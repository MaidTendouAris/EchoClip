use super::tests::{read_wav_samples, test_config, test_dir};
use super::*;

#[test]
fn pcm_accounting_includes_buffered_audio_and_tracks_retention() {
    let work_dir = test_dir("pcm-accounting");
    let mut recorder = SegmentedRecorder::start(test_config(&work_dir, 2, 4)).unwrap();
    recorder.push_samples(&[1]).unwrap();
    assert_eq!(recorder.temp_bytes(), 2);
    recorder.push_samples(&[2, 3, 4, 5]).unwrap();
    // The oldest full segment is evicted as soon as the limit is reached.
    assert_eq!(recorder.temp_bytes(), 6);
    recorder.push_samples(&[6]).unwrap();
    assert_eq!(recorder.temp_bytes(), 4);
    let output = work_dir.join("latest.wav");
    recorder.save_latest_wav(4, &output).unwrap();
    assert_eq!(read_wav_samples(&output), vec![5, 6]);
    assert_eq!(disk_pcm_bytes(&recorder), recorder.temp_bytes());
    drop(recorder);
    remove_test_dir(&work_dir);
}

#[test]
fn pinned_segments_count_until_the_export_releases_them() {
    let work_dir = test_dir("pcm-pinned");
    let mut recorder = SegmentedRecorder::start(test_config(&work_dir, 2, 4)).unwrap();
    recorder
        .push_samples_defer_trim(&[1, 2, 3, 4, 5, 6])
        .unwrap();
    let pinned_name = recorder.manifest.segments[0].file_name.clone();
    recorder
        .trim_expired_segments_except(&HashSet::from([pinned_name.clone()]))
        .unwrap();
    assert_eq!(recorder.temp_bytes(), 8);
    assert_eq!(recorder.available_samples(), 2);
    assert_eq!(recorder.snapshot().unwrap().available_millis(), 2000);
    assert_eq!(recorder.manifest.segments.len(), 2);
    assert!(recorder.session_dir.join(&pinned_name).is_file());
    assert_eq!(disk_pcm_bytes(&recorder), recorder.temp_bytes());
    recorder.trim_expired_segments().unwrap();
    assert_eq!(recorder.temp_bytes(), 4);
    assert!(!recorder.session_dir.join(&pinned_name).exists());
    let output = work_dir.join("latest.wav");
    recorder.save_latest_wav(2, &output).unwrap();
    assert_eq!(read_wav_samples(&output), vec![5, 6]);
    drop(recorder);
    remove_test_dir(&work_dir);
}

#[test]
fn failed_trim_keeps_remaining_manifest_and_can_be_retried() {
    let work_dir = test_dir("pcm-trim-error");
    let mut recorder = SegmentedRecorder::start(test_config(&work_dir, 2, 4)).unwrap();
    recorder
        .push_samples_defer_trim(&[1, 2, 3, 4, 5, 6])
        .unwrap();
    // A directory in place of one closed PCM file reliably fails remove_file
    // on all platforms, including when tests run with elevated permissions.
    let blocked = recorder
        .session_dir
        .join(&recorder.manifest.segments[1].file_name);
    fs::remove_file(&blocked).unwrap();
    fs::create_dir(&blocked).unwrap();
    fs::write(blocked.join("blocker"), b"test").unwrap();
    assert!(recorder.trim_expired_segments().is_err());
    assert_eq!(
        recorder
            .manifest
            .segments
            .iter()
            .map(|s| s.index)
            .collect::<Vec<_>>(),
        vec![1, 2]
    );
    assert_eq!(recorder.temp_bytes(), 8);
    fs::remove_file(blocked.join("blocker")).unwrap();
    fs::remove_dir(&blocked).unwrap();
    // Missing expired files are also removed from the inventory exactly once.
    recorder.trim_expired_segments().unwrap();
    assert_eq!(recorder.temp_bytes(), 4);
    assert_eq!(recorder.manifest.segments.len(), 1);
    recorder.push_samples(&[7]).unwrap();
    assert_eq!(recorder.temp_bytes(), 6);
    let output = work_dir.join("latest.wav");
    recorder.save_latest_wav(2, &output).unwrap();
    assert_eq!(read_wav_samples(&output), vec![6, 7]);
    drop(recorder);
    remove_test_dir(&work_dir);
}

