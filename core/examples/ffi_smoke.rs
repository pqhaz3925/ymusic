//! Dev smoke test of the FFI facade against the real API.
//!   YM_TOKEN=... cargo run --example ffi_smoke
use std::time::Instant;
use ymusic_core::ffi::YmClient;

macro_rules! timed {
    ($name:expr, $e:expr, $show:expr) => {{
        let t = Instant::now();
        match $e.await {
            Ok(v) => println!("{:16} ok  {:5} ms  {}", $name, t.elapsed().as_millis(), $show(&v)),
            Err(e) => println!("{:16} ERR {:5} ms  {e:?}", $name, t.elapsed().as_millis()),
        }
    }};
}

#[tokio::main]
async fn main() {
    let c = YmClient::new(std::env::var("YM_TOKEN").unwrap_or_default()).expect("client");
    timed!("home", c.home(), |h: &ymusic_core::ffi::FfiHome| format!(
        "mixes={} tiles={:?} shelves={:?}",
        h.mixes.len(),
        h.quick_access.iter().map(|t| format!("{}|{:?}|cover={}", t.title, t.subtitle, t.cover_uri.is_some())).collect::<Vec<_>>(),
        h.shelves.iter().map(|s| format!("{}:{}({})", s.id, s.title, s.items.len())).collect::<Vec<_>>()
    ));
    timed!("liked_ids", c.liked_ids(), |v: &Vec<String>| format!("{}", v.len()));
    timed!("liked_tracks", c.liked_tracks(), |v: &Vec<ymusic_core::ffi::FfiTrack>| format!(
        "{} first={:?}",
        v.len(),
        v.first().map(|t| (&t.title, t.cover_uri.is_some(), t.album_id.is_some()))
    ));
    timed!("liked_albums", c.liked_albums(), |v: &Vec<ymusic_core::ffi::FfiAlbum>| format!("{}", v.len()));
    timed!("liked_artists", c.liked_artists(), |v: &Vec<ymusic_core::ffi::FfiArtist>| format!("{}", v.len()));
    timed!("my_playlists", c.my_playlists(), |v: &Vec<ymusic_core::ffi::FfiPlaylist>| format!("{}", v.len()));
    timed!("history", c.tracks_of("history".into(), String::new()), |v: &Vec<ymusic_core::ffi::FfiTrack>| format!("{}", v.len()));
    timed!("wave", c.wave_tracks("user:onyourwave".into(), vec![]), |v: &Vec<ymusic_core::ffi::FfiTrack>| format!("{}", v.len()));
    timed!("wave collection", c.wave_tracks("personal:collection".into(), vec![]), |v: &Vec<ymusic_core::ffi::FfiTrack>| format!("{}", v.len()));
    for q in ["lq", "nq", "hq", "lossless"] {
        timed!(q, c.stream_url("366604".into(), q.into(), vec![]), |s: &ymusic_core::ffi::FfiStream| format!(
            "codec={} bitrate={:?} granted={} enc={}",
            s.codec, s.bitrate, s.quality, s.key.is_some()
        ));
    }
}
