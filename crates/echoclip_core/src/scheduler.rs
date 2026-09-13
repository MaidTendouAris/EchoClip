use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

pub const SCHEDULER_SCHEMA_VERSION: u32 = 1;
pub const MAX_SCHEDULED_TASKS: usize = 128;
pub const MAX_SCHEDULE_PRESETS: usize = 9;
pub const MAX_TASK_ACTIONS: usize = 8;
pub const MAX_EXECUTION_HISTORY: usize = 200;
pub const DEFAULT_LATE_GRACE_MILLIS: i64 = 5 * 60 * 1_000;

static NEXT_ID: AtomicU64 = AtomicU64::new(1);

#[derive(Debug)]
pub enum SchedulerError {
    Io(io::Error),
    Serde(serde_json::Error),
    Validation(String),
    NotFound(String),
    RevisionConflict { expected: u64, actual: u64 },
}

impl std::fmt::Display for SchedulerError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io(error) => write!(formatter, "scheduler I/O error: {error}"),
            Self::Serde(error) => write!(formatter, "scheduler JSON error: {error}"),
            Self::Validation(message) => write!(formatter, "{message}"),
            Self::NotFound(id) => write!(formatter, "scheduled task not found: {id}"),
            Self::RevisionConflict { expected, actual } => write!(
                formatter,
                "scheduled task revision conflict: expected {expected}, actual {actual}"
            ),
        }
    }
}

