//! Root-level models of the Python package (`yandex_music/*.py`): covers, likes,
//! short tracks, credits, pagination and other shared value objects.

use serde::{Deserialize, Serialize};

fn de_type<'de, D: serde::Deserializer<'de>>(d: D) -> Result<Option<String>, D::Error> {
    crate::models::de::opt_id(d)
}

/// Content restrictions: availability flag and disclaimers.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ContentRestrictions {
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub available: Option<bool>,
    pub disclaimers: Option<Vec<String>>,
}

/// Derived colors computed from a cover image.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct CoverDerivedColors {
    pub average: Option<String>,
    pub wave_text: Option<String>,
    pub mini_player: Option<String>,
    pub accent: Option<String>,
}

/// Album/playlist cover description with its image URI template.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Cover {
    #[serde(rename = "type")]
    pub r#type: Option<String>,
    pub uri: Option<String>,
    pub items_uri: Option<Vec<String>>,
    pub dir: Option<String>,
    pub version: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub custom: Option<bool>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub is_custom: Option<bool>,
    pub copyright_name: Option<String>,
    pub copyright_cline: Option<String>,
    pub prefix: Option<String>,
    pub error: Option<String>,
    pub color: Option<String>,
    pub derived_colors: Option<CoverDerivedColors>,
    pub video_url: Option<String>,
}

impl Cover {
    /// Builds the image URL for the given size (e.g. `400x400`).
    pub fn get_url(&self, index: usize, size: &str) -> Option<String> {
        let uri = match &self.uri {
            Some(u) if !u.is_empty() => u.clone(),
            _ => self.items_uri.as_ref()?.get(index)?.clone(),
        };
        Some(format!("https://{}", uri.replace("%%", size)))
    }
}

/// One participant of content creation (role and name).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Credit {
    pub title: Option<String>,
    pub value: Option<String>,
}

/// List of credits of a track, clip, etc.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Credits {
    pub credits: Option<Vec<Credit>>,
}

/// Disclaimer with foreign agent information.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Disclaimer {
    pub foreign_agent: Option<ForeignAgent>,
}

/// Salt used to sign direct download links.
pub const SIGN_SALT: &str = "XGRlBW9FXlekgbPrRHuSiA";

/// Available download variant of a track.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct DownloadInfo {
    pub codec: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub bitrate_in_kbps: Option<i64>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub gain: Option<bool>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub preview: Option<bool>,
    pub download_info_url: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub direct: Option<bool>,
    #[serde(skip)]
    pub direct_link: Option<String>,
}

impl DownloadInfo {
    /// Builds the direct link from the XML download-info document (same algorithm as Python).
    pub fn build_direct_link(xml: &[u8]) -> Option<String> {
        use md5::Digest;
        let doc = roxmltree::Document::parse(std::str::from_utf8(xml).ok()?).ok()?;
        let text = |tag: &str| {
            doc.descendants()
                .find(|n| n.has_tag_name(tag))
                .and_then(|n| n.text())
                .map(str::to_owned)
        };
        let host = text("host")?;
        let path = text("path")?;
        let ts = text("ts")?;
        let s = text("s")?;
        let body = format!("{}{}{}", SIGN_SALT, &path[1..], s);
        let sign = format!("{:x}", md5::Md5::digest(body.as_bytes()));
        Some(format!("https://{host}/get-mp3/{sign}/{ts}{path}"))
    }
}

/// Experimental feature flags keyed by arbitrary experiment names.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(transparent)]
pub struct Experiments(pub serde_json::Map<String, serde_json::Value>);

/// Foreign agent status warning.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ForeignAgent {
    pub reason: Option<String>,
    pub title: Option<String>,
}

/// Small icon with background color and image URL.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Icon {
    pub background_color: Option<String>,
    pub image_url: Option<String>,
}

impl Icon {
    /// Builds the icon image URL for the given size.
    pub fn get_url(&self, size: &str) -> Option<String> {
        Some(format!("https://{}", self.image_url.as_ref()?.replace("%%", size)))
    }
}

/// Information about the request that produced a response.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct InvocationInfo {
    pub hostname: Option<String>,
    pub req_id: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub exec_duration_millis: Option<i64>,
    pub app_name: Option<String>,
}

/// "Liked" mark on an album, artist or playlist.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Like {
    #[serde(rename = "type", deserialize_with = "de_type")]
    pub r#type: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub id: Option<String>,
    pub timestamp: Option<String>,
    pub album: Option<Box<crate::models::album::Album>>,
    pub artist: Option<Box<crate::models::artist::Artist>>,
    pub playlist: Option<Box<crate::models::playlist::Playlist>>,
    pub short_description: Option<String>,
    pub description: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub is_premiere: Option<bool>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub is_banner: Option<bool>,
}

