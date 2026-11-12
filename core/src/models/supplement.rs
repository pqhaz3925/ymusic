//! Models of the `yandex_music/supplement` package: extra track info (lyrics, video).

use serde::{Deserialize, Serialize};

/// Lyrics of a track (deprecated, prefer tracks_lyrics).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Lyrics {
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub id: Option<i64>,
    pub lyrics: Option<String>,
    pub full_lyrics: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub has_rights: Option<bool>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub show_translation: Option<bool>,
    pub text_language: Option<String>,
    pub url: Option<String>,
}

/// A video supplement of a track.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct VideoSupplement {
    pub cover: Option<String>,
    pub provider: Option<String>,
    pub title: Option<String>,
    pub provider_video_id: Option<String>,
    pub url: Option<String>,
    pub embed_url: Option<String>,
    pub embed: Option<String>,
}

/// Extra information about a track.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Supplement {
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub id: Option<i64>,
    pub lyrics: Option<Lyrics>,
    pub videos: Vec<VideoSupplement>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub radio_is_available: Option<bool>,
    pub description: Option<String>,
}

#[cfg(test)]
mod tests {
    #[test]
    fn supplement_de() {
        let v = r#"{"id":123,"radioIsAvailable":true,"description":"d",
            "lyrics":{"id":123,"lyrics":"[00:00.00] hi","fullLyrics":"hi","hasRights":true,
                      "showTranslation":false,"textLanguage":"en","url":"https://l"},
            "videos":[{"cover":"c","provider":"youtube","title":"t","providerVideoId":"vid",
                       "url":"u","embedUrl":"eu","embed":"<iframe>"}]}"#;
        let s: super::Supplement = serde_json::from_str(v).unwrap();
        assert_eq!(s.lyrics.unwrap().text_language.as_deref(), Some("en"));
        assert_eq!(s.videos[0].provider.as_deref(), Some("youtube"));
        assert_eq!(s.radio_is_available, Some(true));
    }
}
