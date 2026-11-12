//! Dev: which seed combinations does the rotor accept?  cargo run --example dbg_wave -- "<seeds>" ...
use ymusic_core::ffi::YmClient;

#[tokio::main]
async fn main() {
    let c = YmClient::new(std::env::var("YM_TOKEN").unwrap_or_default()).expect("client");
    for seeds in std::env::args().skip(1) {
        match c.wave_tracks(seeds.clone(), vec![]).await {
            Ok(t) => println!("{seeds:60} ok {} | {}", t.len(), t.iter().take(3).map(|t| format!("{} — {}", t.title, t.artists.first().map(|a| a.name.as_str()).unwrap_or(""))).collect::<Vec<_>>().join("; ")),
            Err(e) => println!("{seeds:60} ERR {e}"),
        }
    }
}