#[test]
fn recovery_reconciles_pcm_accounting_with_actual_files() {
    let work_dir = test_dir("pcm-recovery-count");
    let config = test_config(&work_dir, 2, 10);
    let mut recorder = SegmentedRecorder::start(config.clone()).unwrap();
    recorder.push_samples(&[1, 2, 3, 4, 5]).unwrap();
    recorder.flush().unwrap();
    let session = recorder.session_dir.clone();
    drop(recorder);
    fs::remove_file(session.join("segment-000000.pcm")).unwrap();
    fs::write(session.join("segment-000001.pcm"), 3_i16.to_le_bytes()).unwrap();
    fs::write(session.join("segment-000003.pcm"), 6_i16.to_le_bytes()).unwrap();
    let mut recovered = SegmentedRecorder::recover_latest_or_start(config).unwrap();
    assert_eq!(recovered.temp_bytes(), 6);
    assert_eq!(recovered.available_samples(), 3);
    assert_eq!(disk_pcm_bytes(&recovered), recovered.temp_bytes());
    recovered.push_samples(&[7]).unwrap();
    assert_eq!(recovered.temp_bytes(), 8);
    let output = work_dir.join("latest.wav");
    recovered.save_latest_wav(10, &output).unwrap();
    assert_eq!(read_wav_samples(&output), vec![3, 5, 6, 7]);
    drop(recovered);
    remove_test_dir(&work_dir);
}

#[test]
fn nine_hour_cache_resumes_and_exports_across_the_recovered_boundary() {
    let work_dir = test_dir("nine-hour-cache");
    let config = test_config(&work_dir, 60, 24 * 60 * 60);
    let recorder = SegmentedRecorder::start(config.clone()).unwrap();
    let mut manifest = recorder.manifest.clone();
    let session = recorder.session_dir.clone();
    drop(recorder);
    for index in 0..540_u64 {
        let file_name = format!("segment-{index:06}.pcm");
        fs::write(session.join(&file_name), vec![0_u8; 120]).unwrap();
        manifest.segments.push(SegmentInfo {
            index,
            file_name,
            start_sample: index * 60,
            sample_count: 60,
            complete: true,
        });
    }
    manifest.total_samples_written = 9 * 60 * 60;
    fs::write(session.join("manifest.json"), manifest.to_json().unwrap()).unwrap();
    let mut worker = RecorderWorker::start(config).unwrap();
    assert_eq!(worker.status().temp_bytes, 9 * 60 * 60 * 2);
    // One callback at a time exercises enqueue/dequeue accounting without a
    // timing threshold that depends on the speed of a CI machine.
    for sample in 1..=100_i16 {
        worker.push_samples(&[sample]).unwrap();
        worker.flush().unwrap();
        let status = worker.status();
        assert_eq!(status.queued_chunks, 0);
        assert_eq!(status.dropped_chunks, 0);
        assert_eq!(status.total_samples_written, 9 * 60 * 60 + sample as u64);
        assert_eq!(status.temp_bytes, status.total_samples_written * 2);
    }
    let samples = worker
        .sync_handle()
        .read_range_i16(9 * 60 * 60 - 2, 9 * 60 * 60 + 100)
        .unwrap();
    let expected: Vec<i16> = [0, 0].into_iter().chain(1..=100).collect();
    assert_eq!(samples, expected);
    worker.stop();
    drop(worker);
    remove_test_dir(&work_dir);
}

fn disk_pcm_bytes(recorder: &SegmentedRecorder) -> u64 {
    recorder
        .manifest
        .segments
        .iter()
        .map(|s| {
            fs::metadata(recorder.session_dir.join(&s.file_name))
                .unwrap()
                .len()
        })
        .sum()
}

fn remove_test_dir(path: &Path) {
    let resolved = fs::canonicalize(path).unwrap();
    assert_eq!(
        resolved.parent().unwrap(),
        fs::canonicalize(std::env::temp_dir()).unwrap()
    );
    assert!(
        resolved
            .file_name()
            .unwrap()
            .to_string_lossy()
            .starts_with("echoclip-core-")
    );
    fs::remove_dir_all(resolved).unwrap();
}

#[test]
fn thirty_minutes_evicts_one_minute_and_pause_recovery_preserves_duration() {
    let path = test_dir("minute-boundary-pause");
    let config = test_config(&path, 60, 1800);
    let mut recorder = SegmentedRecorder::start(config.clone()).unwrap();
    let first: Vec<i16> = (0..1799).collect();
    recorder.push_samples(&first).unwrap();
    assert_eq!(recorder.available_samples(), 1799);
    recorder.push_samples(&[1799]).unwrap();
    assert_eq!(recorder.available_samples(), 1740);
    assert_eq!(recorder.snapshot().unwrap().available_millis(), 1_740_000);
    assert!(!recorder.session_dir.join("segment-000000.pcm").exists());
    assert_eq!(recorder.temp_bytes(), 1740 * 2);
    recorder
        .push_samples(&(1800..1842).collect::<Vec<i16>>())
        .unwrap();
    recorder.flush().unwrap();
    assert_eq!(recorder.available_samples(), 1782);
    drop(recorder);
    let mut recovered = SegmentedRecorder::recover_latest_or_start(config).unwrap();
    assert_eq!(recovered.available_samples(), 1782);
    let output = path.join("paused.wav");
    assert_eq!(recovered.save_latest_wav(1800, &output).unwrap(), 1782);
    assert_eq!(read_wav_samples(&output), (60..1842).collect::<Vec<i16>>());
    drop(recovered);
    remove_test_dir(&path);
}

