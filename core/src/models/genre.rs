//! Port of `yandex_music/genre`.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Music genre.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Genre {
    /// Genre id.
    pub id: Option<String>,
    /// Genre weight.
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub weight: Option<i64>,
    /// Whether the genre is used for the composer top.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub composer_top: Option<bool>,
    /// Genre title.
    pub title: Option<String>,
    /// Localized titles by language code.
    pub titles: HashMap<String, Option<Title>>,
    /// Genre images.
    pub images: Option<Images>,
    /// Whether the genre is shown in the menu.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub show_in_menu: Option<bool>,
    /// Regions where the genre is shown.
    pub show_in_regions: Option<Vec<i64>>,
    /// Full genre title.
    pub full_title: Option<String>,
    /// URL part.
    pub url_part: Option<String>,
    /// Genre color.
    pub color: Option<String>,
    /// Radio icon.
    pub radio_icon: Option<crate::models::common::Icon>,
    /// Sub-genres.
    pub sub_genres: Vec<Genre>,
    /// Regions where the genre is hidden.
    pub hide_in_regions: Option<Vec<i64>>,
}

/// Genre images.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Images {
    /// 208x208 image URI.
    #[serde(rename = "208x208")]
    pub x208x208: Option<String>,
    /// 300x300 image URI.
    #[serde(rename = "300x300")]
    pub x300x300: Option<String>,
}

/// Localized genre title.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Title {
    /// Title.
    pub title: Option<String>,
    /// Full title.
    pub full_title: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn genre_deserialize() {
        let json = serde_json::json!({
            "id": "all",
            "weight": 2,
            "composerTop": false,
            "title": "Все жанры",
            "titles": {"uz": {"title": "Hammasi", "fullTitle": "Barcha janrlar musiqasi"}},
            "images": {
                "208x208": "http://avatars.mds.yandex.net/get-music-misc/28052/metagenre-pop-x208/orig",
                "300x300": "http://avatars.mds.yandex.net/get-music-misc/28052/metagenre-pop-x300/orig"
            },
            "showInMenu": true,
            "showInRegions": [181],
            "fullTitle": "Музыка всех жанров",
            "radioIcon": {"image": "icon.png"},
            "subGenres": [{"id": "pop", "weight": 1}],
            "hideInRegions": []
        });
        let genre: Genre = serde_json::from_value(json).unwrap();
        assert_eq!(genre.id.as_deref(), Some("all"));
        assert_eq!(genre.weight, Some(2));
        assert_eq!(genre.composer_top, Some(false));
        assert_eq!(genre.titles["uz"].as_ref().unwrap().title.as_deref(), Some("Hammasi"));
        assert!(genre.images.as_ref().unwrap().x208x208.is_some());
        assert_eq!(genre.sub_genres.len(), 1);
        assert!(genre.radio_icon.is_some());
    }
}