impl std::error::Error for SchedulerError {}
impl From<io::Error> for SchedulerError {
    fn from(value: io::Error) -> Self {
        Self::Io(value)
    }
}
impl From<serde_json::Error> for SchedulerError {
    fn from(value: serde_json::Error) -> Self {
        Self::Serde(value)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ScheduleTaskInput {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub expected_revision: Option<u64>,
    pub name: String,
    #[serde(default = "default_name_prefix")]
    pub name_prefix: String,
    #[serde(default = "default_true")]
    pub enabled: bool,
    pub trigger: ScheduleTriggerInput,
    pub actions: Vec<ScheduledAction>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(
    tag = "type",
    rename_all = "snake_case",
    rename_all_fields = "camelCase"
)]
pub enum ScheduleTriggerInput {
    Countdown {
        delay_millis: u64,
    },
    TimePoint {
        due_at_utc_millis: i64,
        local_datetime: String,
        timezone_id: String,
        utc_offset_minutes: i32,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(
    tag = "type",
    rename_all = "snake_case",
    rename_all_fields = "camelCase"
)]
pub enum ScheduleTrigger {
    Countdown {
        created_at_utc_millis: i64,
        delay_millis: u64,
        due_at_utc_millis: i64,
    },
    TimePoint {
        due_at_utc_millis: i64,
        local_datetime: String,
        timezone_id: String,
        utc_offset_minutes: i32,
    },
}
impl ScheduleTrigger {
    pub fn due_at_utc_millis(&self) -> i64 {
        match self {
            Self::Countdown {
                due_at_utc_millis, ..
            }
            | Self::TimePoint {
                due_at_utc_millis, ..
            } => *due_at_utc_millis,
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ScheduledExportFormat {
    Wav,
    Mp3,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(
    tag = "type",
    rename_all = "snake_case",
    rename_all_fields = "camelCase"
)]
pub enum ScheduledAction {
    SetUploadEnabled {
        enabled: bool,
    },
    StartRecording,
    StopRecording,
    SaveRecent {
        seconds: u32,
        format: ScheduledExportFormat,
        #[serde(default = "default_mp3_bitrate")]
        mp3_bitrate_kbps: u32,
        #[serde(default = "default_true")]
        allow_partial: bool,
    },
}
impl ScheduledAction {
    fn order(&self) -> u8 {
        match self {
            Self::SetUploadEnabled { .. } => 0,
            Self::StartRecording | Self::StopRecording => 1,
            Self::SaveRecent { .. } => 2,
        }
    }
    fn runs_when_very_late(&self) -> bool {
        matches!(
            self,
            Self::StopRecording | Self::SetUploadEnabled { enabled: false }
        )
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ScheduledTaskState {
    Armed,
    Running,
    Succeeded,
    PartiallySucceeded,
    Failed,
    Missed,
    Disabled,
    Canceled,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ScheduledTask {
    pub schema_version: u32,
    pub id: String,
    pub revision: u64,
    pub name: String,
    pub enabled: bool,
    pub trigger: ScheduleTrigger,
    pub actions: Vec<ScheduledAction>,
    pub state: ScheduledTaskState,
    pub created_at_utc_millis: i64,
    pub updated_at_utc_millis: i64,
    pub next_due_utc_millis: Option<i64>,
    #[serde(default)]
    pub last_execution_id: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ActionResultState {
    Succeeded,
    NoOp,
    Partial,
    Failed,
    Missed,
    PlatformBlocked,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ScheduledActionResult {
    pub action_index: usize,
    pub state: ActionResultState,
    #[serde(default)]
    pub error_code: Option<String>,
    #[serde(default)]
    pub output_uri: Option<String>,
    #[serde(default)]
    pub actual_duration_millis: Option<u64>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ExecutionResultState {
    Running,
    Succeeded,
    PartiallySucceeded,
    Failed,
    Missed,
    Interrupted,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ExecutionRecord {
    pub execution_id: String,
    pub task_id: String,
    pub task_revision: u64,
    pub task_name: String,
    pub scheduled_for_utc_millis: i64,
    pub started_at_utc_millis: i64,
    pub finished_at_utc_millis: Option<i64>,
    pub late_by_millis: u64,
    pub action_results: Vec<ScheduledActionResult>,
    pub result: ExecutionResultState,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct DueAction {
    pub action_index: usize,
    pub action: ScheduledAction,
}
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct DueExecution {
    pub execution_id: String,
    pub task_id: String,
    pub task_revision: u64,
    pub task_name: String,
    pub scheduled_for_utc_millis: i64,
    pub late_by_millis: u64,
    pub actions: Vec<DueAction>,
}
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct SchedulerSnapshot {
    pub schema_version: u32,
    pub generated_at_utc_millis: i64,
    pub next_wakeup_utc_millis: Option<i64>,
    pub tasks: Vec<ScheduledTask>,
    pub history: Vec<ExecutionRecord>,
    pub presets: Vec<SchedulePreset>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct SchedulePreset {
    pub id: String,
    pub name: String,
    pub enabled: bool,
    pub trigger: ScheduleTriggerInput,
    pub actions: Vec<ScheduledAction>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SchedulerFile {
    schema_version: u32,
    tasks: Vec<ScheduledTask>,
    history: Vec<ExecutionRecord>,
    #[serde(default)]
    presets: Vec<SchedulePreset>,
}
impl Default for SchedulerFile {
    fn default() -> Self {
        Self {
            schema_version: SCHEDULER_SCHEMA_VERSION,
            tasks: Vec::new(),
            history: Vec::new(),
            presets: Vec::new(),
        }
    }
}

pub struct Scheduler {
    directory: PathBuf,
    state_path: PathBuf,
    state: SchedulerFile,
}

impl Scheduler {
    pub fn open(core_work_dir: impl AsRef<Path>) -> Result<Self, SchedulerError> {
        let directory = core_work_dir.as_ref().join(".echoclip").join("scheduler");
        fs::create_dir_all(&directory)?;
        let state_path = directory.join("state-v1.json");
        let mut scheduler = Self {
            directory,
            state_path,
            state: SchedulerFile::default(),
        };
        if scheduler.state_path.exists() {
            match fs::read_to_string(&scheduler.state_path)
                .map_err(SchedulerError::from)
                .and_then(|json| serde_json::from_str::<SchedulerFile>(&json).map_err(Into::into))
            {
                Ok(state) if state.schema_version == SCHEDULER_SCHEMA_VERSION => {
                    scheduler.state = state
                }
                Ok(state) => {
                    return Err(SchedulerError::Validation(format!(
                        "unsupported scheduler schema version {}",
                        state.schema_version
                    )));
                }
                Err(error) => {
                    let quarantine = scheduler
                        .directory
                        .join(format!("state-v1.corrupt-{}.json", now_utc_millis().max(0)));
                    fs::rename(&scheduler.state_path, quarantine)?;
                    return Err(error);
                }
            }
        }
        if scheduler.reconcile_interrupted(now_utc_millis()) {
            scheduler.persist()?;
        }
        Ok(scheduler)
    }

    pub fn snapshot(&self, now: i64) -> SchedulerSnapshot {
        let mut tasks = self.state.tasks.clone();
        tasks.sort_by_key(|task| task.next_due_utc_millis.unwrap_or(i64::MAX));
        let mut history = self.state.history.clone();
        history.sort_by_key(|record| std::cmp::Reverse(record.started_at_utc_millis));
        SchedulerSnapshot {
            schema_version: SCHEDULER_SCHEMA_VERSION,
            generated_at_utc_millis: now,
            next_wakeup_utc_millis: self.next_wakeup_utc_millis(),
            tasks,
            history,
            presets: self.state.presets.clone(),
        }
    }
    pub fn snapshot_json(&self, now: i64) -> Result<String, SchedulerError> {
        Ok(serde_json::to_string(&self.snapshot(now))?)
    }
    // The editor JSON transport accepts task input or a preset command.
    // Saving a preset never arms or executes a task.
    pub fn editor_command_json(&mut self, json: &str, now: i64) -> Result<(), SchedulerError> {
        let value: serde_json::Value = serde_json::from_str(json)?;
        match value.get("operation").and_then(|v| v.as_str()) {
            None => {
                self.upsert_json(json, now)?;
            }
            Some("save_preset") => {
                self.save_preset(serde_json::from_value(value["task"].clone())?, now)?;
            }
            Some("delete_preset") => {
                let id = value["id"]
                    .as_str()
                    .ok_or_else(|| SchedulerError::Validation("INVALID_PRESET_ID".into()))?;
                self.delete_preset(id)?;
            }
            _ => {
                return Err(SchedulerError::Validation(
                    "UNKNOWN_EDITOR_OPERATION".into(),
                ));
            }
        }
        Ok(())
    }
    pub fn save_preset(
        &mut self,
        mut input: ScheduleTaskInput,
        now: i64,
    ) -> Result<SchedulePreset, SchedulerError> {
        if self.state.presets.len() >= MAX_SCHEDULE_PRESETS {
            return Err(SchedulerError::Validation("PRESET_LIMIT_REACHED".into()));
        }
        input.name = self.resolve_name(&input.name, &input.name_prefix)?;
        normalize_actions(&mut input.actions)?;
        if input.actions.is_empty() {
            return Err(SchedulerError::Validation(
                "scheduled task must contain at least one action".into(),
            ));
        }
        // Revalidate saved time points when a task is created from this template.
        resolve_trigger(input.trigger.clone(), false, now)?;
        let preset = SchedulePreset {
            id: new_id("preset", now),
            name: input.name,
            enabled: input.enabled,
            trigger: input.trigger,
            actions: input.actions,
        };
        let previous = self.state.clone();
        self.state.presets.push(preset.clone());
        if let Err(error) = self.persist() {
            self.state = previous;
            return Err(error);
        }
        Ok(preset)
    }
    pub fn delete_preset(&mut self, id: &str) -> Result<(), SchedulerError> {
        let index = self
            .state
            .presets
            .iter()
            .position(|p| p.id == id)
            .ok_or_else(|| SchedulerError::NotFound(id.into()))?;
        let previous = self.state.clone();
        self.state.presets.remove(index);
        if let Err(error) = self.persist() {
            self.state = previous;
            return Err(error);
        }
        Ok(())
    }
    fn resolve_name(&self, name: &str, prefix: &str) -> Result<String, SchedulerError> {
        if !name.trim().is_empty() {
            validate_name(name)?;
            return Ok(name.trim().into());
        }
        let prefix = if prefix.trim().is_empty() {
            "Task"
        } else {
            prefix.trim()
        };
        for number in 1.. {
            let candidate = format!("{prefix} {number}");
            validate_name(&candidate)?;
            if !self.state.tasks.iter().any(|t| t.name == candidate)
                && !self.state.presets.iter().any(|p| p.name == candidate)
            {
                return Ok(candidate);
            }
        }
        unreachable!()
    }
    pub fn upsert_json(&mut self, json: &str, now: i64) -> Result<ScheduledTask, SchedulerError> {
        self.upsert(serde_json::from_str(json)?, now)
    }
    pub fn upsert(
        &mut self,
        mut input: ScheduleTaskInput,
        now: i64,
    ) -> Result<ScheduledTask, SchedulerError> {
        input.name = self.resolve_name(&input.name, &input.name_prefix)?;
        normalize_actions(&mut input.actions)?;
        if input.actions.is_empty() {
            return Err(SchedulerError::Validation(
                "scheduled task must contain at least one action".into(),
            ));
        }
        let existing_index = input
            .id
            .as_deref()
            .and_then(|id| self.state.tasks.iter().position(|task| task.id == id));
        if existing_index.is_none() && self.state.tasks.len() >= MAX_SCHEDULED_TASKS {
            return Err(SchedulerError::Validation(format!(
                "scheduled task limit reached ({MAX_SCHEDULED_TASKS})"
            )));
        }
        let (id, revision, created_at) = if let Some(index) = existing_index {
            let existing = &self.state.tasks[index];
            let expected = input.expected_revision.unwrap_or(existing.revision);
            if expected != existing.revision {
                return Err(SchedulerError::RevisionConflict {
                    expected,
                    actual: existing.revision,
                });
            }
            (
                existing.id.clone(),
                existing.revision.saturating_add(1),
                existing.created_at_utc_millis,
            )
        } else {
            if input.id.as_deref().is_some_and(|id| !id.trim().is_empty()) {
                return Err(SchedulerError::NotFound(input.id.unwrap()));
            }
            (new_id("task", now), 1, now)
        };
        let trigger = resolve_trigger(input.trigger, input.enabled, now)?;
        let task = ScheduledTask {
            schema_version: SCHEDULER_SCHEMA_VERSION,
            id,
            revision,
            name: input.name.trim().to_string(),
            enabled: input.enabled,
            next_due_utc_millis: input.enabled.then(|| trigger.due_at_utc_millis()),
            trigger,
            actions: input.actions,
            state: if input.enabled {
                ScheduledTaskState::Armed
            } else {
                ScheduledTaskState::Disabled
            },
            created_at_utc_millis: created_at,
            updated_at_utc_millis: now,
            last_execution_id: None,
        };
        if let Some(index) = existing_index {
            self.state.tasks[index] = task.clone();
        } else {
            self.state.tasks.push(task.clone());
        }
        self.persist()?;
        Ok(task)
    }
    pub fn delete(&mut self, id: &str) -> Result<(), SchedulerError> {
        let before = self.state.tasks.len();
        self.state.tasks.retain(|task| task.id != id);
        if before == self.state.tasks.len() {
            return Err(SchedulerError::NotFound(id.into()));
        }
        self.persist()
    }
    pub fn set_enabled(
        &mut self,
        id: &str,
        expected_revision: Option<u64>,
        enabled: bool,
        now: i64,
    ) -> Result<ScheduledTask, SchedulerError> {
        let task = self
            .state
            .tasks
            .iter_mut()
            .find(|task| task.id == id)
            .ok_or_else(|| SchedulerError::NotFound(id.into()))?;
        if let Some(expected) = expected_revision {
            if expected != task.revision {
                return Err(SchedulerError::RevisionConflict {
                    expected,
                    actual: task.revision,
                });
            }
        }
        let recalculated_countdown_due = if enabled {
            match &task.trigger {
                ScheduleTrigger::Countdown { delay_millis, .. } => {
                    Some(checked_due(now, *delay_millis)?)
                }
                ScheduleTrigger::TimePoint {
                    due_at_utc_millis, ..
                } if *due_at_utc_millis <= now => {
                    return Err(SchedulerError::Validation("TIME_POINT_IN_PAST".into()));
                }
                ScheduleTrigger::TimePoint { .. } => None,
            }
        } else {
            None
        };
        task.revision = task.revision.saturating_add(1);
        task.updated_at_utc_millis = now;
        task.enabled = enabled;
        task.last_execution_id = None;
        if enabled {
            if let (
                ScheduleTrigger::Countdown {
                    created_at_utc_millis,
                    due_at_utc_millis,
                    ..
                },
                Some(due),
            ) = (&mut task.trigger, recalculated_countdown_due)
            {
                *created_at_utc_millis = now;
                *due_at_utc_millis = due;
            }
            task.state = ScheduledTaskState::Armed;
            task.next_due_utc_millis = Some(task.trigger.due_at_utc_millis());
        } else {
            task.state = ScheduledTaskState::Disabled;
            task.next_due_utc_millis = None;
        }
        let output = task.clone();
        self.persist()?;
        Ok(output)
    }
    pub fn next_wakeup_utc_millis(&self) -> Option<i64> {
        self.state
            .tasks
            .iter()
            .filter(|task| task.enabled && task.state == ScheduledTaskState::Armed)
            .filter_map(|task| task.next_due_utc_millis)
            .min()
    }
    pub fn tick(&mut self, now: i64) -> Result<Vec<DueExecution>, SchedulerError> {
        let indices: Vec<usize> = self
            .state
            .tasks
            .iter()
            .enumerate()
            .filter(|(_, task)| {
                task.enabled
                    && task.state == ScheduledTaskState::Armed
                    && task.next_due_utc_millis.is_some_and(|due| due <= now)
            })
            .map(|(index, _)| index)
            .collect();
        if indices.is_empty() {
            return Ok(Vec::new());
        }
        let mut due = Vec::new();
        for index in indices {
            let task = &mut self.state.tasks[index];
            let scheduled_for = task.trigger.due_at_utc_millis();
            let late = now.saturating_sub(scheduled_for).max(0) as u64;
            let execution_id = new_id("execution", now);
            let very_late = late > DEFAULT_LATE_GRACE_MILLIS as u64;
            let mut actions = Vec::new();
            let mut action_results = Vec::new();
            for (action_index, action) in task.actions.iter().cloned().enumerate() {
                if very_late && !action.runs_when_very_late() {
                    action_results.push(ScheduledActionResult {
                        action_index,
                        state: ActionResultState::Missed,
                        error_code: Some("LATE_GRACE_EXCEEDED".into()),
                        output_uri: None,
                        actual_duration_millis: None,
                    });
                } else {
                    actions.push(DueAction {
                        action_index,
                        action,
                    });
                }
            }
            task.enabled = false;
            task.next_due_utc_millis = None;
            task.last_execution_id = Some(execution_id.clone());
            task.state = if actions.is_empty() {
                ScheduledTaskState::Missed
            } else {
                ScheduledTaskState::Running
            };
            self.state.history.push(ExecutionRecord {
                execution_id: execution_id.clone(),
                task_id: task.id.clone(),
                task_revision: task.revision,
                task_name: task.name.clone(),
                scheduled_for_utc_millis: scheduled_for,
                started_at_utc_millis: now,
                finished_at_utc_millis: actions.is_empty().then_some(now),
                late_by_millis: late,
                action_results,
                result: if actions.is_empty() {
                    ExecutionResultState::Missed
                } else {
                    ExecutionResultState::Running
                },
            });
            if !actions.is_empty() {
                due.push(DueExecution {
                    execution_id,
                    task_id: task.id.clone(),
                    task_revision: task.revision,
                    task_name: task.name.clone(),
                    scheduled_for_utc_millis: scheduled_for,
                    late_by_millis: late,
                    actions,
                });
            }
        }
        self.prune_history();
        self.persist()?;
        Ok(due)
    }
    pub fn complete_execution(
        &mut self,
        execution_id: &str,
        mut results: Vec<ScheduledActionResult>,
        now: i64,
    ) -> Result<ExecutionRecord, SchedulerError> {
        let record = self
            .state
            .history
            .iter_mut()
            .find(|record| record.execution_id == execution_id)
            .ok_or_else(|| SchedulerError::NotFound(execution_id.into()))?;
        if record.result != ExecutionResultState::Running {
            return Ok(record.clone());
        }
        record.action_results.append(&mut results);
        record
            .action_results
            .sort_by_key(|result| result.action_index);
        record.finished_at_utc_millis = Some(now);
        record.result = summarize_results(&record.action_results);
        if let Some(task) = self.state.tasks.iter_mut().find(|task| {
            task.id == record.task_id && task.last_execution_id.as_deref() == Some(execution_id)
        }) {
            task.state = match record.result {
                ExecutionResultState::Succeeded => ScheduledTaskState::Succeeded,
                ExecutionResultState::PartiallySucceeded => ScheduledTaskState::PartiallySucceeded,
                ExecutionResultState::Missed => ScheduledTaskState::Missed,
                ExecutionResultState::Running => ScheduledTaskState::Running,
                ExecutionResultState::Failed | ExecutionResultState::Interrupted => {
                    ScheduledTaskState::Failed
                }
            };
        }
        let output = record.clone();
        self.persist()?;
        Ok(output)
    }
    fn reconcile_interrupted(&mut self, now: i64) -> bool {
        let mut changed = false;
        for record in &mut self.state.history {
            if record.result == ExecutionResultState::Running {
                record.result = ExecutionResultState::Interrupted;
                record.finished_at_utc_millis = Some(now);
                changed = true;
                if let Some(task) = self.state.tasks.iter_mut().find(|task| {
                    task.id == record.task_id
                        && task.last_execution_id.as_deref() == Some(record.execution_id.as_str())
                }) {
                    task.state = ScheduledTaskState::Failed;
                    task.enabled = false;
                    task.next_due_utc_millis = None;
                }
            }
        }
        changed
    }
    fn prune_history(&mut self) {
        if self.state.history.len() > MAX_EXECUTION_HISTORY {
            self.state
                .history
                .drain(..self.state.history.len() - MAX_EXECUTION_HISTORY);
        }
    }
    fn persist(&self) -> Result<(), SchedulerError> {
        let temporary = self.directory.join("state-v1.json.tmp");
        let mut file = OpenOptions::new()
            .create(true)
            .truncate(true)
            .write(true)
            .open(&temporary)?;
        file.write_all(&serde_json::to_vec_pretty(&self.state)?)?;
        file.flush()?;
        file.sync_all()?;
        drop(file);
        atomic_replace(&temporary, &self.state_path)?;
        if let Ok(directory) = File::open(&self.directory) {
            let _ = directory.sync_all();
        }
        Ok(())
    }
}

pub fn now_utc_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .min(i64::MAX as u128) as i64
}
fn default_name_prefix() -> String {
    "Task".into()
}
fn default_true() -> bool {
    true
}
fn default_mp3_bitrate() -> u32 {
    128
}
fn validate_name(name: &str) -> Result<(), SchedulerError> {
    let count = name.trim().chars().count();
    if count == 0 || count > 80 {
        return Err(SchedulerError::Validation(
            "task name must contain 1 to 80 characters".into(),
        ));
    }
    Ok(())
}
fn normalize_actions(actions: &mut Vec<ScheduledAction>) -> Result<(), SchedulerError> {
    if actions.len() > MAX_TASK_ACTIONS {
        return Err(SchedulerError::Validation(format!(
            "task contains more than {MAX_TASK_ACTIONS} actions"
        )));
    }
    let starts = actions
        .iter()
        .filter(|a| matches!(a, ScheduledAction::StartRecording))
        .count();
    let stops = actions
        .iter()
        .filter(|a| matches!(a, ScheduledAction::StopRecording))
        .count();
    if starts != 0 && stops != 0 {
        return Err(SchedulerError::Validation("ACTION_CONFLICT".into()));
    }
    if starts > 1 || stops > 1 {
        return Err(SchedulerError::Validation(
            "duplicate recording action".into(),
        ));
    }
    if actions
        .iter()
        .filter(|a| matches!(a, ScheduledAction::SetUploadEnabled { .. }))
        .count()
        > 1
    {
        return Err(SchedulerError::Validation("duplicate upload action".into()));
    }
    if actions
        .iter()
        .filter(|a| matches!(a, ScheduledAction::SaveRecent { .. }))
        .count()
        > 1
    {
        return Err(SchedulerError::Validation("duplicate save action".into()));
    }
    for action in actions.iter_mut() {
        if let ScheduledAction::SaveRecent {
            seconds,
            mp3_bitrate_kbps,
            ..
        } = action
        {
            if *seconds == 0 || *seconds > 86_400 {
                return Err(SchedulerError::Validation("DURATION_OUT_OF_RANGE".into()));
            }
            *mp3_bitrate_kbps = sanitize_bitrate(*mp3_bitrate_kbps);
        }
    }
    actions.sort_by_key(ScheduledAction::order);
    Ok(())
}
fn resolve_trigger(
    input: ScheduleTriggerInput,
    enabled: bool,
    now: i64,
) -> Result<ScheduleTrigger, SchedulerError> {
    match input {
        ScheduleTriggerInput::Countdown { delay_millis } => {
            if delay_millis == 0 || delay_millis > 365 * 24 * 60 * 60 * 1_000 {
                return Err(SchedulerError::Validation(
                    "countdown must be between one millisecond and 365 days".into(),
                ));
            }
            Ok(ScheduleTrigger::Countdown {
                created_at_utc_millis: now,
                delay_millis,
                due_at_utc_millis: checked_due(now, delay_millis)?,
            })
        }
        ScheduleTriggerInput::TimePoint {
            due_at_utc_millis,
            local_datetime,
            timezone_id,
            utc_offset_minutes,
        } => {
            if enabled && due_at_utc_millis <= now {
                return Err(SchedulerError::Validation("TIME_POINT_IN_PAST".into()));
            }
            if local_datetime.trim().is_empty() || timezone_id.trim().is_empty() {
                return Err(SchedulerError::Validation(
                    "time point requires local date/time and timezone".into(),
                ));
            }
            if !(-1440..=1440).contains(&utc_offset_minutes) {
                return Err(SchedulerError::Validation("invalid UTC offset".into()));
            }
            Ok(ScheduleTrigger::TimePoint {
                due_at_utc_millis,
                local_datetime,
                timezone_id,
                utc_offset_minutes,
            })
        }
    }
}
fn checked_due(now: i64, delay_millis: u64) -> Result<i64, SchedulerError> {
    let delay = i64::try_from(delay_millis)
        .map_err(|_| SchedulerError::Validation("countdown is too large".into()))?;
    now.checked_add(delay)
        .ok_or_else(|| SchedulerError::Validation("countdown overflows clock".into()))
}
fn summarize_results(results: &[ScheduledActionResult]) -> ExecutionResultState {
    let successes = results
        .iter()
        .filter(|result| {
            matches!(
                result.state,
                ActionResultState::Succeeded | ActionResultState::NoOp | ActionResultState::Partial
            )
        })
        .count();
    if successes == results.len() {
        ExecutionResultState::Succeeded
    } else if successes == 0 && results.iter().all(|r| r.state == ActionResultState::Missed) {
        ExecutionResultState::Missed
    } else if successes == 0 {
        ExecutionResultState::Failed
    } else {
        ExecutionResultState::PartiallySucceeded
    }
}
fn sanitize_bitrate(value: u32) -> u32 {
    [64_u32, 96, 128, 160, 192, 256, 320]
        .into_iter()
        .min_by_key(|candidate| candidate.abs_diff(value))
        .unwrap_or(128)
}
fn new_id(prefix: &str, now: i64) -> String {
    format!(
        "{prefix}-{now:016x}-{:016x}",
        NEXT_ID.fetch_add(1, Ordering::Relaxed)
    )
}
#[cfg(windows)]
fn atomic_replace(source: &Path, destination: &Path) -> io::Result<()> {
    if destination.exists() {
        fs::remove_file(destination)?;
    }
    fs::rename(source, destination)
}
#[cfg(not(windows))]
fn atomic_replace(source: &Path, destination: &Path) -> io::Result<()> {
    fs::rename(source, destination)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn root(name: &str) -> PathBuf {
        let path = std::env::temp_dir().join(new_id(name, now_utc_millis()));
        fs::create_dir_all(&path).unwrap();
        path
    }
    fn input(actions: Vec<ScheduledAction>) -> ScheduleTaskInput {
        ScheduleTaskInput {
            id: None,
            expected_revision: None,
            name: "task".into(),
            name_prefix: default_name_prefix(),
            enabled: true,
            trigger: ScheduleTriggerInput::Countdown { delay_millis: 100 },
            actions,
        }
    }
    #[test]
    fn persists_and_deduplicates_tick() {
        let path = root("scheduler");
        let mut scheduler = Scheduler::open(&path).unwrap();
        let task = scheduler
            .upsert(input(vec![ScheduledAction::StartRecording]), 1_000)
            .unwrap();
        assert_eq!(scheduler.tick(1_100).unwrap().len(), 1);
        assert!(scheduler.tick(1_100).unwrap().is_empty());
        drop(scheduler);
        assert_eq!(
            Scheduler::open(&path).unwrap().snapshot(2_000).tasks[0].id,
            task.id
        );
        fs::remove_dir_all(path).unwrap();
    }
    #[test]
    fn orders_actions_and_applies_late_policy() {
        let path = root("scheduler-order");
        let mut scheduler = Scheduler::open(&path).unwrap();
        let task = scheduler
            .upsert(
                input(vec![
                    ScheduledAction::SaveRecent {
                        seconds: 30,
                        format: ScheduledExportFormat::Mp3,
                        mp3_bitrate_kbps: 129,
                        allow_partial: true,
                    },
                    ScheduledAction::StopRecording,
                    ScheduledAction::SetUploadEnabled { enabled: false },
                ]),
                1_000,
            )
            .unwrap();
        assert!(matches!(
            task.actions[0],
            ScheduledAction::SetUploadEnabled { .. }
        ));
        let due = scheduler.tick(1_101 + DEFAULT_LATE_GRACE_MILLIS).unwrap();
        assert_eq!(due[0].actions.len(), 2);
        fs::remove_dir_all(path).unwrap();
    }
    #[test]
    fn enabling_expired_time_point_does_not_mutate_task() {
        let path = root("scheduler-expired");
        let mut scheduler = Scheduler::open(&path).unwrap();
        let task = scheduler
            .upsert(
                ScheduleTaskInput {
                    id: None,
                    expected_revision: None,
                    name: "expired".into(),
                    name_prefix: default_name_prefix(),
                    enabled: false,
                    trigger: ScheduleTriggerInput::TimePoint {
                        due_at_utc_millis: 1_500,
                        local_datetime: "1970-01-01T00:00:01.500".into(),
                        timezone_id: "UTC".into(),
                        utc_offset_minutes: 0,
                    },
                    actions: vec![ScheduledAction::StartRecording],
                },
                1_000,
            )
            .unwrap();
        assert!(
            scheduler
                .set_enabled(&task.id, Some(task.revision), true, 2_000)
                .is_err()
        );
        let unchanged = &scheduler.snapshot(2_000).tasks[0];
        assert_eq!(unchanged.revision, task.revision);
        assert!(!unchanged.enabled);
        assert_eq!(unchanged.state, ScheduledTaskState::Disabled);
        fs::remove_dir_all(path).unwrap();
    }
    #[test]
    fn rejects_recording_conflict_and_restarts_countdown() {
        let path = root("scheduler-conflict");
        let mut scheduler = Scheduler::open(&path).unwrap();
        assert!(
            scheduler
                .upsert(
                    input(vec![
                        ScheduledAction::StartRecording,
                        ScheduledAction::StopRecording
                    ]),
                    1_000
                )
                .is_err()
        );
        let task = scheduler
            .upsert(input(vec![ScheduledAction::StartRecording]), 1_000)
            .unwrap();
        let disabled = scheduler
            .set_enabled(&task.id, Some(task.revision), false, 1_050)
            .unwrap();
        let enabled = scheduler
            .set_enabled(&task.id, Some(disabled.revision), true, 2_000)
            .unwrap();
        assert_eq!(enabled.next_due_utc_millis, Some(2_100));
        fs::remove_dir_all(path).unwrap();
    }
    #[test]
    fn presets_persist_enforce_limit_and_never_arm_tasks() {
        let path = root("presets");
        let mut scheduler = Scheduler::open(&path).unwrap();
        let mut template = input(vec![
            ScheduledAction::StartRecording,
            ScheduledAction::SetUploadEnabled { enabled: false },
        ]);
        template.name.clear();
        template.name_prefix = "预设".into();
        let command = serde_json::json!({"operation": "save_preset", "task": template}).to_string();
        for _ in 0..9 {
            scheduler.editor_command_json(&command, 1_000).unwrap();
        }
        assert!(
            scheduler
                .editor_command_json(&command, 1_000)
                .unwrap_err()
                .to_string()
                .contains("PRESET_LIMIT_REACHED")
        );
        assert_eq!(scheduler.snapshot(1_000).presets.len(), 9);
        assert_eq!(scheduler.next_wakeup_utc_millis(), None);
        assert!(scheduler.tick(2_000).unwrap().is_empty());
        drop(scheduler);
        let mut scheduler = Scheduler::open(&path).unwrap();
        let preset = scheduler.snapshot(2_000).presets[0].clone();
        assert_eq!(preset.name, "预设 1");
        assert!(matches!(
            preset.actions[0],
            ScheduledAction::SetUploadEnabled { enabled: false }
        ));
        // Instantiating a preset starts a fresh countdown and a distinct task ID.
        let mut task_input = input(preset.actions.clone());
        task_input.trigger = preset.trigger;
        let task = scheduler.upsert(task_input, 3_000).unwrap();
        assert_eq!(task.next_due_utc_millis, Some(3_100));
        assert_ne!(task.id, preset.id);
        scheduler
            .editor_command_json(
                &serde_json::json!({"operation":"delete_preset", "id":preset.id}).to_string(),
                3_000,
            )
            .unwrap();
        scheduler.editor_command_json(&command, 3_000).unwrap();
        assert_eq!(scheduler.snapshot(3_000).tasks.len(), 1);
        assert_eq!(scheduler.snapshot(3_000).presets.len(), 9);
        fs::remove_dir_all(path).unwrap();
    }
    #[test]
    fn blank_names_are_generated_in_requested_language_and_survive_legacy_state() {
        let path = root("preset-migration");
        let mut scheduler = Scheduler::open(&path).unwrap();
        let task = scheduler
            .upsert(input(vec![ScheduledAction::StopRecording]), 1_000)
            .unwrap();
        let mut legacy = serde_json::to_value(&scheduler.state).unwrap();
        legacy.as_object_mut().unwrap().remove("presets");
        fs::write(&scheduler.state_path, serde_json::to_vec(&legacy).unwrap()).unwrap();
        drop(scheduler);
        let mut scheduler = Scheduler::open(&path).unwrap();
        assert_eq!(scheduler.snapshot(2_000).tasks[0], task);
        assert!(scheduler.snapshot(2_000).presets.is_empty());
        for (prefix, expected) in [("Task", "Task 1"), ("Task", "Task 2"), ("任务", "任务 1")] {
            let mut unnamed = input(vec![ScheduledAction::StopRecording]);
            unnamed.name = "  ".into();
            unnamed.name_prefix = prefix.into();
            assert_eq!(scheduler.upsert(unnamed, 2_000).unwrap().name, expected);
        }
        fs::remove_dir_all(path).unwrap();
    }
    #[test]
    fn invalid_presets_do_not_change_state_and_past_time_points_require_review() {
        let path = root("preset-validation");
        let mut scheduler = Scheduler::open(&path).unwrap();
        assert!(scheduler.save_preset(input(vec![]), 1_000).is_err());
        assert!(
            scheduler
                .save_preset(
                    input(vec![
                        ScheduledAction::StartRecording,
                        ScheduledAction::StopRecording
                    ]),
                    1_000
                )
                .is_err()
        );
        assert!(scheduler.snapshot(1_000).presets.is_empty());
        let mut time_point = input(vec![ScheduledAction::StopRecording]);
        time_point.trigger = ScheduleTriggerInput::TimePoint {
            due_at_utc_millis: 500,
            local_datetime: "1970-01-01T00:00:00.500".into(),
            timezone_id: "UTC".into(),
            utc_offset_minutes: 0,
        };
        scheduler.save_preset(time_point.clone(), 1_000).unwrap();
        assert!(scheduler.upsert(time_point, 1_000).is_err());
        assert!(scheduler.snapshot(1_000).tasks.is_empty());
        fs::remove_dir_all(path).unwrap();
    }
}
