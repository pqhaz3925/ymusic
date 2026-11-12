//! Models of the `yandex_music/shot` package: Alice shots played before a track.

use serde::{Deserialize, Serialize};

/// Type of a shot produced by Alice.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ShotType {
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub id: Option<String>,
    pub title: Option<String>,
}

/// Core information about a shot.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ShotData {
    pub cover_uri: Option<String>,
    pub mds_url: Option<String>,
    pub shot_text: Option<String>,
    pub shot_type: Option<ShotType>,
}

/// A single shot from Alice.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Shot {
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub order: Option<i64>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub played: Option<bool>,
    pub shot_data: Option<ShotData>,
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub shot_id: Option<String>,
    pub status: Option<String>,
}

/// Event holding shots to play before the next track.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ShotEvent {
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub event_id: Option<String>,
    pub shots: Vec<Shot>,
}

#[cfg(test)]
mod tests {
    #[test]
    fn shot_de() {
        let v = r#"{"order":1,"played":false,"shotId":"42","status":"ready",
            "shotData":{"coverUri":"avatars.yandex.net/get-music-content/%%","mdsUrl":"https://x",
                        "shotText":"Hi","shotType":{"id":"1","title":"Joke"}}}"#;
        let s: super::Shot = serde_json::from_str(v).unwrap();
        assert_eq!(s.shot_id.as_deref(), Some("42"));
        assert_eq!(s.shot_data.unwrap().shot_type.unwrap().title.as_deref(), Some("Joke"));
        let e: super::ShotEvent = serde_json::from_str(r#"{"eventId":7,"shots":[]}"#).unwrap();
        assert_eq!(e.event_id.as_deref(), Some("7"));
    }
}
