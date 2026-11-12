//! Dev: in what order does the API return liked tracks?
use ymusic_core::Client;

#[tokio::main]
async fn main() {
    let client = Client::new(std::env::var("YM_TOKEN").ok()).expect("client");
    let _ = client.init().await;
    let liked = client.users_likes_tracks(None, 0).await.ok().flatten().and_then(|l| l.tracks).unwrap_or_default();
    let ts = |i: usize| liked.get(i).and_then(|t| t.timestamp.clone()).unwrap_or_default();
    println!("count={} first={} second={} last={}", liked.len(), ts(0), ts(1), ts(liked.len().saturating_sub(1)));
}
