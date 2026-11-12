//! Port of `yandex_music/label`.

use serde::{Deserialize, Serialize};

/// Music label.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Label {
    /// Label id.
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub id: Option<String>,
    /// Label name.
    pub name: Option<String>,
    /// Description.
    pub description: Option<String>,
    /// Formatted description.
    pub description_formatted: Option<String>,
    /// Image URI.
    pub image: Option<String>,
    /// Links to the label pages.
    pub links: Option<Vec<crate::models::artist::Link>>,
    /// Label type.
    #[serde(rename = "type")]
    pub r#type: Option<String>,
}

/// Label albums page.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct LabelAlbums {
    /// Albums.
    pub albums: Vec<crate::models::album::Album>,
    /// Pager.
    pub pager: Option<crate::models::common::Pager>,
}

/// Label artists page.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct LabelArtists {
    /// Artists.
    pub artists: Vec<crate::models::artist::Artist>,
    /// Pager.
    pub pager: Option<crate::models::common::Pager>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn label_deserialize() {
        let json = serde_json::json!({
            "id": 148217,
            "name": "tommee profitt STUDIOS",
            "description": "Лейбл с Американской Саунд-машины",
            "descriptionFormatted": "Форматированное описание",
            "image": "avatars.yandex.net/get-music-misc/12345/label.148217.image/%%",
            "links": [{"title": "Site", "href": "https://example.com", "type": "official"}],
            "type": "musical"
        });
        let label: Label = serde_json::from_value(json).unwrap();
        assert_eq!(label.id.as_deref(), Some("148217"));
        assert_eq!(label.name.as_deref(), Some("tommee profitt STUDIOS"));
        assert_eq!(label.r#type.as_deref(), Some("musical"));
        assert_eq!(label.links.as_ref().unwrap()[0].href.as_deref(), Some("https://example.com"));
    }

    #[test]
    fn label_albums_deserialize() {
        let json = serde_json::json!({"albums": [{"id": 1}], "pager": {"total": 1}});
        let page: LabelAlbums = serde_json::from_value(json).unwrap();
        assert_eq!(page.albums.len(), 1);
        assert!(page.pager.is_some());
    }
}
