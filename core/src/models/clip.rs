//! Models of the `yandex_music/clip` package: music clips.

use serde::{Deserialize, Serialize};

/// Music clip (short video).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Clip {
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub clip_id: Option<String>,
    pub title: Option<String>,
    pub version: Option<String>,
    pub player_id: Option<String>,
    pub uuid: Option<String>,
    pub thumbnail: Option<String>,
    pub preview_url: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub duration: Option<i64>,
    #[serde(default, deserialize_with = "crate::models::de::opt_ids")]
    pub track_ids: Option<Vec<String>>,
    pub artists: Option<Vec<crate::models::artist::Artist>>,
    pub disclaimers: Option<Vec<String>>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub explicit: Option<bool>,
    pub cover: Option<crate::models::common::Cover>,
    pub content_restrictions: Option<crate::models::common::ContentRestrictions>,
}

/// Clips the user may like, with pager.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ClipsWillLike {
    pub clips: Option<Vec<Clip>>,
    pub pager: Option<crate::models::common::Pager>,
}

#[cfg(test)]
mod tests {
    #[test]
    fn clip_de() {
        let v = r#"{"clipId":"c-1","title":"Clip","version":"v","playerId":"p","uuid":"u",
            "thumbnail":"t","previewUrl":"pu","duration":30,"trackIds":[1,2],"artists":[],
            "disclaimers":["d"],"explicit":true,"cover":{"uri":"avatars/%%"},"contentRestrictions":{}}"#;
        let c: super::Clip = serde_json::from_str(v).unwrap();
        assert_eq!(c.clip_id.as_deref(), Some("c-1"));
        assert_eq!(c.track_ids.unwrap(), vec!["1".to_string(), "2".to_string()]);
        assert_eq!(c.explicit, Some(true));
        let w: super::ClipsWillLike = serde_json::from_str(r#"{"clips":[],"pager":{"total":0}}"#).unwrap();
        assert!(w.clips.unwrap().is_empty());
    }
}