#[test]
fn minute_eviction_is_stable_across_callback_sizes_and_stop() {
    let path = test_dir("minute-worker");
    let mut config = test_config(&path, 60, 300);
    config.audio = AudioConfig {
        sample_rate: 10,
        channels: 2,
    };
    let mut worker = RecorderWorker::start(config).unwrap();
    let mut samples = 0_u64;
    for _ in 0..500 {
        worker.push_samples(&[7; 74]).unwrap();
        worker.flush().unwrap();
        samples += 74;
        let start = if samples < 6000 {
            0
        } else {
            ((samples - 6000) / 1200 + 1) * 1200
        };
        let status = worker.status();
        assert_eq!(status.retained_start_sample, start);
        assert_eq!(status.available_millis, (samples - start) * 50);
        assert_eq!(status.temp_bytes, (samples - start) * 2);
        let window = worker.buffer_window();
        assert_eq!((window.start_sample, window.end_sample), (start, samples));
    }
    let before = worker.status().available_millis;
    worker.stop();
    assert_eq!(worker.status().available_millis, before);
    drop(worker);
    remove_test_dir(&path);
}

#[test]
fn legacy_overfull_disk_cache_is_trimmed_on_recovery() {
    let path = test_dir("legacy-overfull");
    let config = test_config(&path, 60, 1800);
    let mut recorder = SegmentedRecorder::start(config.clone()).unwrap();
    recorder.push_samples_defer_trim(&vec![1; 1842]).unwrap();
    recorder.flush().unwrap();
    drop(recorder);
    let recovered = SegmentedRecorder::recover_latest_or_start(config).unwrap();
    assert_eq!(recovered.available_samples(), 1782);
    assert_eq!(recovered.temp_bytes(), 1782 * 2);
    assert!(!recovered.session_dir.join("segment-000000.pcm").exists());
    drop(recovered);
    remove_test_dir(&path);
}

#[test]
fn recording_at_44100_hz_preserves_wav_rate_and_exact_sample_count() {
    let path = test_dir("44100-wav");
    let mut config = test_config(&path, 60, 300);
    config.audio = AudioConfig {
        sample_rate: 44_100,
        channels: 1,
    };
    let mut recorder = SegmentedRecorder::start(config).unwrap();
    recorder.push_samples(&vec![123; 44_100]).unwrap();
    let output = path.join("44100.wav");
    assert_eq!(recorder.save_latest_wav(1, &output).unwrap(), 44_100);
    let wav = fs::read(&output).unwrap();
    assert_eq!(u32::from_le_bytes(wav[24..28].try_into().unwrap()), 44_100);
    assert_eq!(read_wav_samples(&output), vec![123; 44_100]);
    assert_eq!(recorder.snapshot().unwrap().available_millis(), 1000);
    drop(recorder);
    remove_test_dir(&path);
}

#[test]
fn wav_export_is_limited_to_four_hours_and_riff_capacity() {
    let path = test_dir("wav-duration-limit");
    let mut recorder = SegmentedRecorder::start(test_config(&path, 60, 86400)).unwrap();
    recorder.push_samples(&vec![123; 14401]).unwrap();
    let output = path.join("limit.wav");
    assert!(
        recorder
            .save_latest_wav(14401, &output)
            .unwrap_err()
            .to_string()
            .contains("wav_duration_limit")
    );
    assert!(!output.exists());
    assert_eq!(recorder.save_latest_wav(14400, &output).unwrap(), 14400);
    assert_eq!(read_wav_samples(&output).len(), 14400);
    let snapshot = recorder.snapshot().unwrap();
    assert!(
        snapshot
            .save_latest_with_options(14401, &path.join("async.wav"), &ExportOptions::wav(), None)
            .is_err()
    );
    let large = AudioConfig {
        sample_rate: 48000,
        channels: 4,
    };
    assert!(
        ExportFormat::Wav
            .validate_samples(large.samples_for_seconds_u64(14400), large)
            .is_err()
    );
    assert!(
        ExportFormat::Flac
            .validate_samples(large.samples_for_seconds_u64(86400), large)
            .is_ok()
    );
    drop(recorder);
    remove_test_dir(&path);
}

#[test]
fn supported_export_names_preserve_the_selected_container() {
    for name in ["wav", "mp3", "flac", "ogg", "m4a", "aac"] {
        assert_eq!(ExportFormat::from_name(name).unwrap().extension(), name);
        assert_eq!(
            ExportFormat::from_name(&name.to_uppercase())
                .unwrap()
                .extension(),
            name
        );
    }
    assert!(ExportFormat::from_name("invalid").is_none());
}
