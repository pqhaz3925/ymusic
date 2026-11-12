//! Models of the `yandex_music/pin` package (pinned items on the main screen).

use serde::Deserialize;
use serde::Serialize;

/// Data of a pinned item.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct PinData {
    /// Item id.
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub id: Option<i64>,
    /// Owner user id.
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub uid: Option<i64>,
    /// Playlist kind.
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub kind: Option<i64>,
    /// Playlist uuid.
    pub playlist_uuid: Option<String>,
    /// Name.
    pub name: Option<String>,
    /// Title.
    pub title: Option<String>,
    /// Cover.
    pub cover: Option<crate::models::common::Cover>,
    /// Content restrictions.
    pub content_restrictions: Option<crate::models::common::ContentRestrictions>,
}

/// One pinned item.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Pin {
    /// Pin type.
    pub r#type: Option<String>,
    /// Pin data.
    pub data: Option<crate::models::pin::PinData>,
}

/// List of pinned items.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct PinsList {
    /// Pins.
    pub pins: Option<Vec<crate::models::pin::Pin>>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deserialize_pins() {
        let json = r##"{"pins": [
            {"type": "playlist", "data": {"id": 5, "uid": 123456, "kind": 1000, "title": "Мой плейлист", "cover": {"uri": "avatars/%%"}, "contentRestrictions": {}}}
        ]}"##;
        let p: PinsList = serde_json::from_str(json).unwrap();
        let pin = &p.pins.unwrap()[0];
        assert_eq!(pin.r#type.as_deref(), Some("playlist"));
        let d = pin.data.as_ref().unwrap();
        assert_eq!(d.uid, Some(123456));
        assert_eq!(d.title.as_deref(), Some("Мой плейлист"));
        assert!(d.cover.is_some());
    }
}
