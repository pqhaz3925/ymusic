//! Models of the `yandex_music/queue` package: playback queue of devices.

use serde::{Deserialize, Serialize};

/// Describes what the queue was built from (various, my_music, radio, playlist, artist).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Context {
    pub r#type: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub id: Option<String>,
    pub description: Option<String>,
}

/// A queue entry in the list of device queues.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct QueueItem {
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub id: Option<String>,
    pub context: Option<Context>,
    pub modified: Option<String>,
}

/// A playback queue with its tracks.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Queue {
    pub context: Option<Context>,
    pub tracks: Vec<crate::models::landing::TrackId>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub current_index: Option<i64>,
    pub modified: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub id: Option<String>,
    #[serde(rename = "from")]
    pub from_: Option<String>,
}

#[cfg(test)]
mod tests {
    #[test]
    fn queue_de() {
        let v: serde_json::Value = serde_json::from_str(
            r#"{"context":{"type":"playlist","id":"1234:567","description":"My playlist"},
                "tracks":[{"id":"1","trackId":"2","albumId":3,"from":"playlist"}],
                "currentIndex":0,"modified":"2024-01-01T00:00:00","id":"dev-queue","from":"android"}"#,
        )
        .unwrap();
        let q: super::Queue = serde_json::from_value(v).unwrap();
        assert_eq!(q.context.unwrap().id.as_deref(), Some("1234:567"));
        assert_eq!(q.tracks[0].album_id, Some(3));
        assert_eq!(q.current_index, Some(0));
        assert_eq!(q.from_.as_deref(), Some("android"));
        let item: super::QueueItem =
            serde_json::from_str(r#"{"id":5,"context":{"type":"radio"},"modified":"m"}"#).unwrap();
        assert_eq!(item.id.as_deref(), Some("5"));
    }
}
