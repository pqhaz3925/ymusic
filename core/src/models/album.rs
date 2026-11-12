//! Port of `yandex_music/album`.

use serde::{Deserialize, Serialize};

/// Album, artist or playlist action button.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct AlbumActionButton {
    /// Button text.
    pub text: Option<String>,
    /// Link URL.
    pub url: Option<String>,
    /// Button HEX color.
    pub color: Option<String>,
    /// Open the link in the built-in browser.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub view_browser: Option<bool>,
}

/// Similar entities for an album.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct AlbumSimilarEntities {
    /// Similar entities.
    pub items: Option<Vec<crate::models::wave::SimilarEntityItem>>,
}

/// Availability of an album trailer.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct AlbumTrailerStatus {
    /// Whether the trailer is available.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub available: Option<bool>,
}

/// Album with trailer information.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct AlbumTrailer {
    /// Album.
    pub album: Option<Box<crate::models::album::Album>>,
    /// Artists.
    pub artists: Option<Vec<crate::models::artist::Artist>>,
    /// Trailer info.
    pub trailer: Option<crate::models::common::TrailerInfo>,
}

/// Album deprecation info (album merged into another one).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Deprecation {
    /// Target album id.
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub target_album_id: Option<String>,
    /// Deprecation status.
    pub status: Option<String>,
    /// Whether the album is fully moved.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub done: Option<bool>,
}

/// Position of a track inside an album volume.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct TrackPosition {
    /// Volume number.
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub volume: Option<i64>,
    /// Track index in the volume.
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub index: Option<i64>,
}

