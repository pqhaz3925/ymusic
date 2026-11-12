//! Models of the `yandex_music/search` package: search results, banners and suggestions.

use serde::{Deserialize, Serialize};

/// Best match of a search (result shape depends on `type`).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Best {
    pub r#type: Option<String>,
    pub result: Option<serde_json::Value>,
    pub text: Option<String>,
}

/// Banner shown in search results.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct SearchBanner {
    pub text: Option<String>,
    pub text_for_search: Option<String>,
    pub url: Option<String>,
    pub url_scheme: Option<String>,
    pub text_color: Option<String>,
    pub text_background_color: Option<String>,
    pub image_url: Option<String>,
}

/// Results of one search category (track, artist, album, ...).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct SearchResult {
    pub r#type: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub total: Option<i64>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub per_page: Option<i64>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub order: Option<i64>,
    pub results: Vec<serde_json::Value>,
}

/// Full search response.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Search {
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub search_request_id: Option<String>,
    pub text: Option<String>,
    pub best: Option<Best>,
    pub albums: Option<SearchResult>,
    pub artists: Option<SearchResult>,
    pub playlists: Option<SearchResult>,
    pub tracks: Option<SearchResult>,
    pub videos: Option<SearchResult>,
    pub users: Option<SearchResult>,
    pub podcasts: Option<SearchResult>,
    pub podcast_episodes: Option<SearchResult>,
    pub clips: Option<SearchResult>,
    pub banner: Option<SearchBanner>,
    pub r#type: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub page: Option<i64>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub per_page: Option<i64>,
    pub misspell_result: Option<String>,
    pub misspell_original: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub misspell_corrected: Option<bool>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub nocorrect: Option<bool>,
}

/// Search suggestions.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Suggestions {
    pub best: Option<Best>,
    pub suggestions: Vec<String>,
}

#[cfg(test)]
mod tests {
    #[test]
    fn search_de() {
        let v = r#"{"searchRequestId":"req-1","text":"muse","best":{"type":"track","result":{"id":"1"},"text":"Muse"},
            "tracks":{"total":10,"perPage":1,"order":0,"results":[{"id":"1"}]},
            "albums":{"total":0,"perPage":1,"order":0,"results":[]},
            "banner":{"text":"b","textForSearch":"s","url":"u","urlScheme":"us","textColor":"FFFFFF",
                      "textBackgroundColor":"000000","imageUrl":"i"},
            "type":"all","page":0,"perPage":1,"misspellResult":null,"misspellCorrected":false,"nocorrect":true}"#;
        let s: super::Search = serde_json::from_str(v).unwrap();
        assert_eq!(s.best.unwrap().r#type.as_deref(), Some("track"));
        assert_eq!(s.tracks.unwrap().total, Some(10));
        assert_eq!(s.banner.unwrap().text_color.as_deref(), Some("FFFFFF"));
        assert_eq!(s.nocorrect, Some(true));
        let g: super::Suggestions = serde_json::from_str(r#"{"best":null,"suggestions":["a","b"]}"#).unwrap();
        assert_eq!(g.suggestions.len(), 2);
    }
}