/// Pagination information.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Pager {
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub total: Option<i64>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub page: Option<i64>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub per_page: Option<i64>,
}

/// Permission alerts shown to the user.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct PermissionAlerts {
    pub alerts: Option<Vec<String>>,
}

/// Result of promo code activation.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct PromoCodeStatus {
    pub status: Option<String>,
    #[serde(rename = "status_desc", alias = "statusDesc")]
    pub status_desc: Option<String>,
    pub account_status: Option<crate::models::account::Status>,
}

/// Purchase offers: in-app products, web payment URL, promo codes.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Settings {
    pub in_app_products: Option<Vec<crate::models::account::Product>>,
    pub native_products: Option<Vec<crate::models::account::Product>>,
    pub web_payment_url: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    #[serde(rename = "promo_codes_enabled", alias = "promoCodesEnabled")]
    pub promo_codes_enabled: Option<bool>,
    pub web_payment_month_product_price: Option<crate::models::account::Price>,
}

/// Short track representation (track id, album id, optional chart info).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct TrackShort {
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub id: Option<String>,
    pub timestamp: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub album_id: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub play_count: Option<i64>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub recent: Option<bool>,
    pub chart: Option<Box<crate::models::landing::Chart>>,
    pub track: Option<Box<crate::models::track::Track>>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub original_index: Option<i64>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub original_shuffle_index: Option<i64>,
}

impl TrackShort {
    /// `id:album_id` (or just `id` when album id is absent).
    pub fn track_id(&self) -> String {
        match (&self.id, &self.album_id) {
            (Some(id), Some(album)) if !album.is_empty() => format!("{id}:{album}"),
            (Some(id), _) => id.clone(),
            (None, _) => String::new(),
        }
    }
}

/// List of short tracks belonging to a user (e.g. liked tracks).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct TracksList {
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub uid: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub revision: Option<i64>,
    pub tracks: Option<Vec<TrackShort>>,
}

impl TracksList {
    /// Track ids in `id:album` form.
    pub fn tracks_ids(&self) -> Vec<String> {
        self.tracks.iter().flatten().map(TrackShort::track_id).collect()
    }
}

/// Trailer information with its tracks.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct TrailerInfo {
    pub title: Option<String>,
    pub tracks: Option<Vec<crate::models::track::Track>>,
}

