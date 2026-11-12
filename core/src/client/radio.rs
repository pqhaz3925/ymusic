//! Port of `yandex_music/_client/radio.py`: legacy rotor (radio / Wave) API.

use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::{json, Map, Value};

use super::Client;
use crate::error::Result;
use crate::http::{from_value, from_value_opt, is_ok};
use crate::models::account::Status;
use crate::models::rotor::{Dashboard, GenerativeStream, GenerativeStreamFeedback, StationResult, StationTracksResult};

/// Port of `utc_now_iso`: current UTC time as `YYYY-MM-DDTHH:MM:SS.mmmZ`.
pub fn utc_now_iso() -> String {
    let ms = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0);
    let secs = ms.div_euclid(1000);
    let millis = ms.rem_euclid(1000);
    let days = secs.div_euclid(86_400);
    let sod = secs.rem_euclid(86_400);
    // Civil-from-days (Howard Hinnant).
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + if m <= 2 { 1 } else { 0 };
    format!(
        "{y:04}-{m:02}-{d:02}T{:02}:{:02}:{:02}.{millis:03}Z",
        sod / 3600,
        (sod % 3600) / 60,
        sod % 60
    )
}

impl Client {
    /// Rotor account status with extra fields (e.g. `skips_per_hour`).
    pub async fn rotor_account_status(&self) -> Result<Option<Status>> {
        let v = self.http.get(&self.url("/rotor/account/status"), &[]).await?;
        from_value_opt(v)
    }

    /// Recommended stations of the current user.
    pub async fn rotor_stations_dashboard(&self) -> Result<Option<Dashboard>> {
        let v = self.http.get(&self.url("/rotor/stations/dashboard"), &[]).await?;
        from_value_opt(v)
    }

    /// All stations with user settings; `language` defaults to the client language.
    pub async fn rotor_stations_list(&self, language: Option<&str>) -> Result<Vec<StationResult>> {
        let lang = match language {
            Some(l) if !l.is_empty() => l.to_owned(),
            _ => self.language.clone(),
        };
        let v = self.http.get(&self.url("/rotor/stations/list"), &[("language", lang)]).await?;
        from_value(v)
    }

    /// Send radio feedback (`radioStarted`, `trackStarted`, `trackFinished`, `skip`); `timestamp` is ISO 8601, default now.
    #[allow(clippy::too_many_arguments)]
    pub async fn rotor_station_feedback(
        &self,
        station: &str,
        type_: &str,
        timestamp: Option<&str>,
        from_: Option<&str>,
        batch_id: Option<&str>,
        total_played_seconds: Option<f64>,
        track_id: Option<&str>,
        stream_id: Option<&str>,
    ) -> Result<bool> {
        let ts = timestamp.map(str::to_owned).unwrap_or_else(utc_now_iso);
        let url = self.url(&format!("/rotor/station/{station}/feedback"));

        let mut params: Vec<(&str, String)> = Vec::new();
        let mut data = Map::new();
        data.insert("type".into(), json!(type_));
        data.insert("timestamp".into(), json!(ts));

        if let Some(b) = batch_id.filter(|s| !s.is_empty()) {
            params.push(("batch-id", b.to_owned()));
        }
        if let Some(s) = stream_id.filter(|s| !s.is_empty()) {
            params.push(("streamId", s.to_owned()));
        }
        if let Some(t) = track_id.filter(|s| !s.is_empty() && *s != "0") {
            data.insert("trackId".into(), json!(t));
        }
        if let Some(f) = from_.filter(|s| !s.is_empty()) {
            data.insert("from".into(), json!(f));
        }
        if let Some(p) = total_played_seconds.filter(|p| *p != 0.0) {
            data.insert("totalPlayedSeconds".into(), json!(p));
        }

        let v = self.http.post_json(&url, &params, &Value::Object(data)).await?;
        Ok(is_ok(&v))
    }

    /// Feedback: radio started.
    pub async fn rotor_station_feedback_radio_started(
        &self,
        station: &str,
        from_: &str,
        batch_id: Option<&str>,
        timestamp: Option<&str>,
    ) -> Result<bool> {
        self.rotor_station_feedback(station, "radioStarted", timestamp, Some(from_), batch_id, None, None, None)
            .await
    }

