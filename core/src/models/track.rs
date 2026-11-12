//! Models of the Python package `yandex_music/track/`.

use serde::{Deserialize, Serialize};

/// Track fade (in/out) parameters in seconds.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Fade {
    pub in_start: Option<f64>,
    pub in_stop: Option<f64>,
    pub out_start: Option<f64>,
    pub out_stop: Option<f64>,
}

/// Download information for one file of a track (quality, codec, bitrate, url).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct FileDownloadInfo {
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub track_id: Option<String>,
    pub quality: Option<String>,
    pub codec: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub bitrate: Option<i64>,
    pub transport: Option<String>,
    pub url: Option<String>,
    pub urls: Vec<String>,
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub real_id: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub gain: Option<bool>,
    pub key: Option<String>,
}

/// Wrapper holding download info of a track file.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct FileInfo {
    pub download_info: Option<crate::models::track::FileDownloadInfo>,
}

/// Part of a licence text with an optional agreement url.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct LicenceTextPart {
    pub text: Option<String>,
    pub url: Option<String>,
}

/// Availability flags for synchronized and plain text lyrics.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct LyricsInfo {
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub has_available_sync_lyrics: Option<bool>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub has_available_text_lyrics: Option<bool>,
}

/// Lyrics provider service (major).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct LyricsMajor {
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub id: Option<String>,
    pub name: Option<String>,
    pub pretty_name: Option<String>,
}

/// Label/major owning the track.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Major {
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub id: Option<String>,
    pub name: Option<String>,
}

/// Track metadata (album name, year, number, genre, etc.).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct MetaData {
    pub album: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub volume: Option<i64>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub year: Option<i64>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub number: Option<i64>,
    pub genre: Option<String>,
    pub lyricist: Option<String>,
    pub version: Option<String>,
    pub composer: Option<String>,
}

/// Audio loudness normalization values.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Normalization {
    #[serde(deserialize_with = "crate::models::de::opt_f64")]
    pub gain: Option<f64>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub peak: Option<i64>,
}

/// Poetry annotation span (begin/end offsets and line index).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct PoetryLoverMatch {
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub begin: Option<i64>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub end: Option<i64>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub line: Option<i64>,
}

/// EBU R128 loudness parameters (integrated loudness and true peak).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct R128 {
    #[serde(deserialize_with = "crate::models::de::opt_f64")]
    pub i: Option<f64>,
    #[serde(deserialize_with = "crate::models::de::opt_f64")]
    pub tp: Option<f64>,
}

/// Smart preview parameters (duration and fade).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct SmartPreviewParams {
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub duration_ms: Option<i64>,
    pub fade: Option<crate::models::track::Fade>,
}

/// Full track information with similar tracks, aliases and detailed artists.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct TrackFullInfo {
    pub track: Option<Box<crate::models::track::Track>>,
    pub similar_tracks: Vec<crate::models::track::Track>,
    pub also_in_albums: Vec<crate::models::track::Track>,
    pub aliases: Option<Vec<String>>,
    pub artists: Vec<crate::models::artist::Artist>,
}

/// Lyrics description: download url, ids, writers and provider.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct TrackLyrics {
    pub download_url: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub lyric_id: Option<String>,
    pub external_lyric_id: Option<String>,
    pub writers: Option<Vec<String>>,
    pub major: Option<crate::models::track::LyricsMajor>,
}

/// Trailer of a track (title and the track itself).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct TrackTrailer {
    pub title: Option<String>,
    pub track: Option<Box<crate::models::track::Track>>,
}

/// A track with its similar tracks.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct SimilarTracks {
    pub track: Option<Box<crate::models::track::Track>>,
    pub similar_tracks: Vec<crate::models::track::Track>,
}

