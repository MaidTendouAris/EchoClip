use std::env;
use std::path::PathBuf;

use echoclip_core::{AudioConfig, RingBuffer, generate_demo_audio};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let output_dir = env::args()
        .nth(1)
        .map(PathBuf::from)
        .unwrap_or(env::current_dir()?.join("demo_output"));
    std::fs::create_dir_all(&output_dir)?;

    let config = AudioConfig::mono_48k();
    let mut buffer = RingBuffer::new(config, 10.0);

    println!("EchoClip Windows demo");
    println!("Simulating a 10 second rolling audio buffer...");

    for chunk_index in 0..10 {
        let chunk = generate_demo_audio(config, 1.0);
        buffer.push_samples(&chunk);
        println!(
            "buffered chunk {:02}: {:.1}s available",
            chunk_index + 1,
            buffer.available_seconds()
        );
    }

    let clip = buffer.latest(5.0).with_gain_db(3.0);
    let output_file = output_dir.join("echoclip-last-5s-demo.wav");
    clip.write_wav(&output_file)?;

    println!("Saved latest {:.1}s clip:", clip.duration_seconds());
    println!("{}", output_file.display());
    println!("This demo validates the Rust core path: ring buffer -> gain -> WAV.");

    Ok(())
}