    /// Feedback: track started.
    pub async fn rotor_station_feedback_track_started(
        &self,
        station: &str,
        track_id: &str,
        batch_id: Option<&str>,
        timestamp: Option<&str>,
    ) -> Result<bool> {
        self.rotor_station_feedback(station, "trackStarted", timestamp, None, batch_id, None, Some(track_id), None)
            .await
    }

    /// Feedback: track finished.
    pub async fn rotor_station_feedback_track_finished(
        &self,
        station: &str,
        track_id: &str,
        total_played_seconds: f64,
        batch_id: Option<&str>,
        timestamp: Option<&str>,
    ) -> Result<bool> {
        self.rotor_station_feedback(
            station,
            "trackFinished",
            timestamp,
            None,
            batch_id,
            Some(total_played_seconds),
            Some(track_id),
            None,
        )
        .await
    }

    /// Feedback: track skipped.
    pub async fn rotor_station_feedback_skip(
        &self,
        station: &str,
        track_id: &str,
        total_played_seconds: f64,
        batch_id: Option<&str>,
        timestamp: Option<&str>,
    ) -> Result<bool> {
        self.rotor_station_feedback(
            station,
            "skip",
            timestamp,
            None,
            batch_id,
            Some(total_played_seconds),
            Some(track_id),
            None,
        )
        .await
    }

    /// Station info and user settings for it.
    pub async fn rotor_station_info(&self, station: &str) -> Result<Vec<StationResult>> {
        let v = self.http.get(&self.url(&format!("/rotor/station/{station}/info")), &[]).await?;
        from_value(v)
    }

    /// Generative station info and its stream (`generative:focus`, ...).
    pub async fn rotor_station_stream(&self, station: &str) -> Result<Option<GenerativeStream>> {
        let v = self.http.get(&self.url(&format!("/rotor/station/{station}/stream")), &[]).await?;
        from_value_opt(v)
    }

    /// Feedback for a generative station (`streamStarted`, `streamPlay`, `streamPause`).
    pub async fn rotor_station_stream_feedback(
        &self,
        station: &str,
        type_: &str,
        stream_id: Option<&str>,
        timestamp: Option<&str>,
    ) -> Result<Option<GenerativeStreamFeedback>> {
        let url = self.url(&format!("/rotor/station/{station}/feedback"));
        let mut params: Vec<(&str, String)> = Vec::new();
        if let Some(s) = stream_id.filter(|s| !s.is_empty()) {
            params.push(("streamId", s.to_owned()));
        }
        let ts = timestamp.map(str::to_owned).unwrap_or_else(utc_now_iso);
        let body = json!({ "type": type_, "timestamp": ts });
        let v = self.http.post_json(&url, &params, &body).await?;
        from_value_opt(v)
    }

    /// Change station settings (Python defaults: `language = "not-russian"`, `type_ = "rotor"`).
    pub async fn rotor_station_settings2(
        &self,
        station: &str,
        mood_energy: &str,
        diversity: &str,
        language: &str,
        type_: &str,
    ) -> Result<bool> {
        let url = self.url(&format!("/rotor/station/{station}/settings3"));
        let mut data = Map::new();
        data.insert("moodEnergy".into(), json!(mood_energy));
        data.insert("diversity".into(), json!(diversity));
        data.insert("type".into(), json!(type_));
        if !language.is_empty() {
            data.insert("language".into(), json!(language));
        }
        let v = self.http.post_json(&url, &[], &Value::Object(data)).await?;
        Ok(is_ok(&v))
    }

    /// Track chain of a station; a non-empty `queue` replaces `settings2` (as in Python).
    pub async fn rotor_station_tracks(
        &self,
        station: &str,
        settings2: bool,
        queue: Option<&str>,
    ) -> Result<Option<StationTracksResult>> {
        let url = self.url(&format!("/rotor/station/{station}/tracks"));
        let mut params: Vec<(&str, String)> = Vec::new();
        if settings2 {
            params = vec![("settings2", "True".to_owned())];
        }
        if let Some(q) = queue.filter(|q| !q.is_empty()) {
            params = vec![("queue", q.to_owned())];
        }
        let v = self.http.get(&url, &params).await?;
        from_value_opt(v)
    }
}
