//! Models of the `yandex_music/metatag` package (genre/mood metatags and their trees).

use serde::Deserialize;
use serde::Serialize;

/// Page of a metatag album list.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct MetatagAlbums {
    /// Unique metatag id.
    pub id: Option<String>,
    /// Cover uri.
    pub cover_uri: Option<String>,
    /// Accent color.
    pub color: Option<String>,
    /// Metatag title.
    pub title: Option<crate::models::metatag::MetatagTitle>,
    /// Radio station id.
    pub station_id: Option<String>,
    /// Pager.
    pub pager: Option<crate::models::common::Pager>,
    /// Albums of the metatag.
    pub albums: Vec<crate::models::album::Album>,
    /// Allowed sort values.
    pub sort_by_values: Vec<crate::models::metatag::MetatagSortByValue>,
}

/// Artist entry in a metatag artist list.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct MetatagArtistEntry {
    /// Artist.
    pub artist: Option<crate::models::artist::Artist>,
    /// Popular tracks of the artist.
    pub popular_tracks: Vec<crate::models::track::Track>,
}

/// Page of a metatag artist list.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct MetatagArtists {
    /// Unique metatag id.
    pub id: Option<String>,
    /// Cover uri.
    pub cover_uri: Option<String>,
    /// Accent color.
    pub color: Option<String>,
    /// Metatag title.
    pub title: Option<crate::models::metatag::MetatagTitle>,
    /// Radio station id.
    pub station_id: Option<String>,
    /// Pager.
    pub pager: Option<crate::models::common::Pager>,
    /// Artists of the metatag.
    pub artists: Vec<crate::models::metatag::MetatagArtistEntry>,
    /// Allowed sort values.
    pub sort_by_values: Vec<crate::models::metatag::MetatagSortByValue>,
}

/// Leaf node of a metatag tree.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct MetatagLeaf {
    /// Leaf tag.
    pub tag: Option<String>,
    /// Leaf title.
    pub title: Option<String>,
    /// Nested leaves.
    pub leaves: Vec<crate::models::metatag::MetatagLeaf>,
}

/// Page of a metatag playlist list.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct MetatagPlaylists {
    /// Unique metatag id.
    pub id: Option<String>,
    /// Cover uri.
    pub cover_uri: Option<String>,
    /// Accent color.
    pub color: Option<String>,
    /// Metatag title.
    pub title: Option<crate::models::metatag::MetatagTitle>,
    /// Radio station id.
    pub station_id: Option<String>,
    /// Pager.
    pub pager: Option<crate::models::common::Pager>,
    /// Playlists of the metatag.
    pub playlists: Vec<crate::models::playlist::Playlist>,
    /// Allowed sort values.
    pub sort_by_values: Vec<crate::models::metatag::MetatagSortByValue>,
}

/// One allowed sort value of a metatag.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct MetatagSortByValue {
    /// Sort value.
    pub value: Option<String>,
    /// Human readable title.
    pub title: Option<String>,
    /// Whether this value is selected.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub active: Option<bool>,
}

/// Metatag title with a short and full variant.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct MetatagTitle {
    /// Short title.
    pub title: Option<String>,
    /// Full title.
    pub full_title: Option<String>,
}

/// Navigation tree of metatags.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct MetatagTree {
    /// Tree title.
    pub title: Option<String>,
    /// Navigation id.
    pub navigation_id: Option<String>,
    /// Leaves of the tree.
    pub leaves: Vec<crate::models::metatag::MetatagLeaf>,
}

/// Metatag (genre, mood, activity).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Metatag {
    /// Unique metatag id.
    pub id: Option<String>,
    /// Cover uri.
    pub cover_uri: Option<String>,
    /// Accent color.
    pub color: Option<String>,
    /// Metatag title.
    pub title: Option<crate::models::metatag::MetatagTitle>,
    /// Whether the metatag is liked.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub liked: Option<bool>,
    /// Radio station id.
    pub station_id: Option<String>,
    /// Custom wave animation url.
    pub custom_wave_animation_url: Option<String>,
    /// Artists of the metatag.
    pub artists: Vec<crate::models::artist::Artist>,
    /// Albums of the metatag.
    pub albums: Vec<crate::models::album::Album>,
    /// Playlists of the metatag.
    pub playlists: Vec<crate::models::playlist::Playlist>,
    /// Track sort values.
    pub tracks_sort_by_values: Vec<crate::models::metatag::MetatagSortByValue>,
    /// Album sort values.
    pub albums_sort_by_values: Vec<crate::models::metatag::MetatagSortByValue>,
    /// Playlist sort values.
    pub playlists_sort_by_values: Vec<crate::models::metatag::MetatagSortByValue>,
}

/// Root metatags tree response.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Metatags {
    /// Trees.
    pub trees: Vec<crate::models::metatag::MetatagTree>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deserialize_metatags() {
        let json = r##"{
            "trees": [
                {"title": "Жанры", "navigationId": "genres", "leaves": [
                    {"tag": "rock", "title": "Рок", "leaves": [{"tag": "alt", "title": "Альтернатива"}]}
                ]}
            ]
        }"##;
        let v: Metatags = serde_json::from_str(json).unwrap();
        let tree = &v.trees[0];
        assert_eq!(tree.navigation_id.as_deref(), Some("genres"));
        assert_eq!(tree.leaves[0].leaves[0].tag.as_deref(), Some("alt"));
    }

    #[test]
    fn deserialize_metatag() {
        let json = r##"{
            "id": "pop", "coverUri": "avatars.yandex.net/get-music-content/1/%%",
            "color": "#ffcc00", "title": {"title": "Поп", "fullTitle": "Популярная музыка"},
            "liked": false, "stationId": "genre:pop",
            "artists": [], "albums": [], "playlists": [],
            "tracksSortByValues": [{"value": "popular", "title": "Популярные", "active": true}]
        }"##;
        let m: Metatag = serde_json::from_str(json).unwrap();
        assert_eq!(m.title.unwrap().full_title.as_deref(), Some("Популярная музыка"));
        assert_eq!(m.tracks_sort_by_values[0].active, Some(true));
    }

    #[test]
    fn deserialize_metatag_albums() {
        let json = r##"{"id": "pop", "pager": {"total": 1, "page": 0, "perPage": 20}, "albums": [{"id": 1, "title": "A"}]}"##;
        let a: MetatagAlbums = serde_json::from_str(json).unwrap();
        assert_eq!(a.albums[0].title.as_deref(), Some("A"));
        assert!(a.pager.is_some());
    }
}
