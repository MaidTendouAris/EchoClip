use super::tests::{read_wav_samples, test_config, test_dir};
use super::*;

fn wait_export(worker: &RecorderWorker, id: u64) -> ExportJobStatus {
    let deadline = std::time::Instant::now() + Duration::from_secs(5);
    loop {
        let status = worker.export_status(id).unwrap();
        if matches!(
            status.state,
            ExportJobState::Finished | ExportJobState::Failed | ExportJobState::Canceled
        ) {
            return status;
        }
        assert!(std::time::Instant::now() < deadline, "export timed out");
        thread::sleep(Duration::from_millis(5));
    }
}

#[test]
fn fixed_range_crosses_segments_and_does_not_follow_new_audio() {
    let path = test_dir("fixed-range");
    let mut worker = RecorderWorker::start(test_config(&path, 2, 20)).unwrap();
    worker.push_samples(&[1, 2, 3, 4, 5, 6]).unwrap();
    worker.flush().unwrap();
    let window = worker.buffer_window();
    worker.push_samples(&[7, 8, 9]).unwrap();
    let output = path.join("range.wav");
    let id = worker
        .save_range_async(
            ExportRange {
                buffer_id: window.buffer_id,
                start_sample: 1,
                end_sample: 5,
            },
            &output,
            ExportOptions::wav(),
        )
        .unwrap();
    assert_eq!(wait_export(&worker, id).state, ExportJobState::Finished);
    assert_eq!(read_wav_samples(&output), vec![2, 3, 4, 5]);
    worker.stop();
    fs::remove_dir_all(path).unwrap();
}

#[test]
fn expired_range_fails_instead_of_clamping_to_different_audio() {
    let path = test_dir("expired-range");
    let mut worker = RecorderWorker::start(test_config(&path, 2, 4)).unwrap();
    worker.push_samples(&[1, 2, 3, 4]).unwrap();
    worker.flush().unwrap();
    let window = worker.buffer_window();
    worker.push_samples(&[5, 6, 7, 8, 9, 10]).unwrap();
    worker.flush().unwrap();
    let output = path.join("range.wav");
    let id = worker
        .save_range_async(
            ExportRange {
                buffer_id: window.buffer_id,
                start_sample: 0,
                end_sample: 3,
            },
            &output,
            ExportOptions::wav(),
        )
        .unwrap();
    let status = wait_export(&worker, id);
    assert_eq!(status.state, ExportJobState::Failed);
    assert!(status.error.unwrap().contains("BUFFER_RANGE_EXPIRED"));
    assert!(!output.exists());
    worker.stop();
    fs::remove_dir_all(path).unwrap();
}

#[test]
fn recovery_preserves_unchanged_timeline_and_invalidates_rebased_audio() {
    let path = test_dir("range-recovery");
    let config = test_config(&path, 2, 20);
    let mut recorder = SegmentedRecorder::start(config.clone()).unwrap();
    recorder.push_samples(&[1, 2, 3, 4, 5]).unwrap();
    recorder.flush().unwrap();
    let timeline = recorder.manifest.timeline_id.clone();
    let segment = recorder
        .session_dir
        .join(&recorder.manifest.segments[0].file_name);
    drop(recorder);
    let recovered = SegmentedRecorder::recover_latest_or_start(config.clone()).unwrap();
    assert_eq!(recovered.manifest.timeline_id, timeline);
    drop(recovered);
    fs::remove_file(segment).unwrap();
    let rebased = SegmentedRecorder::recover_latest_or_start(config).unwrap();
    assert_ne!(rebased.manifest.timeline_id, timeline);
    drop(rebased);
    fs::remove_dir_all(path).unwrap();
}

#[test]
fn invalid_range_or_replaced_buffer_is_rejected_before_export() {
    let path = test_dir("invalid-range");
    let mut worker = RecorderWorker::start(test_config(&path, 2, 10)).unwrap();
    let output = path.join("range.wav");
    let window = worker.buffer_window();
    assert!(
        worker
            .save_range_async(
                ExportRange {
                    buffer_id: window.buffer_id,
                    start_sample: 2,
                    end_sample: 2
                },
                &output,
                ExportOptions::wav()
            )
            .is_err()
    );
    assert!(
        worker
            .save_range_async(
                ExportRange {
                    buffer_id: "old-buffer".into(),
                    start_sample: 0,
                    end_sample: 1
                },
                &output,
                ExportOptions::wav()
            )
            .is_err()
    );
    assert!(!output.exists());
    worker.stop();
    fs::remove_dir_all(path).unwrap();
}
