//! Reproduce long-session writer/status contention without recording real audio.
//! Run: cargo run --release -p echoclip_core --example long_recording_probe
//! PCM is scaled to 100 Hz; 60-second segment counts and 10 ms callbacks are real.
use echoclip_core::{AudioConfig, CoreConfig, RecorderWorker, SegmentInfo, SegmentedRecorder};
use std::{
    fs,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

fn main() {
    for segment_count in [1_u64, 540, 1440] {
        let config = CoreConfig {
            audio: AudioConfig {
                sample_rate: 100,
                channels: 1,
            },
            segment_seconds: 60,
            max_replay_seconds: 24 * 60 * 60,
            work_dir: std::env::temp_dir().join(format!(
                "echoclip-long-probe-{}-{}-{}",
                std::process::id(),
                SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap()
                    .as_nanos(),
                segment_count
            )),
        };
        let recorder = SegmentedRecorder::start(config.clone()).unwrap();
        let mut manifest = recorder.manifest().clone();
        let session_dir = recorder.session_dir().to_owned();
        drop(recorder);
        for index in 0..segment_count {
            let name = format!("segment-{index:06}.pcm");
            fs::write(session_dir.join(&name), vec![0_u8; 12000]).unwrap();
            manifest.segments.push(SegmentInfo {
                index,
                file_name: name,
                start_sample: index * 6000,
                sample_count: 6000,
                complete: true,
            });
        }
        manifest.total_samples_written = segment_count * 6000;
        fs::write(
            session_dir.join("manifest.json"),
            manifest.to_json().unwrap(),
        )
        .unwrap();
        let mut worker = RecorderWorker::start(config.clone()).unwrap();
        let done = Arc::new(AtomicBool::new(false));
        let start = Instant::now();
        let (accepted, latencies) = thread::scope(|scope| {
            let monitor = scope.spawn(|| {
                let mut latencies = Vec::new();
                while !done.load(Ordering::Relaxed) {
                    let now = Instant::now();
                    let _ = worker.status();
                    latencies.push(now.elapsed().as_secs_f64() * 1000.0);
                    thread::sleep(Duration::from_millis(50));
                }
                latencies
            });
            let mut accepted = 0;
            for index in 0..400_u64 {
                let deadline = start + Duration::from_millis(index * 10);
                thread::sleep(deadline.saturating_duration_since(Instant::now()));
                if worker.push_samples(&[42]).is_ok() {
                    accepted += 1;
                }
            }
            worker.flush().unwrap();
            done.store(true, Ordering::Relaxed);
            (accepted, monitor.join().unwrap())
        });
        let elapsed = start.elapsed().as_secs_f64();
        let status = worker.status();
        assert_eq!(
            status.total_samples_written,
            segment_count * 6000 + accepted
        );
        let mut latencies = latencies;
        latencies.sort_by(f64::total_cmp);
        println!(
            "{}",
            serde_json::json!({
                "initial_segments": segment_count, "simulated_hours": segment_count as f64 / 60.0,
                "attempted_chunks": 400, "accepted_chunks": accepted, "dropped_chunks": status.dropped_chunks,
                "elapsed_seconds": elapsed, "status_samples": latencies.len(),
                "status_p95_ms": latencies[(latencies.len() - 1) * 95 / 100],
                "status_max_ms": latencies.last().unwrap(), "queued_after_flush": status.queued_chunks,
            })
        );
        worker.stop();
        drop(worker);
        // Only remove the unique temporary directory created by this probe.
        let cleanup_path = fs::canonicalize(&config.work_dir).unwrap();
        assert_eq!(
            cleanup_path.parent().unwrap(),
            fs::canonicalize(std::env::temp_dir()).unwrap()
        );
        assert!(
            cleanup_path
                .file_name()
                .unwrap()
                .to_string_lossy()
                .starts_with("echoclip-long-probe-")
        );
        fs::remove_dir_all(cleanup_path).unwrap();
    }
}
