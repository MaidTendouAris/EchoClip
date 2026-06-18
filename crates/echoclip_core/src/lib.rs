use std::f32::consts::PI;
use std::fs::File;
use std::io::{self, Write};
use std::path::Path;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AudioConfig {
    pub sample_rate: u32,
    pub channels: u16,
}

impl AudioConfig {
    pub fn mono_48k() -> Self {
        Self {
            sample_rate: 48_000,
            channels: 1,
        }
    }

    fn samples_for_duration(self, seconds: f32) -> usize {
        let frames = (self.sample_rate as f32 * seconds).round().max(1.0) as usize;
        frames * self.channels as usize
    }
}

#[derive(Debug, Clone)]
pub struct AudioClip {
    pub config: AudioConfig,
    pub samples: Vec<i16>,
}

impl AudioClip {
    pub fn duration_seconds(&self) -> f32 {
        self.samples.len() as f32 / self.config.channels as f32 / self.config.sample_rate as f32
    }

    pub fn with_gain_db(mut self, gain_db: f32) -> Self {
        apply_gain_db(&mut self.samples, gain_db);
        self
    }

    pub fn write_wav<P: AsRef<Path>>(&self, path: P) -> io::Result<()> {
        write_wav_i16(path, self.config, &self.samples)
    }
}

#[derive(Debug, Clone)]
pub struct RingBuffer {
    config: AudioConfig,
    samples: Vec<i16>,
    write_pos: usize,
    len: usize,
}

impl RingBuffer {
    pub fn new(config: AudioConfig, capacity_seconds: f32) -> Self {
        let capacity = config.samples_for_duration(capacity_seconds);
        Self {
            config,
            samples: vec![0; capacity],
            write_pos: 0,
            len: 0,
        }
    }

    pub fn config(&self) -> AudioConfig {
        self.config
    }

    pub fn capacity_samples(&self) -> usize {
        self.samples.len()
    }

    pub fn available_samples(&self) -> usize {
        self.len
    }

    pub fn available_seconds(&self) -> f32 {
        self.len as f32 / self.config.channels as f32 / self.config.sample_rate as f32
    }

    pub fn push_samples(&mut self, input: &[i16]) {
        for &sample in input {
            self.samples[self.write_pos] = sample;
            self.write_pos = (self.write_pos + 1) % self.samples.len();
            self.len = (self.len + 1).min(self.samples.len());
        }
    }

    pub fn latest(&self, seconds: f32) -> AudioClip {
        let requested = self.config.samples_for_duration(seconds);
        let count = requested.min(self.len);
        let start = (self.write_pos + self.samples.len() - count) % self.samples.len();
        let mut out = Vec::with_capacity(count);

        for index in 0..count {
            out.push(self.samples[(start + index) % self.samples.len()]);
        }

        AudioClip {
            config: self.config,
            samples: out,
        }
    }
}

pub fn apply_gain_db(samples: &mut [i16], gain_db: f32) {
    let gain = 10.0_f32.powf(gain_db / 20.0);
    for sample in samples {
        let amplified = *sample as f32 * gain;
        *sample = amplified.clamp(i16::MIN as f32, i16::MAX as f32) as i16;
    }
}

pub fn generate_demo_audio(config: AudioConfig, seconds: f32) -> Vec<i16> {
    let frames = (config.sample_rate as f32 * seconds).round() as usize;
    let channels = config.channels as usize;
    let mut samples = Vec::with_capacity(frames * channels);

    for frame in 0..frames {
        let t = frame as f32 / config.sample_rate as f32;
        let tone = (t * 440.0 * 2.0 * PI).sin() * 0.25;
        let slow_pulse = (t * 3.0 * 2.0 * PI).sin().max(0.0) * 0.35;
        let value = ((tone + slow_pulse) * i16::MAX as f32).clamp(i16::MIN as f32, i16::MAX as f32);
        for _ in 0..channels {
            samples.push(value as i16);
        }
    }

    samples
}

pub fn write_wav_i16<P: AsRef<Path>>(
    path: P,
    config: AudioConfig,
    samples: &[i16],
) -> io::Result<()> {
    let mut file = File::create(path)?;
    let data_size = (samples.len() * 2) as u32;
    let byte_rate = config.sample_rate * config.channels as u32 * 2;
    let block_align = config.channels * 2;

    file.write_all(b"RIFF")?;
    file.write_all(&(36 + data_size).to_le_bytes())?;
    file.write_all(b"WAVE")?;
    file.write_all(b"fmt ")?;
    file.write_all(&16_u32.to_le_bytes())?;
    file.write_all(&1_u16.to_le_bytes())?;
    file.write_all(&config.channels.to_le_bytes())?;
    file.write_all(&config.sample_rate.to_le_bytes())?;
    file.write_all(&byte_rate.to_le_bytes())?;
    file.write_all(&block_align.to_le_bytes())?;
    file.write_all(&16_u16.to_le_bytes())?;
    file.write_all(b"data")?;
    file.write_all(&data_size.to_le_bytes())?;

    for sample in samples {
        file.write_all(&sample.to_le_bytes())?;
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn latest_returns_most_recent_samples() {
        let config = AudioConfig {
            sample_rate: 10,
            channels: 1,
        };
        let mut buffer = RingBuffer::new(config, 1.0);
        buffer.push_samples(&[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);

        let clip = buffer.latest(0.5);

        assert_eq!(clip.samples, vec![8, 9, 10, 11, 12]);
    }

    #[test]
    fn gain_is_clamped() {
        let mut samples = vec![20_000, -20_000];
        apply_gain_db(&mut samples, 12.0);

        assert_eq!(samples, vec![i16::MAX, i16::MIN]);
    }
}
