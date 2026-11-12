//! Port of `yandex_music/_client/tracks.py`.

use std::time::{SystemTime, UNIX_EPOCH};

use reqwest::header::{HeaderMap, HeaderValue};
use reqwest::Method;
use serde_json::Value;

use super::Client;
use crate::error::{Error, Result};
use crate::http::{from_value, from_value_opt, is_ok, join};
use crate::models::common::DownloadInfo;
use crate::models::shot::ShotEvent;
use crate::models::supplement::Supplement;
use crate::models::track::{FileInfo, SimilarTracks, Track, TrackFullInfo, TrackLyrics, TrackTrailer};
use crate::utils::{get_file_info_sign, get_sign_request_default, DESKTOP_CLIENT, DESKTOP_SIGN_KEY};

/// Codecs requested by default from `/get-file-info`.
pub const FILE_INFO_CODECS: [&str; 7] = ["flac", "flac-mp4", "aac-mp4", "he-aac-mp4", "aac", "he-aac", "mp3"];

/// Preferred stream quality for [`Client::direct_link`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Quality {
    Lossless,
    High,
    Normal,
}

impl Quality {
    /// Parses `lossless` / `hq` / `nq`; anything else is `hq`.
    pub fn parse(s: &str) -> Self {
        match s {
            "lossless" => Quality::Lossless,
            "nq" | "lq" | "low" => Quality::Normal,
            _ => Quality::High,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Quality::Lossless => "lossless",
            Quality::High => "hq",
            Quality::Normal => "nq",
        }
    }
}

/// Resolved stream: url, codec, bitrate and (for `encraw`) the AES key in hex.
#[derive(Debug, Clone, Default)]
pub struct StreamInfo {
    pub url: String,
    pub codec: String,
    pub bitrate: Option<i64>,
    pub key: Option<String>,
    /// Quality the server actually granted (`lossless` / `hq` / `nq`), when it says so.
    pub quality: Option<String>,
}

/// Current UTC time as ISO 8601 with milliseconds (`2024-01-01T12:00:00.000Z`).
fn utc_now_iso() -> String {
    let d = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default();
    let secs = d.as_secs() as i64;
    let ms = d.subsec_millis();
    let (days, rem) = (secs.div_euclid(86_400), secs.rem_euclid(86_400));
    // Civil-from-days (Howard Hinnant).
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);
    format!(
        "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}.{ms:03}Z",
        rem / 3600,
        rem % 3600 / 60,
        rem % 60
    )
}

impl Client {
    /// Fetch tracks by ids (`POST /tracks`).
    pub async fn tracks<S: AsRef<str>>(&self, track_ids: &[S], with_positions: bool) -> Result<Vec<Track>> {
        let url = self.url("/tracks");
        let form = [
            ("track-ids", join(track_ids)),
            ("with-positions", if with_positions { "True" } else { "False" }.to_owned()),
        ];
        from_value(self.http.post(&url, &form).await?)
    }

    /// Like [`Client::tracks`], but a track whose model fails to parse is skipped instead of
    /// failing the whole batch (one odd field must not empty a 700-track list).
    pub async fn tracks_lenient<S: AsRef<str>>(&self, track_ids: &[S]) -> Result<Vec<Track>> {
        let url = self.url("/tracks");
        let form = [("track-ids", join(track_ids)), ("with-positions", "False".to_owned())];
        Ok(match self.http.post(&url, &form).await? {
            Value::Array(items) => items.into_iter().filter_map(|v| serde_json::from_value(v).ok()).collect(),
            _ => Vec::new(),
        })
    }

    /// Download variants of a track; optionally resolves direct links from the XML documents.
    pub async fn tracks_download_info(&self, track_id: &str, get_direct_links: bool) -> Result<Vec<DownloadInfo>> {
        let url = self.url(&format!("/tracks/{track_id}/download-info"));
        let mut infos: Vec<DownloadInfo> = from_value(self.http.get(&url, &[]).await?)?;
        if get_direct_links {
            for info in infos.iter_mut() {
                let xml_url = info
                    .download_info_url
                    .clone()
                    .ok_or_else(|| Error::InvalidResponse("download_info_url is missing".into()))?;
                let xml = self.http.retrieve(&xml_url, &[]).await?;
                let link = DownloadInfo::build_direct_link(&xml)
                    .ok_or_else(|| Error::InvalidResponse("bad download-info xml".into()))?;
                info.direct_link = Some(link);
            }
        }
        Ok(infos)
    }

