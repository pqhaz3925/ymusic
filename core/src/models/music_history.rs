//! Models of the `yandex_music/music_history` package (listening history).

use serde::Deserialize;
use serde::Serialize;

/// Full context model of a history item (album, artist, playlist or wave).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct MusicHistoryContextFullModel {
    /// Album.
    pub album: Option<Box<crate::models::album::Album>>,
    /// Artist.
    pub artist: Option<Box<crate::models::artist::Artist>>,
    /// Playlist.
    pub playlist: Option<Box<crate::models::playlist::Playlist>>,
    /// Wave.
    pub wave: Option<Box<crate::models::wave::Wave>>,
    /// Artists.
    pub artists: Option<Vec<crate::models::artist::Artist>>,
    /// Whether the context is available.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub available: Option<bool>,
    /// Tracks count.
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub tracks_count: Option<i64>,
    /// Simple wave foreground image url.
    pub simple_wave_foreground_image_url: Option<String>,
    /// Simple wave background color.
    pub simple_wave_background_color: Option<String>,
}

/// Group of history items sharing one context.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct MusicHistoryGroup {
    /// Context item.
    pub context: Option<Box<crate::models::music_history::MusicHistoryItem>>,
    /// Items of the group.
    pub tracks: Option<Vec<crate::models::music_history::MusicHistoryItem>>,
}

/// Data of a history item.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct MusicHistoryItemData {
    /// Item id.
    pub item_id: Option<crate::models::music_history::MusicHistoryItemId>,
    /// Full model: `crate::models::track::Track` or `crate::models::music_history::MusicHistoryContextFullModel`.
    pub full_model: Option<serde_json::Value>,
}

/// Identifier of a history item.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct MusicHistoryItemId {
    /// Item id.
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub id: Option<String>,
    /// Track id.
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub track_id: Option<String>,
    /// Album id.
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub album_id: Option<String>,
    /// User id.
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub uid: Option<String>,
    /// Kind (playlist kind).
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub kind: Option<String>,
    /// Seeds.
    pub seeds: Option<Vec<String>>,
}

/// One entry of the listening history.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct MusicHistoryItem {
    /// Item type.
    pub r#type: Option<String>,
    /// Item data.
    pub data: Option<crate::models::music_history::MusicHistoryItemData>,
}

/// List of history items.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct MusicHistoryItems {
    /// Items.
    pub items: Option<Vec<crate::models::music_history::MusicHistoryItem>>,
}

/// One date tab of the history.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct MusicHistoryTab {
    /// Date of the tab.
    pub date: Option<String>,
    /// Groups of items.
    pub items: Option<Vec<crate::models::music_history::MusicHistoryGroup>>,
}

/// Listening history response.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct MusicHistory {
    /// Date tabs.
    pub history_tabs: Option<Vec<crate::models::music_history::MusicHistoryTab>>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deserialize_music_history() {
        let json = r##"{
            "historyTabs": [
                {"date": "2024-05-01", "items": [
                    {"context": {"type": "album", "data": {"itemId": {"id": "1", "albumId": 1, "uid": 123456, "kind": 0}, "fullModel": {"id": 1, "title": "A"}}},
                     "tracks": [{"type": "track", "data": {"itemId": {"trackId": 10, "albumId": "1"}, "fullModel": {"id": 10, "title": "T"}}}]}
                ]}
            ]
        }"##;
        let h: MusicHistory = serde_json::from_str(json).unwrap();
        let tabs = h.history_tabs.unwrap();
        assert_eq!(tabs[0].date.as_deref(), Some("2024-05-01"));
        let group = &tabs[0].items.as_ref().unwrap()[0];
        let ctx = group.context.as_ref().unwrap();
        assert_eq!(ctx.r#type.as_deref(), Some("album"));
        let id = ctx.data.as_ref().unwrap().item_id.as_ref().unwrap();
        assert_eq!(id.album_id.as_deref(), Some("1"));
        assert_eq!(id.uid.as_deref(), Some("123456"));
        let track = &group.tracks.as_ref().unwrap()[0];
        assert_eq!(track.data.as_ref().unwrap().item_id.as_ref().unwrap().track_id.as_deref(), Some("10"));
    }

    #[test]
    fn deserialize_context_full_model() {
        let json = r##"{"wave": {"seeds": ["user:1"], "stationId": "user:1"}, "available": true, "tracksCount": "12", "simpleWaveBackgroundColor": "#000000"}"##;
        let c: MusicHistoryContextFullModel = serde_json::from_str(json).unwrap();
        assert_eq!(c.available, Some(true));
        assert_eq!(c.tracks_count, Some(12));
        assert!(c.wave.is_some());
    }
}