/// Video attached to a track.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Video {
    pub title: Option<String>,
    pub cover: Option<String>,
    pub embed_url: Option<String>,
    pub provider: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub provider_video_id: Option<String>,
    pub youtube_url: Option<String>,
    pub thumbnail_url: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub duration: Option<i64>,
    pub text: Option<String>,
    pub html_auto_play_video_player: Option<String>,
    pub regions: Option<Vec<String>>,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse<T: serde::de::DeserializeOwned>(s: &str) -> T {
        serde_json::from_str(s).expect("deserialize")
    }

    #[test]
    fn cover_and_derived_colors() {
        let c: Cover = parse(
            r##"{"type":"Mosaic","uri":"avatars.yandex.net/get-music-content/1/%%","itemsUri":["a/%%","b/%%"],
                "version":"1","custom":false,"prefix":"abc","color":"#6d6e72","unknownKey":1,
                "derivedColors":{"average":"#6d6e72","waveText":"#ffffff","miniPlayer":"#000","accent":"#ff0000"}}"##,
        );
        assert_eq!(c.r#type.as_deref(), Some("Mosaic"));
        assert_eq!(c.custom, Some(false));
        assert_eq!(c.derived_colors.as_ref().unwrap().wave_text.as_deref(), Some("#ffffff"));
        assert_eq!(
            c.get_url(0, "400x400").as_deref(),
            Some("https://avatars.yandex.net/get-music-content/1/400x400")
        );
    }

    #[test]
    fn credits_and_disclaimer() {
        let cr: Credits = parse(r#"{"credits":[{"title":"Author","value":"Someone"}]}"#);
        assert_eq!(cr.credits.unwrap()[0].value.as_deref(), Some("Someone"));
        let d: Disclaimer = parse(r#"{"foreignAgent":{"reason":"policy","title":"Includes"}}"#);
        assert_eq!(d.foreign_agent.unwrap().reason.as_deref(), Some("policy"));
    }

    #[test]
    fn download_info_and_xml() {
        let d: DownloadInfo = parse(
            r#"{"codec":"mp3","bitrateInKbps":320,"gain":true,"preview":false,
                "downloadInfoUrl":"https://storage.mds.yandex.net/get-mp3-info/1234/abc","direct":false}"#,
        );
        assert_eq!(d.bitrate_in_kbps, Some(320));
        assert_eq!(d.gain, Some(true));
        let xml = br#"<download-info><host>storage.mds.yandex.net</host><ts>1613414830</ts>
            <path>/get-mp3/0/abc</path><s>signature</s></download-info>"#;
        let link = DownloadInfo::build_direct_link(xml).unwrap();
        assert!(link.starts_with("https://storage.mds.yandex.net/get-mp3/"));
        assert!(link.ends_with("/1613414830/get-mp3/0/abc"));
    }

    #[test]
    fn icon_invocation_pager() {
        let i: Icon = parse(r##"{"backgroundColor":"#7b3f00","imageUrl":"avatars.yandex.net/%%"}"##);
        assert_eq!(i.get_url("200x200").as_deref(), Some("https://avatars.yandex.net/200x200"));
        let v: InvocationInfo = parse(r#"{"hostname":"music-wave","reqId":"1","execDurationMillis":"12"}"#);
        assert_eq!(v.exec_duration_millis, Some(12));
        let p: Pager = parse(r#"{"total":100,"page":0,"perPage":50}"#);
        assert_eq!(p.per_page, Some(50));
    }

    #[test]
    fn like_and_experiments() {
        let l: Like = parse(
            r#"{"type":"album","id":123,"timestamp":"2020-01-01T00:00:00+03:00","isPremiere":true,
                "album":{"id":123,"title":"A"},"unknown":true}"#,
        );
        assert_eq!(l.r#type.as_deref(), Some("album"));
        assert_eq!(l.id.as_deref(), Some("123"));
        assert_eq!(l.is_premiere, Some(true));
        assert_eq!(l.album.unwrap().id.as_deref(), Some("123"));
        let e: Experiments = parse(r#"{"foo":"bar","baz":1}"#);
        assert_eq!(e.0["foo"], serde_json::json!("bar"));
    }

    #[test]
    fn track_short_and_list() {
        let t: TrackShort = parse(
            r#"{"id":111,"timestamp":"2020-01-01","albumId":222,"playCount":5,"recent":true,
                "chart":{"position":1,"progress":"up","listeners":10,"shift":0}}"#,
        );
        assert_eq!(t.track_id(), "111:222");
        assert_eq!(t.chart.unwrap().position, Some(1));
        let list: TracksList = parse(r#"{"uid":1,"revision":2,"tracks":[{"id":"111","albumId":"222"}]}"#);
        assert_eq!(list.uid.as_deref(), Some("1"));
        assert_eq!(list.tracks_ids(), vec!["111:222".to_string()]);
    }

    #[test]
    fn settings_promo_video_trailer() {
        let s: Settings = parse(
            r#"{"inAppProducts":[{"productId":"p1","type":"T","duration":1,"trialDuration":0,"feature":"f",
                "debug":false,"plus":true,"price":{"amount":19900,"currency":"RUB"}}],
                "nativeProducts":[],"webPaymentUrl":"https://yandex.ru","promo_codes_enabled":true,
                "webPaymentMonthProductPrice":{"amount":1,"currency":"RUB"}}"#,
        );
        assert_eq!(s.promo_codes_enabled, Some(true));
        assert_eq!(s.in_app_products.unwrap()[0].price.as_ref().unwrap().amount, Some(19900));
        let p: PromoCodeStatus = parse(r#"{"status":"ok","status_desc":"Activated","account_status":null}"#);
        assert_eq!(p.status_desc.as_deref(), Some("Activated"));
        let v: Video = parse(r#"{"title":"V","providerVideoId":10413967802532191922,"duration":60}"#);
        assert_eq!(v.provider_video_id.as_deref(), Some("10413967802532191922"));
        let t: TrailerInfo = parse(r#"{"title":"T","tracks":[{"id":1}]}"#);
        assert_eq!(t.tracks.unwrap().len(), 1);
    }

    #[test]
    fn misc_small() {
        let r: ContentRestrictions = parse(r#"{"available":true,"disclaimers":["18+"]}"#);
        assert_eq!(r.available, Some(true));
        let c: Credit = parse(r#"{"title":"t","value":"v"}"#);
        assert_eq!(c.title.as_deref(), Some("t"));
        let a: PermissionAlerts = parse(r#"{"alerts":["x"]}"#);
        assert_eq!(a.alerts.unwrap().len(), 1);
    }
}