    /// File info with signed request (`GET /get-file-info`), supports lossless.
    pub async fn tracks_file_info(
        &self,
        track_id: &str,
        quality: &str,
        codecs: Option<&[&str]>,
        transport: &str,
    ) -> Result<Option<FileInfo>> {
        let url = self.url("/get-file-info");
        let codecs: &[&str] = codecs.unwrap_or(&FILE_INFO_CODECS);
        let sign = get_file_info_sign(track_id, quality, codecs, transport, DESKTOP_SIGN_KEY);
        let query = [
            ("ts", sign.timestamp.to_string()),
            ("trackId", track_id.to_owned()),
            ("quality", quality.to_owned()),
            ("codecs", codecs.join(",")),
            ("transports", transport.to_owned()),
            ("sign", sign.value),
        ];
        let mut headers = HeaderMap::new();
        headers.insert("X-Yandex-Music-Client", HeaderValue::from_static(DESKTOP_CLIENT));
        let rb = self.http.builder(Method::GET, &url).query(&query).headers(headers);
        from_value_opt(self.http.send(rb).await?)
    }

    /// Track supplement: lyrics and videos (`GET /tracks/{id}/supplement`).
    pub async fn track_supplement(&self, track_id: &str) -> Result<Option<Supplement>> {
        let url = self.url(&format!("/tracks/{track_id}/supplement"));
        from_value_opt(self.http.get(&url, &[]).await?)
    }

    /// Track lyrics, signed request (`GET /tracks/{id}/lyrics`); `format` is `TEXT` or `LRC`.
    pub async fn tracks_lyrics(&self, track_id: &str, format: &str) -> Result<Option<TrackLyrics>> {
        let url = self.url(&format!("/tracks/{track_id}/lyrics"));
        let sign = get_sign_request_default(track_id);
        let query = [
            ("format", format.to_owned()),
            ("timeStamp", sign.timestamp.to_string()),
            ("sign", sign.value),
        ];
        from_value_opt(self.http.get(&url, &query).await?)
    }

    /// Similar tracks (`GET /tracks/{id}/similar`).
    pub async fn tracks_similar(&self, track_id: &str) -> Result<Option<SimilarTracks>> {
        let url = self.url(&format!("/tracks/{track_id}/similar"));
        from_value_opt(self.http.get(&url, &[]).await?)
    }

    /// Report a playback (`POST /play-audio`); `uid` defaults to the logged-in account.
    #[allow(clippy::too_many_arguments)]
    pub async fn play_audio(
        &self,
        track_id: &str,
        from: &str,
        album_id: &str,
        playlist_id: Option<&str>,
        from_cache: bool,
        play_id: Option<&str>,
        uid: Option<i64>,
        timestamp: Option<&str>,
        track_length_seconds: i64,
        total_played_seconds: f64,
        end_position_seconds: f64,
        client_now: Option<&str>,
    ) -> Result<bool> {
        let url = self.url("/play-audio");
        let uid = uid.or_else(|| self.account_uid());
        let non_empty = |v: Option<&str>| v.filter(|s| !s.is_empty()).map(str::to_owned).unwrap_or_else(utc_now_iso);
        let mut form: Vec<(&str, String)> = vec![
            ("track-id", track_id.to_owned()),
            ("from-cache", if from_cache { "True" } else { "False" }.to_owned()),
            ("from", from.to_owned()),
            ("play-id", play_id.unwrap_or("").to_owned()),
            ("timestamp", non_empty(timestamp)),
            ("track-length-seconds", track_length_seconds.to_string()),
            ("total-played-seconds", total_played_seconds.to_string()),
            ("end-position-seconds", end_position_seconds.to_string()),
            ("album-id", album_id.to_owned()),
            ("client-now", non_empty(client_now)),
        ];
        if let Some(uid) = uid {
            form.push(("uid", uid.to_string()));
        }
        if let Some(p) = playlist_id {
            form.push(("playlist-id", p.to_owned()));
        }
        Ok(is_ok(&self.http.post(&url, &form).await?))
    }

