//! Dev: find which JSON path of /tracks holds a given integer (model type mismatch hunting).
use serde_json::Value;
use ymusic_core::Client;

fn walk(v: &Value, path: &mut Vec<String>, needle: i64, out: &mut Vec<String>) {
    match v {
        Value::Number(n) if n.as_i64() == Some(needle) => out.push(path.join(".")),
        Value::Array(a) => {
            for x in a.iter() {
                path.push("[]".into());
                walk(x, path, needle, out);
                path.pop();
            }
        }
        Value::Object(o) => {
            for (k, x) in o {
                path.push(k.clone());
                walk(x, path, needle, out);
                path.pop();
            }
        }
        _ => {}
    }
}

#[tokio::main]
async fn main() {
    let needle: i64 = std::env::args().nth(1).and_then(|s| s.parse().ok()).unwrap_or(44981);
    let client = Client::new(std::env::var("YM_TOKEN").ok()).expect("client");
    let _ = client.init().await;
    let liked = client.users_likes_tracks(None, 0).await.ok().flatten().and_then(|l| l.tracks).unwrap_or_default();
    let ids: Vec<String> = liked.iter().filter_map(|t| t.id.clone()).collect();
    let mut found = std::collections::BTreeSet::new();
    for chunk in ids.chunks(100) {
        let form = [("track-ids", chunk.join(",")), ("with-positions", "False".to_owned())];
        let url = format!("{}/tracks", client.base_url);
        let v = client.http().post(&url, &form).await.expect("tracks");
        let mut out = Vec::new();
        walk(&v, &mut Vec::new(), needle, &mut out);
        found.extend(out);
        // Also: try each track alone to list every failing field message.
        if let Value::Array(a) = &v {
            for t in a {
                if let Err(e) = serde_json::from_value::<ymusic_core::models::track::Track>(t.clone()) {
                    found.insert(format!("ERR {e}"));
                }
            }
        }
    }
    for f in found {
        println!("{f}");
    }
}