/// Music track or podcast episode.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Track {
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub id: Option<String>,
    pub title: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub available: Option<bool>,
    pub artists: Vec<crate::models::artist::Artist>,
    pub albums: Vec<crate::models::album::Album>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub available_for_premium_users: Option<bool>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub lyrics_available: Option<bool>,
    pub poetry_lover_matches: Vec<crate::models::track::PoetryLoverMatch>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub best: Option<bool>,
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub real_id: Option<String>,
    pub og_image: Option<String>,
    #[serde(rename = "type")]
    pub r#type: Option<String>,
    pub cover_uri: Option<String>,
    pub major: Option<crate::models::track::Major>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub duration_ms: Option<i64>,
    pub storage_dir: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub file_size: Option<i64>,
    pub substituted: Option<Box<crate::models::track::Track>>,
    pub matched_track: Option<Box<crate::models::track::Track>>,
    pub normalization: Option<crate::models::track::Normalization>,
    pub error: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub can_publish: Option<bool>,
    pub state: Option<String>,
    pub desired_visibility: Option<String>,
    pub filename: Option<String>,
    pub user_info: Option<crate::models::account::User>,
    pub meta_data: Option<crate::models::track::MetaData>,
    pub regions: Option<Vec<String>>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub available_as_rbt: Option<bool>,
    pub content_warning: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub explicit: Option<bool>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub preview_duration_ms: Option<i64>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub available_full_without_permission: Option<bool>,
    pub version: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub remember_position: Option<bool>,
    pub background_video_uri: Option<String>,
    pub short_description: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub is_suitable_for_children: Option<bool>,
    pub track_source: Option<String>,
    pub available_for_options: Option<Vec<String>>,
    pub r128: Option<crate::models::track::R128>,
    pub lyrics_info: Option<crate::models::track::LyricsInfo>,
    pub track_sharing_flag: Option<String>,
    pub derived_colors: Option<crate::models::common::CoverDerivedColors>,
    pub fade: Option<crate::models::track::Fade>,
    pub smart_preview_params: Option<crate::models::track::SmartPreviewParams>,
    pub special_audio_resources: Option<Vec<String>>,
    pub disclaimers: Option<Vec<String>>,
    pub background_video_id: Option<String>,
    pub player_id: Option<String>,
    pub mix_fade: Option<crate::models::track::Fade>,
    pub chart: Option<crate::models::landing::Chart>,
    /// The API sends these as numbers (older responses: strings).
    #[serde(deserialize_with = "crate::models::de::ids")]
    pub clip_ids: Vec<String>,
    pub isrc: Option<String>,
    pub ugc_artist_name: Option<String>,
    pub podcast_episode_type: Option<String>,
    pub pub_date: Option<String>,
    /// Local download info cache (filled by the client, not by the API).
    pub download_info: Option<Vec<crate::models::common::DownloadInfo>>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn track_deserializes() {
        let json = r#"{
            "id": "10994777", "realId": 10994777, "title": "Sapphire",
            "available": true, "availableForPremiumUsers": true, "lyricsAvailable": false,
            "best": false, "type": "music", "coverUri": "avatars.yandex.net/x/%%",
            "durationMs": "251270", "fileSize": 6036792, "version": "Radio Edit",
            "rememberPosition": false, "trackSource": "OWN",
            "availableForOptions": ["bookmate"], "trackSharingFlag": "VIDEO_ALLOWED",
            "clipIds": ["100500", "100501"], "isrc": "RUA000000001",
            "major": {"id": 1, "name": "Major Label"},
            "normalization": {"gain": "1.5", "peak": 2},
            "r128": {"i": -8.3, "tp": 0.5},
            "fade": {"inStart": 0.0, "inStop": 0.5, "outStart": 250.0, "outStop": 251.2},
            "smartPreviewParams": {"durationMs": 30000, "fade": {"inStart": 0.0}},
            "lyricsInfo": {"hasAvailableSyncLyrics": true, "hasAvailableTextLyrics": true},
            "metaData": {"album": "A", "volume": 1, "year": 2020, "number": 3, "genre": "pop"},
            "poetryLoverMatches": [{"begin": 0, "end": 5, "line": 1}],
            "chart": {"position": 1, "progress": "up"},
            "artists": [], "albums": []
        }"#;
        let t: Track = serde_json::from_str(json).unwrap();
        assert_eq!(t.id.as_deref(), Some("10994777"));
        assert_eq!(t.real_id.as_deref(), Some("10994777"));
        assert_eq!(t.duration_ms, Some(251270));
        assert_eq!(t.r#type.as_deref(), Some("music"));
        assert_eq!(t.clip_ids, vec!["100500", "100501"]);
        assert_eq!(t.r128.as_ref().unwrap().i, Some(-8.3));
        assert_eq!(t.normalization.as_ref().unwrap().gain, Some(1.5));
        assert_eq!(t.fade.as_ref().unwrap().out_stop, Some(251.2));
        assert_eq!(t.meta_data.as_ref().unwrap().year, Some(2020));
        assert!(t.chart.is_some());
    }

    #[test]
    fn file_download_info_deserializes() {
        let json = r#"{"trackId": "123", "quality": "lossless", "codec": "flac",
            "bitrate": 1411, "transport": "raw", "url": "http://x",
            "urls": ["http://x"], "realId": 123, "gain": true, "key": "abcd"}"#;
        let d: FileDownloadInfo = serde_json::from_str(json).unwrap();
        assert_eq!(d.track_id.as_deref(), Some("123"));
        assert_eq!(d.real_id.as_deref(), Some("123"));
        assert_eq!(d.gain, Some(true));
        assert_eq!(d.urls.len(), 1);
    }

    #[test]
    fn full_info_and_similar() {
        let f: TrackFullInfo =
            serde_json::from_str(r#"{"track":{"id":1},"similarTracks":[{"id":2}],"aliases":["a"]}"#)
                .unwrap();
        assert_eq!(f.track.unwrap().id.as_deref(), Some("1"));
        assert_eq!(f.similar_tracks.len(), 1);
        let s: SimilarTracks =
            serde_json::from_str(r#"{"track":{"id":"5"},"similarTracks":[{"id":6}]}"#).unwrap();
        assert_eq!(s.track.unwrap().id.as_deref(), Some("5"));
        assert_eq!(s.similar_tracks[0].id.as_deref(), Some("6"));
    }

    #[test]
    fn lyrics_models() {
        let l: TrackLyrics = serde_json::from_str(
            r#"{"downloadUrl":"http://x","lyricId":42,"externalLyricId":"ext","writers":["w"],
                "major":{"id":7,"name":"svc","prettyName":"Service"}}"#,
        )
        .unwrap();
        assert_eq!(l.lyric_id.as_deref(), Some("42"));
        assert_eq!(l.major.unwrap().pretty_name.as_deref(), Some("Service"));
        let t: TrackTrailer = serde_json::from_str(r#"{"title":"t","track":{"id":1}}"#).unwrap();
        assert!(t.track.is_some());
    }
}