    /// Shots to play between tracks (`GET /after-track`).
    pub async fn after_track(
        &self,
        next_track_id: &str,
        context_item: &str,
        prev_track_id: Option<&str>,
        context: &str,
        types: &str,
        from: &str,
    ) -> Result<Option<ShotEvent>> {
        let url = self.url("/after-track");
        let mut query: Vec<(&str, String)> = vec![("from", from.to_owned())];
        if let Some(p) = prev_track_id {
            query.push(("prevTrackId", p.to_owned()));
        }
        query.push(("nextTrackId", next_track_id.to_owned()));
        query.push(("context", context.to_owned()));
        query.push(("contextItem", context_item.to_owned()));
        query.push(("types", types.to_owned()));
        match self.http.get(&url, &query).await? {
            Value::Object(mut m) => from_value_opt(m.remove("shotEvent").unwrap_or(Value::Null)),
            _ => Ok(None),
        }
    }

    /// Track trailer (`GET /tracks/{id}/trailer`).
    pub async fn tracks_trailer(&self, track_id: &str) -> Result<Option<TrackTrailer>> {
        let url = self.url(&format!("/tracks/{track_id}/trailer"));
        from_value_opt(self.http.get(&url, &[]).await?)
    }

    /// Full track info (`GET /tracks/{id}/full-info`).
    pub async fn tracks_full_info(&self, track_id: &str) -> Result<Option<TrackFullInfo>> {
        let url = self.url(&format!("/tracks/{track_id}/full-info"));
        from_value_opt(self.http.get(&url, &[]).await?)
    }

    /// Resolve a playable stream, preferring the non-encrypted `raw` transport, then `encraw`,
    /// then the legacy MP3 download-info. `codecs` narrows what the server may answer with
    /// (`None` = [`FILE_INFO_CODECS`]).
    pub async fn direct_link(&self, track_id: &str, prefer: Quality, codecs: Option<&[&str]>) -> Result<StreamInfo> {
        let mut last_err: Option<Error> = None;
        for transport in ["raw", "encraw"] {
            let info = match self.tracks_file_info(track_id, prefer.as_str(), codecs, transport).await {
                Ok(f) => f.and_then(|f| f.download_info),
                Err(e) => {
                    last_err = Some(e);
                    None
                }
            };
            if let Some(d) = info {
                let encrypted = d.transport.as_deref().unwrap_or(transport) == "encraw";
                let key = d.key.filter(|k| !k.is_empty());
                if encrypted && key.is_none() {
                    continue;
                }
                let url = d.url.filter(|u| !u.is_empty()).or_else(|| d.urls.into_iter().next());
                if let Some(url) = url {
                    return Ok(StreamInfo {
                        url,
                        codec: d.codec.unwrap_or_default(),
                        bitrate: d.bitrate,
                        key: if encrypted { key } else { None },
                        quality: d.quality,
                    });
                }
            }
        }
        let infos = match self.tracks_download_info(track_id, false).await {
            Ok(i) => i,
            // Offline / flaky link: report the transport error, not "no download info".
            Err(e) => return Err(match last_err {
                Some(first @ (Error::Network(_) | Error::TimedOut)) => first,
                _ => e,
            }),
        };
        let candidates = infos.into_iter().filter(|i| i.preview != Some(true));
        let best = match prefer {
            Quality::Normal => candidates.min_by_key(|i| i.bitrate_in_kbps.unwrap_or(i64::MAX)),
            _ => candidates.max_by_key(|i| i.bitrate_in_kbps.unwrap_or(0)),
        }
        .ok_or_else(|| Error::NotFound(format!("no download info for track {track_id}")))?;
        let xml_url = best
            .download_info_url
            .as_deref()
            .ok_or_else(|| Error::InvalidResponse("download_info_url is missing".into()))?;
        let xml = self.http.retrieve(xml_url, &[]).await?;
        let url = DownloadInfo::build_direct_link(&xml)
            .ok_or_else(|| Error::InvalidResponse("bad download-info xml".into()))?;
        Ok(StreamInfo {
            url,
            codec: best.codec.unwrap_or_default(),
            bitrate: best.bitrate_in_kbps,
            key: None,
            quality: None,
        })
    }
}