/// Album.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Album {
    /// Album id.
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub id: Option<String>,
    /// Album retrieval error.
    pub error: Option<String>,
    /// Album title.
    pub title: Option<String>,
    /// Number of tracks.
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub track_count: Option<i64>,
    /// Artists.
    pub artists: Vec<crate::models::artist::Artist>,
    /// Labels (objects or plain strings).
    pub labels: Vec<serde_json::Value>,
    /// Whether the album is available.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub available: Option<bool>,
    /// Whether the album is available for premium users.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub available_for_premium_users: Option<bool>,
    /// Additional album version info.
    pub version: Option<String>,
    /// Cover URI.
    pub cover_uri: Option<String>,
    /// Content warning.
    pub content_warning: Option<String>,
    /// Original release year.
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub original_release_year: Option<i64>,
    /// Music genre.
    pub genre: Option<String>,
    /// Description text color.
    pub text_color: Option<String>,
    /// Short description.
    pub short_description: Option<String>,
    /// Description.
    pub description: Option<String>,
    /// Whether the album is a premiere.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub is_premiere: Option<bool>,
    /// Whether the album is a banner.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub is_banner: Option<bool>,
    /// Meta type.
    pub meta_type: Option<String>,
    /// Storage directory.
    pub storage_dir: Option<String>,
    /// Open Graph image.
    pub og_image: Option<String>,
    /// Buy options.
    pub buy: Option<Vec<serde_json::Value>>,
    /// Whether the album is recent.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub recent: Option<bool>,
    /// Whether the album is very important.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub very_important: Option<bool>,
    /// Whether the album is available on mobile.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub available_for_mobile: Option<bool>,
    /// Whether the album is partially available.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub available_partially: Option<bool>,
    /// Best track positions.
    pub bests: Option<Vec<i64>>,
    /// Duplicate albums.
    pub duplicates: Vec<Album>,
    /// Prerolls.
    pub prerolls: Option<Vec<serde_json::Value>>,
    /// Track volumes.
    pub volumes: Option<Vec<Vec<crate::models::track::Track>>>,
    /// Year.
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub year: Option<i64>,
    /// Release date.
    pub release_date: Option<String>,
    /// Album type.
    #[serde(rename = "type")]
    pub r#type: Option<String>,
    /// Track position.
    pub track_position: Option<TrackPosition>,
    /// Regions.
    pub regions: Option<Vec<String>>,
    /// Whether the album is available as ringback tone.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub available_as_rbt: Option<bool>,
    /// Whether lyrics are available.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub lyrics_available: Option<bool>,
    /// Remember listening position.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub remember_position: Option<bool>,
    /// Related albums.
    pub albums: Option<Vec<Album>>,
    /// Duration in milliseconds.
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub duration_ms: Option<i64>,
    /// Whether the album contains explicit content.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub explicit: Option<bool>,
    /// Start date.
    pub start_date: Option<String>,
    /// Likes count.
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub likes_count: Option<i64>,
    /// Deprecation info.
    pub deprecation: Option<Deprecation>,
    /// Available regions.
    pub available_regions: Option<Vec<String>>,
    /// Available options.
    pub available_for_options: Option<Vec<String>>,
    /// Whether listening was finished.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub listening_finished: Option<bool>,
    /// Disclaimers.
    pub disclaimers: Option<Vec<String>>,
    /// Action button.
    pub action_button: Option<AlbumActionButton>,
    /// Cover.
    pub cover: Option<crate::models::common::Cover>,
    /// Cover derived colors.
    pub derived_colors: Option<crate::models::common::CoverDerivedColors>,
    /// Meta tag id.
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub meta_tag_id: Option<String>,
    /// Whether this is child content.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub child_content: Option<bool>,
    /// Background image URL.
    pub background_image_url: Option<String>,
    /// Custom wave.
    pub custom_wave: Option<crate::models::playlist::CustomWave>,
    /// Duration in seconds.
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub duration_sec: Option<i64>,
    /// Whether a trailer exists.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub has_trailer: Option<bool>,
    /// Trailer status.
    pub trailer: Option<AlbumTrailerStatus>,
    /// Pager.
    pub pager: Option<crate::models::common::Pager>,
    /// Sort order.
    pub sort_order: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn album_deserialize() {
        let json = serde_json::json!({
            "id": 5239478,
            "error": "not-found",
            "title": "In the End",
            "version": "feat. Mark Van Hoen & Mike Harding",
            "coverUri": "avatars.yandex.net/get-music-content/95061/89c14a7d.a.5239478-1/%%",
            "trackCount": 3,
            "available": true,
            "availableForPremiumUsers": true,
            "genre": "alternative",
            "textColor": "#000000",
            "shortDescription": "",
            "isPremiere": false,
            "metaType": "music",
            "bests": [51241318],
            "year": 2019,
            "releaseDate": "2019-03-22T00:00:00+03:00",
            "type": "single",
            "artists": [],
            "labels": ["Label name"],
            "volumes": [[{"id": "1", "title": "Track"}]],
            "deprecation": {"targetAlbumId": 1, "status": "deprecated", "done": true},
            "trackPosition": {"volume": 1, "index": 2},
            "actionButton": {"text": "Listen", "url": "https://x", "color": "#ffffff", "viewBrowser": true},
            "hasTrailer": false,
            "trailer": {"available": true}
        });
        let album: Album = serde_json::from_value(json).unwrap();
        assert_eq!(album.id.as_deref(), Some("5239478"));
        assert_eq!(album.title.as_deref(), Some("In the End"));
        assert_eq!(album.r#type.as_deref(), Some("single"));
        assert_eq!(album.track_position.as_ref().unwrap().index, Some(2));
        assert_eq!(album.deprecation.as_ref().unwrap().target_album_id.as_deref(), Some("1"));
        assert_eq!(album.volumes.as_ref().unwrap().len(), 1);
        assert_eq!(album.labels.len(), 1);
        assert_eq!(album.action_button.as_ref().unwrap().view_browser, Some(true));
        assert_eq!(album.trailer.as_ref().unwrap().available, Some(true));
    }

    #[test]
    fn empty_album() {
        let album: Album = serde_json::from_str("{}").unwrap();
        assert!(album.id.is_none());
        assert!(album.artists.is_empty());
    }
}
