//! Port of `yandex_music/_client/rotor_sessions.py`: radio sessions (seeds like
//! `user:onyourwave`, `track:123`) and combined (track + clip) sessions.

use std::time::{SystemTime, UNIX_EPOCH};

use serde::Serialize;
use serde_json::{json, Map, Value};

use super::Client;
use crate::error::Result;
use crate::http::{from_value_opt, is_ok};
use crate::models::rotor::{
    CombinedSession, CombinedSessionLanding, CombinedSessionQueueItem, RotorSession, RotorSessionTracks,
    SessionEvent, SessionFeedback, SessionFeedbacks,
};

/// Optional parameters shared by `rotor_session_new` and `rotor_session_clone`.
#[derive(Debug, Clone, Default)]
pub struct SessionParams {
    /// Already played tracks (`id` or `id:album_id`).
    pub queue: Option<Vec<String>>,
    /// Track to start the session from.
    pub track_to_start_from: Option<String>,
    pub include_tracks_in_response: Option<bool>,
    pub include_wave_model: Option<bool>,
    pub interactive: Option<bool>,
    pub incognito: Option<bool>,
    pub child: Option<bool>,
    pub allow_explicit: Option<bool>,
}

impl SessionParams {
    /// Port of `_session_body` (None values are dropped).
    fn body(&self) -> Map<String, Value> {
        let mut m = Map::new();
        let mut put = |k: &str, v: Option<Value>| {
            if let Some(v) = v {
                m.insert(k.to_owned(), v);
            }
        };
        put("queue", self.queue.as_ref().map(|q| json!(q)));
        put("trackToStartFrom", self.track_to_start_from.as_ref().map(|t| json!(t)));
        put("includeTracksInResponse", self.include_tracks_in_response.map(Value::from));
        put("includeWaveModel", self.include_wave_model.map(Value::from));
        put("interactive", self.interactive.map(Value::from));
        put("incognito", self.incognito.map(Value::from));
        put("child", self.child.map(Value::from));
        put("allowExplicit", self.allow_explicit.map(Value::from));
        m
    }
}

/// Radio session feedback event.
#[derive(Debug, Clone, PartialEq)]
pub enum WaveFeedback {
    RadioStarted,
    TrackStarted { track_id: String },
    TrackFinished { track_id: String, played_seconds: f64 },
    Skip { track_id: String, played_seconds: f64 },
    Like { track_id: String },
    Dislike { track_id: String },
}

impl WaveFeedback {
    /// Build the API event with the given timestamp (`None`, `""` or `0` mean "now").
    pub fn to_event(&self, timestamp: Option<Value>) -> SessionEvent {
        let (kind, track_id, secs) = match self {
            Self::RadioStarted => ("radioStarted", None, None),
            Self::TrackStarted { track_id } => ("trackStarted", Some(track_id), None),
            Self::TrackFinished { track_id, played_seconds } => ("trackFinished", Some(track_id), Some(*played_seconds)),
            Self::Skip { track_id, played_seconds } => ("skip", Some(track_id), Some(*played_seconds)),
            Self::Like { track_id } => ("like", Some(track_id), None),
            Self::Dislike { track_id } => ("dislike", Some(track_id), None),
        };
        SessionEvent {
            r#type: Some(kind.to_owned()),
            timestamp: Some(timestamp_or_now(timestamp)),
            track_id: track_id.cloned(),
            total_played_seconds: secs,
            playable: None,
        }
    }
}

/// Port of `_timestamp_or_now`.
fn timestamp_or_now(ts: Option<Value>) -> Value {
    match ts {
        None | Some(Value::Null) => Value::String(utc_now_iso()),
        Some(Value::String(s)) if s.is_empty() => Value::String(utc_now_iso()),
        Some(Value::Number(n)) if n.as_f64() == Some(0.0) => Value::String(utc_now_iso()),
        Some(v) => v,
    }
}

