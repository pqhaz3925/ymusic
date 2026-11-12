//! Port of `yandex_music/_client/music_history.py`.

use serde_json::{json, Value};

use super::Client;
use crate::error::Result;
use crate::http::from_value_opt;
use crate::models::music_history::{MusicHistory, MusicHistoryItems};

fn make_item(type_: &str, item_id: Value) -> Value {
    json!({ "type": type_, "data": { "itemId": item_id } })
}

#[allow(clippy::too_many_arguments)]
fn build_history_items(
    track_ids: Option<&[(&str, &str)]>,
    album_ids: Option<&[&str]>,
    artist_ids: Option<&[&str]>,
    playlist_ids: Option<&[(&str, &str)]>,
    wave_seeds: Option<&[&[&str]]>,
) -> Vec<Value> {
    let mut items = Vec::new();
    for (track_id, album_id) in track_ids.unwrap_or(&[]) {
        items.push(make_item(
            "track",
            json!({ "trackId": track_id, "albumId": album_id }),
        ));
    }
    for album_id in album_ids.unwrap_or(&[]) {
        items.push(make_item("album", json!({ "id": album_id })));
    }
    for artist_id in artist_ids.unwrap_or(&[]) {
        items.push(make_item("artist", json!({ "id": artist_id })));
    }
    for (uid, kind) in playlist_ids.unwrap_or(&[]) {
        let uid: i64 = uid.parse().unwrap_or(0);
        let kind: i64 = kind.parse().unwrap_or(0);
        items.push(make_item("playlist", json!({ "uid": uid, "kind": kind })));
    }
    for seeds in wave_seeds.unwrap_or(&[]) {
        items.push(make_item("wave", json!({ "seeds": seeds })));
    }
    items
}

impl Client {
    /// Get the listening history.
    pub async fn music_history(&self, full_models_count: i64) -> Result<Option<MusicHistory>> {
        let url = self.url("/music-history");
        let params = [("fullModelsCount", full_models_count.to_string())];
        let result = self.http.get(&url, &params).await?;
        from_value_opt(result)
    }

    /// Get listening-history items for the given track/album/artist/playlist/wave ids.
    pub async fn music_history_items(
        &self,
        track_ids: Option<&[(&str, &str)]>,
        album_ids: Option<&[&str]>,
        artist_ids: Option<&[&str]>,
        playlist_ids: Option<&[(&str, &str)]>,
        wave_seeds: Option<&[&[&str]]>,
    ) -> Result<Option<MusicHistoryItems>> {
        let url = self.url("/music-history/items");
        let items = build_history_items(track_ids, album_ids, artist_ids, playlist_ids, wave_seeds);
        let result = self.http.post_json(&url, &[], &json!({ "items": items })).await?;
        from_value_opt(result)
    }
}
