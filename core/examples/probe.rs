//! Dev probe: what does the API hand out for a track at each quality?
//!   YM_TOKEN=... cargo run --example probe -- <track_id> [more ids]
use ymusic_core::client::tracks::Quality;
use ymusic_core::Client;

#[tokio::main]
async fn main() {
    let token = std::env::var("YM_TOKEN").ok();
    let client = Client::new(token).expect("client");
    let _ = client.init().await;
    let http = reqwest::Client::new();
    let mut ids: Vec<String> = std::env::args().skip(1).collect();
    if ids.is_empty() {
        // No ids given: take the three newest liked tracks.
        let liked = client.users_likes_tracks(None, 0).await.ok().flatten().and_then(|l| l.tracks).unwrap_or_default();
        println!("liked tracks: {}", liked.len());
        ids = liked.iter().rev().take(3).filter_map(|t| t.id.clone()).collect();
    }
    for id in ids {
        for q in [Quality::Lossless, Quality::High, Quality::Normal] {
            let codecs_env = std::env::var("PROBE_CODECS").ok();
            let codecs: Option<Vec<&str>> = codecs_env.as_deref().map(|c| c.split(',').collect());
            match client.direct_link(&id, q, codecs.as_deref()).await {
                Ok(s) => {
                    println!(
                        "{id} {:9} codec={:11} bitrate={:?} granted={:?} encrypted={} url={}",
                        q.as_str(),
                        s.codec,
                        s.bitrate,
                        s.quality,
                        s.key.is_some(),
                        s.url.split('?').next().unwrap_or("")
                    );
                    if std::env::var("PROBE_URLS").is_ok() {
                        println!("    FULLURL {} {}", q.as_str(), s.url);
                    }
                    if let Ok(r) = http.get(&s.url).header("Range", "bytes=0-15").send().await {
                        let h = r.headers();
                        let g = |k: &str| h.get(k).and_then(|v| v.to_str().ok()).unwrap_or("-").to_owned();
                        println!(
                            "    status={} type={} range={} len={} accept-ranges={}",
                            r.status(),
                            g("content-type"),
                            g("content-range"),
                            g("content-length"),
                            g("accept-ranges")
                        );
                        if let Ok(b) = r.bytes().await {
                            println!("    head={:02x?}", &b[..b.len().min(16)]);
                        }
                    }
                }
                Err(e) => println!("{id} {:9} ERROR {e}", q.as_str()),
            }
        }
    }
}
