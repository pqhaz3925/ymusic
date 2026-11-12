//! Models of the `yandex_music/feed` package: the personalized feed ("Моя волна" events).

use serde::{Deserialize, Serialize};

/// Track with advertising payload.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct TrackWithAds {
    pub r#type: Option<String>,
    pub track: Option<crate::models::track::Track>,
}

/// Generated playlist shown in the feed.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct GeneratedPlaylist {
    pub r#type: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub ready: Option<bool>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub notify: Option<bool>,
    pub data: Option<crate::models::playlist::Playlist>,
    pub description: Option<Vec<serde_json::Value>>,
    pub preview_description: Option<String>,
}

/// Event about new album releases.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct AlbumEvent {
    pub album: Option<crate::models::album::Album>,
    pub tracks: Vec<crate::models::track::Track>,
}

/// Event about a new release of a subscribed artist.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ArtistEvent {
    pub artist: Option<crate::models::artist::Artist>,
    pub tracks: Vec<crate::models::track::Track>,
    pub similar_to_artists_from_history: Vec<crate::models::artist::Artist>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub subscribed: Option<bool>,
}

/// Single feed event.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Event {
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub id: Option<String>,
    pub r#type: Option<String>,
    pub type_for_from: Option<String>,
    pub title: Option<String>,
    pub tracks: Vec<crate::models::track::Track>,
    pub artists: Vec<ArtistEvent>,
    pub albums: Vec<AlbumEvent>,
    pub message: Option<String>,
    pub device: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub tracks_count: Option<i64>,
    pub genre: Option<String>,
}

/// Feed day: a date with its events.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Day {
    pub day: Option<String>,
    pub events: Vec<Event>,
    pub tracks_to_play_with_ads: Vec<TrackWithAds>,
    pub tracks_to_play: Vec<crate::models::track::Track>,
}

/// The user's feed.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Feed {
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub can_get_more_events: Option<bool>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub pumpkin: Option<bool>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub is_wizard_passed: Option<bool>,
    pub generated_playlists: Vec<GeneratedPlaylist>,
    pub headlines: Vec<String>,
    pub today: Option<String>,
    pub days: Vec<Day>,
    pub next_revision: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deserialize_feed() {
        let json = r##"{
            "canGetMoreEvents": true,
            "pumpkin": false,
            "isWizardPassed": true,
            "generatedPlaylists": [
                {
                    "type": "playlistOfTheDay",
                    "ready": true,
                    "notify": false,
                    "data": {"uid": 1, "kind": 3, "title": "Playlist of the day"},
                    "description": ["Description"],
                    "previewDescription": "Preview"
                }
            ],
            "headlines": ["Headline"],
            "today": "2024-01-01",
            "days": [
                {
                    "day": "2024-01-01",
                    "events": [
                        {
                            "id": "event-1",
                            "type": "concert",
                            "typeForFrom": "concert",
                            "title": "Concert",
                            "tracks": [{"id": "1", "title": "Track"}],
                            "artists": [{"artist": {"id": 2, "name": "Artist"}, "tracks": [], "similarToArtistsFromHistory": [], "subscribed": true}],
                            "albums": [{"album": {"id": 3, "title": "Album"}, "tracks": []}],
                            "message": "msg",
                            "device": "iphone",
                            "tracksCount": 5,
                            "genre": "rock"
                        }
                    ],
                    "tracksToPlayWithAds": [{"type": "track", "track": {"id": "4"}}],
                    "tracksToPlay": [{"id": "5"}]
                }
            ],
            "nextRevision": "rev"
        }"##;
        let feed: Feed = serde_json::from_str(json).unwrap();
        assert_eq!(feed.can_get_more_events, Some(true));
        assert_eq!(feed.headlines, vec!["Headline".to_string()]);
        let event = &feed.days[0].events[0];
        assert_eq!(event.id.as_deref(), Some("event-1"));
        assert_eq!(event.tracks_count, Some(5));
        assert_eq!(event.artists[0].subscribed, Some(true));
        assert_eq!(event.albums[0].album.as_ref().unwrap().id.as_deref(), Some("3"));
        assert_eq!(feed.days[0].tracks_to_play_with_ads[0].track.as_ref().unwrap().id.as_deref(), Some("4"));
        assert_eq!(feed.generated_playlists[0].ready, Some(true));
    }
}
