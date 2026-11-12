//! Models of the `yandex_music/landing` package: the main page (landing) content.

use serde::{Deserialize, Serialize};

/// Reference to a track with its album.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct TrackId {
    /// Absent in the JSON: filled from `id`/`trackId` by [`TrackId::finalize`].
    #[serde(skip_deserializing, deserialize_with = "crate::models::de::opt_i64")]
    pub id: Option<i64>,
    /// Only sent by the queue-tracks context; otherwise it comes from `id`.
    #[serde(default, deserialize_with = "crate::models::de::opt_i64")]
    pub track_id: Option<i64>,
    /// Raw `id` (number or string) used when `track_id` is absent.
    #[serde(
        rename = "id",
        default,
        deserialize_with = "crate::models::de::opt_i64"
    )]
    #[serde(skip_serializing)]
    id_raw: Option<i64>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub album_id: Option<i64>,
    #[serde(rename = "from")]
    pub from_: Option<String>,
}

impl TrackId {
    /// Keep `id` in sync with `track_id` (mirrors Python, where both carry the track number).
    pub fn finalize(&mut self) {
        if self.track_id.is_none() {
            self.track_id = self.id_raw.take();
        }
        if self.id.is_none() {
            self.id = self.track_id;
        }
    }
}

/// Short track info used inside play contexts.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct TrackShortOld {
    pub track_id: Option<TrackId>,
    pub timestamp: Option<String>,
}

/// Chart position data of a track.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Chart {
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub position: Option<i64>,
    pub progress: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub listeners: Option<i64>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub shift: Option<i64>,
    pub bg_color: Option<String>,
    pub track_id: Option<TrackId>,
}

/// Track with its chart position.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ChartItem {
    pub track: Option<crate::models::track::Track>,
    pub chart: Option<Chart>,
}

/// Menu item of the chart block header.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ChartInfoMenuItem {
    pub title: Option<String>,
    pub url: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub selected: Option<bool>,
}

/// Menu of the chart block header.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ChartInfoMenu {
    pub items: Vec<ChartInfoMenuItem>,
}

/// Header info of a chart block.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ChartInfo {
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub id: Option<String>,
    pub r#type: Option<String>,
    pub type_for_from: Option<String>,
    pub title: Option<String>,
    pub menu: Option<ChartInfoMenu>,
    pub chart: Option<crate::models::playlist::Playlist>,
    pub chart_description: Option<String>,
}

/// Promotion banner shown on the landing.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Promotion {
    pub promo_id: Option<String>,
    pub title: Option<String>,
    pub subtitle: Option<String>,
    pub heading: Option<String>,
    pub url: Option<String>,
    pub url_scheme: Option<String>,
    pub text_color: Option<String>,
    pub gradient: Option<String>,
    pub image: Option<String>,
}

/// Special "mix" link banner.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct MixLink {
    pub title: Option<String>,
    pub url: Option<String>,
    pub url_scheme: Option<String>,
    pub text_color: Option<String>,
    pub background_color: Option<String>,
    pub background_image_uri: Option<String>,
    pub cover_white: Option<String>,
    pub cover_uri: Option<String>,
}

/// Data of a personal playlists block.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct PersonalPlaylistsData {
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub is_wizard_passed: Option<bool>,
}

/// Play context (radio-like station) with its tracks.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct PlayContext {
    #[serde(rename = "client")]
    pub client_: Option<String>,
    pub context: Option<String>,
    pub context_item: Option<String>,
    pub tracks: Vec<TrackShortOld>,
}

/// Additional tracks of a play contexts block.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct PlayContextsData {
    pub other_tracks: Vec<TrackShortOld>,
}

/// Item of a landing block.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct BlockEntity {
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub id: Option<String>,
    pub r#type: Option<String>,
    /// Raw payload: `GeneratedPlaylist`, `Promotion`, `Album`, `Playlist`, `ChartItem`, `PlayContext` or `MixLink`.
    pub data: Option<serde_json::Value>,
}

/// Block of the landing page.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Block {
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub id: Option<String>,
    pub r#type: Option<String>,
    pub type_for_from: Option<String>,
    pub title: Option<String>,
    pub entities: Vec<BlockEntity>,
    pub description: Option<String>,
    /// Raw payload: `PersonalPlaylistsData` or `PlayContextsData`.
    pub data: Option<serde_json::Value>,
}

/// List block of the landing (new releases, podcasts, ...).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct LandingList {
    pub r#type: Option<String>,
    pub type_for_from: Option<String>,
    pub title: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub id: Option<String>,
    pub new_releases: Vec<serde_json::Value>,
    pub new_playlists: Vec<serde_json::Value>,
    pub podcasts: Vec<serde_json::Value>,
}

/// The landing page content.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Landing {
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub pumpkin: Option<bool>,
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub content_id: Option<String>,
    pub blocks: Vec<Block>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deserialize_landing() {
        let json = r##"{
            "pumpkin": true,
            "contentId": 112358,
            "blocks": [
                {
                    "id": "personal-playlists",
                    "type": "personal-playlists",
                    "typeForFrom": "personal-playlists",
                    "title": "Волна",
                    "description": null,
                    "data": {"isWizardPassed": true},
                    "entities": [
                        {
                            "id": "new-releases",
                            "type": "personal-playlists",
                            "data": {"isWizardPassed": true}
                        },
                        {
                            "id": "chart",
                            "type": "chart",
                            "data": {"track": {"id": "123", "title": "Song"}, "chart": {"position": 1, "progress": "up", "listeners": 1000, "shift": 2, "bgColor": "#abc"}}
                        }
                    ]
                }
            ]
        }"##;
        let landing: Landing = serde_json::from_str(json).unwrap();
        assert_eq!(landing.pumpkin, Some(true));
        assert_eq!(landing.content_id.as_deref(), Some("112358"));
        let entity = &landing.blocks[0].entities[1];
        let chart_item: ChartItem = serde_json::from_value(entity.data.clone().unwrap()).unwrap();
        assert_eq!(chart_item.chart.as_ref().unwrap().position, Some(1));
        assert_eq!(chart_item.track.as_ref().unwrap().id, Some("123".to_string()));
    }

    #[test]
    fn deserialize_track_id_and_list() {
        let mut tid: TrackId =
            serde_json::from_str(r#"{"id": 5, "albumId": "7", "from": "user"}"#).unwrap();
        tid.finalize();
        assert_eq!(tid.track_id, Some(5));
        assert_eq!(tid.album_id, Some(7));
        assert_eq!(tid.from_.as_deref(), Some("user"));

        let list: LandingList =
            serde_json::from_str(r#"{"type": "chart", "title": "Чарт", "newReleases": [1, 2]}"#)
                .unwrap();
        assert_eq!(list.new_releases.len(), 2);
    }
}