/// Current UTC time as `2024-01-01T12:00:00.000Z`.
fn utc_now_iso() -> String {
    let d = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default();
    let (secs, ms) = (d.as_secs() as i64, d.subsec_millis());
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

/// Serialize a model for a request, dropping `null` fields (`to_dict(for_request=True)`).
fn to_request<T: Serialize>(v: &T) -> Value {
    fn strip(v: Value) -> Value {
        match v {
            Value::Object(m) => Value::Object(m.into_iter().filter(|(_, v)| !v.is_null()).map(|(k, v)| (k, strip(v))).collect()),
            Value::Array(a) => Value::Array(a.into_iter().map(strip).collect()),
            other => other,
        }
    }
    strip(serde_json::to_value(v).unwrap_or(Value::Null))
}

/// Python `is_dict(result)`; also accepts the literal `"ok"`.
fn ok_or_dict(v: &Value) -> bool {
    v.is_object() || is_ok(v)
}

impl Client {
    /// POST `/rotor/session/new`: create a radio session from seeds (`user:onyourwave`, `track:123`).
    pub async fn rotor_session_new<S: AsRef<str>>(&self, seeds: &[S], params: &SessionParams) -> Result<Option<RotorSession>> {
        let mut body = params.body();
        body.insert("seeds".into(), json!(seeds.iter().map(|s| s.as_ref()).collect::<Vec<_>>()));
        let v = self.http.post_json(&self.url("/rotor/session/new"), &[], &Value::Object(body)).await?;
        from_value_opt(v)
    }

    /// POST `/rotor/session/{id}/clone`: clone an existing radio session.
    pub async fn rotor_session_clone(&self, radio_session_id: &str, params: &SessionParams) -> Result<Option<RotorSession>> {
        let url = self.url(&format!("/rotor/session/{radio_session_id}/clone"));
        let v = self.http.post_json(&url, &[], &Value::Object(params.body())).await?;
        from_value_opt(v)
    }

    /// POST `/rotor/session/{id}/tracks`: next batch of tracks, optionally with feedbacks.
    pub async fn rotor_session_tracks<S: AsRef<str>>(
        &self,
        radio_session_id: &str,
        queue: Option<&[S]>,
        feedbacks: Option<&[SessionFeedback]>,
    ) -> Result<Option<RotorSessionTracks>> {
        let url = self.url(&format!("/rotor/session/{radio_session_id}/tracks"));
        let q: Vec<&str> = queue.unwrap_or(&[]).iter().map(|s| s.as_ref()).collect();
        let mut body = json!({ "queue": q });
        if let Some(f) = feedbacks.filter(|f| !f.is_empty()) {
            body["feedbacks"] = Value::Array(f.iter().map(to_request).collect());
        }
        from_value_opt(self.http.post_json(&url, &[], &body).await?)
    }

    /// POST `/rotor/session/{id}/feedback` with a raw `SessionEvent`.
    pub async fn rotor_session_feedback_event(
        &self,
        radio_session_id: &str,
        event: &SessionEvent,
        batch_id: Option<&str>,
        from: Option<&str>,
    ) -> Result<bool> {
        let url = self.url(&format!("/rotor/session/{radio_session_id}/feedback"));
        let fb = SessionFeedback {
            event: Some(event.clone()),
            batch_id: batch_id.map(str::to_owned),
            from_: from.map(str::to_owned),
        };
        Ok(ok_or_dict(&self.http.post_json(&url, &[], &to_request(&fb)).await?))
    }

    /// Send a `WaveFeedback` event stamped with the current time.
    pub async fn rotor_session_feedback(
        &self,
        radio_session_id: &str,
        feedback: &WaveFeedback,
        batch_id: Option<&str>,
        from: Option<&str>,
    ) -> Result<bool> {
        self.rotor_session_feedback_event(radio_session_id, &feedback.to_event(None), batch_id, from).await
    }

    /// Feedback `radioStarted`; `timestamp` of `None`/`""`/`0` means now.
    pub async fn rotor_session_feedback_radio_started(
        &self,
        radio_session_id: &str,
        batch_id: Option<&str>,
        from: Option<&str>,
        timestamp: Option<Value>,
    ) -> Result<bool> {
        let ev = WaveFeedback::RadioStarted.to_event(timestamp);
        self.rotor_session_feedback_event(radio_session_id, &ev, batch_id, from).await
    }

    /// Feedback `trackStarted`; `timestamp` of `None`/`""`/`0` means now.
    pub async fn rotor_session_feedback_track_started(
        &self,
        radio_session_id: &str,
        track_id: &str,
        batch_id: Option<&str>,
        timestamp: Option<Value>,
    ) -> Result<bool> {
        let ev = WaveFeedback::TrackStarted { track_id: track_id.to_owned() }.to_event(timestamp);
        self.rotor_session_feedback_event(radio_session_id, &ev, batch_id, None).await
    }

    /// Feedback `trackFinished`; `timestamp` of `None`/`""`/`0` means now.
    pub async fn rotor_session_feedback_track_finished(
        &self,
        radio_session_id: &str,
        track_id: &str,
        total_played_seconds: f64,
        batch_id: Option<&str>,
        timestamp: Option<Value>,
    ) -> Result<bool> {
        let ev = WaveFeedback::TrackFinished { track_id: track_id.to_owned(), played_seconds: total_played_seconds }.to_event(timestamp);
        self.rotor_session_feedback_event(radio_session_id, &ev, batch_id, None).await
    }

    /// Feedback `skip`; `timestamp` of `None`/`""`/`0` means now.
    pub async fn rotor_session_feedback_skip(
        &self,
        radio_session_id: &str,
        track_id: &str,
        total_played_seconds: f64,
        batch_id: Option<&str>,
        timestamp: Option<Value>,
    ) -> Result<bool> {
        let ev = WaveFeedback::Skip { track_id: track_id.to_owned(), played_seconds: total_played_seconds }.to_event(timestamp);
        self.rotor_session_feedback_event(radio_session_id, &ev, batch_id, None).await
    }

    /// POST `/rotor/session/{id}/feedbacks`: several feedbacks at once.
    pub async fn rotor_session_feedbacks(&self, radio_session_id: &str, feedbacks: &[SessionFeedback]) -> Result<bool> {
        let url = self.url(&format!("/rotor/session/{radio_session_id}/feedbacks"));
        let body = json!({ "feedbacks": feedbacks.iter().map(to_request).collect::<Vec<_>>() });
        Ok(ok_or_dict(&self.http.post_json(&url, &[], &body).await?))
    }

    /// POST `/rotor/sessions/feedbacks`: feedbacks for several sessions.
    pub async fn rotor_sessions_feedbacks(&self, sessions: &[SessionFeedbacks]) -> Result<bool> {
        let url = self.url("/rotor/sessions/feedbacks");
        let body = json!({ "sessions": sessions.iter().map(to_request).collect::<Vec<_>>() });
        Ok(ok_or_dict(&self.http.post_json(&url, &[], &body).await?))
    }

    /// POST `/rotor/combined/session/new`: combined session (`CLIP` and `TRACK` items).
    pub async fn rotor_combined_session_new<S: AsRef<str>>(
        &self,
        supported_types: Option<&[S]>,
        queue: Option<&[CombinedSessionQueueItem]>,
        child: Option<bool>,
        allow_explicit: Option<bool>,
    ) -> Result<Option<CombinedSession>> {
        let mut body = Map::new();
        if let Some(t) = supported_types {
            body.insert("supportedTypes".into(), json!(t.iter().map(|s| s.as_ref()).collect::<Vec<_>>()));
        }
        if let Some(q) = queue {
            body.insert("queue".into(), Value::Array(q.iter().map(to_request).collect()));
        }
        if let Some(c) = child {
            body.insert("child".into(), c.into());
        }
        if let Some(a) = allow_explicit {
            body.insert("allowExplicit".into(), a.into());
        }
        let v = self.http.post_json(&self.url("/rotor/combined/session/new"), &[], &Value::Object(body)).await?;
        from_value_opt(v)
    }

    /// POST `/rotor/combined/session/{id}/next`: next items of a combined session.
    pub async fn rotor_combined_session_next(
        &self,
        session_id: &str,
        queue: Option<&[CombinedSessionQueueItem]>,
    ) -> Result<Option<CombinedSession>> {
        let url = self.url(&format!("/rotor/combined/session/{session_id}/next"));
        let items: Vec<Value> = queue.unwrap_or(&[]).iter().map(to_request).collect();
        from_value_opt(self.http.post_json(&url, &[], &json!({ "queue": items })).await?)
    }

    /// POST `/rotor/combined/session/landing`: combined session landing.
    pub async fn rotor_combined_session_landing<S: AsRef<str>>(
        &self,
        supported_types: Option<&[S]>,
        child: Option<bool>,
        allow_explicit: Option<bool>,
    ) -> Result<Option<CombinedSessionLanding>> {
        let mut body = Map::new();
        if let Some(t) = supported_types {
            body.insert("supportedTypes".into(), json!(t.iter().map(|s| s.as_ref()).collect::<Vec<_>>()));
        }
        if let Some(c) = child {
            body.insert("child".into(), c.into());
        }
        if let Some(a) = allow_explicit {
            body.insert("allowExplicit".into(), a.into());
        }
        let v = self.http.post_json(&self.url("/rotor/combined/session/landing"), &[], &Value::Object(body)).await?;
        from_value_opt(v)
    }
}
