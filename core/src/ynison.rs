//! Ynison (remote control / playback sync) client, port of `yandex_music/ynison/`.
//!
//! JSON shapes follow betterproto's `to_dict()` output used by the Python library: camelCase
//! keys, default values omitted, enums by name, int64 as decimal strings. Incoming frames are
//! parsed leniently (snake_case or camelCase keys, numbers or strings for int64, enum names
//! or numbers).

use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Deserializer, Serialize, Serializer};
use serde_json::Value;

use crate::error::{Error, Result as YResult};

// ---------------------------------------------------------------- serde helpers

fn is_default<T: Default + PartialEq>(v: &T) -> bool {
    *v == T::default()
}

/// int64 goes out as a decimal string (proto3 JSON).
fn ser_i64<S: Serializer>(v: &i64, s: S) -> Result<S::Ok, S::Error> {
    s.serialize_str(&v.to_string())
}

/// int64 comes in as a number or a numeric string.
fn de_i64<'de, D: Deserializer<'de>>(d: D) -> Result<i64, D::Error> {
    crate::models::de::opt_i64(d).map(|v| v.unwrap_or_default())
}

macro_rules! proto_enum {
    ($(#[$m:meta])* $name:ident { $first:ident = $fnum:expr, $($variant:ident = $num:expr),* $(,)? }) => {
        $(#[$m])*
        #[allow(non_camel_case_types)]
        #[derive(Debug, Clone, Copy, PartialEq, Eq)]
        pub enum $name { $first, $($variant),* }

        impl Default for $name {
            fn default() -> Self { $name::$first }
        }

        impl $name {
            /// Proto name of the variant, e.g. `"WEB"`.
            pub fn name(&self) -> &'static str {
                match self { $name::$first => stringify!($first), $($name::$variant => stringify!($variant)),* }
            }
            /// Proto numeric value.
            pub fn number(&self) -> i64 {
                match self { $name::$first => $fnum, $($name::$variant => $num),* }
            }
            pub fn from_number(n: i64) -> Option<Self> {
                if n == $fnum { return Some($name::$first); }
                $(if n == $num { return Some($name::$variant); })*
                None
            }
            pub fn from_name(s: &str) -> Option<Self> {
                if s == stringify!($first) { return Some($name::$first); }
                $(if s == stringify!($variant) { return Some($name::$variant); })*
                None
            }
        }

        impl Serialize for $name {
            fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
                s.serialize_str(self.name())
            }
        }

        impl<'de> Deserialize<'de> for $name {
            fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
                Ok(match Value::deserialize(d)? {
                    Value::String(s) => Self::from_name(&s).unwrap_or_default(),
                    Value::Number(n) => n.as_i64().and_then(Self::from_number).unwrap_or_default(),
                    _ => Self::default(),
                })
            }
        }
    };
}

macro_rules! proto_msg {
    ($(#[$m:meta])* $name:ident { $( $(#[$fm:meta])* $f:ident : $t:ty ),* $(,)? }) => {
        $(#[$m])*
        #[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
        #[serde(rename_all = "camelCase", default)]
        pub struct $name {
            $( #[serde(skip_serializing_if = "is_default")] $(#[$fm])* pub $f: $t, )*
        }
    };
}

// ---------------------------------------------------------------- enums

proto_enum!(
    /// Device kind (`DeviceType`).
    DeviceType { UNSPECIFIED = 0, WEB = 1, ANDROID = 2, IOS = 3, SMART_SPEAKER = 4, WEB_TV = 5,
        ANDROID_TV = 6, APPLE_TV = 7, ANDROID_WEAR = 8, WEB_DESKTOP = 9 }
);
proto_enum!(
    /// Kind of a queue item (`PlayablePlayableType`).
    PlayablePlayableType { UNSPECIFIED = 0, TRACK = 1, LOCAL_TRACK = 2, INFINITE = 3, VIDEO_CLIP = 4 }
);
proto_enum!(
    /// Entity the queue was built from (`PlayerQueueEntityType`, legacy).
    PlayerQueueEntityType { UNSPECIFIED = 0, ARTIST = 1, PLAYLIST = 2, ALBUM = 3, RADIO = 4, VARIOUS = 5,
        GENERATIVE = 6, FM_RADIO = 7, VIDEO_WAVE = 8, LOCAL_TRACKS = 9 }
);
proto_enum!(
    /// Playback context of the queue (`PlayerQueueEntityContext`).
    PlayerQueueEntityContext { BASED_ON_ENTITY_BY_DEFAULT = 0, USER_TRACKS = 1, DOWNLOADED_TRACKS = 2, SEARCH = 3,
        MUSIC_HISTORY = 4, MUSIC_HISTORY_SEARCH = 5, ARTIST_MY_COLLECTION = 6, ARTIST_FAMILIAR_FROM_WAVE = 7 }
);
proto_enum!(
    /// Repeat mode (`PlayerStateOptionsRepeatMode`).
    PlayerStateOptionsRepeatMode { UNSPECIFIED = 0, NONE = 1, ONE = 2, ALL = 3 }
);
proto_enum!(
    /// How a sender tries to take over activity (`PutYnisonStateRequestActivityInterceptionType`).
    PutYnisonStateRequestActivityInterceptionType { DO_NOT_INTERCEPT_BY_DEFAULT = 0,
        INTERCEPT_IF_NO_ONE_ACTIVE = 1, INTERCEPT_EAGER = 2 }
);

// ---------------------------------------------------------------- messages

proto_msg!(
    /// Change version stamp (`UpdateVersion`).
    UpdateVersion {
        device_id: String,
        #[serde(serialize_with = "ser_i64", deserialize_with = "de_i64")]
        version: i64,
        #[serde(serialize_with = "ser_i64", deserialize_with = "de_i64")]
        timestamp_ms: i64,
    }
);
proto_msg!(
    /// Playback status (`PlayingStatus`).
    PlayingStatus {
        #[serde(serialize_with = "ser_i64", deserialize_with = "de_i64")]
        progress_ms: i64,
        #[serde(serialize_with = "ser_i64", deserialize_with = "de_i64")]
        duration_ms: i64,
        paused: bool,
        playback_speed: f64,
        version: Option<UpdateVersion>,
    }
);
proto_msg!(
    /// Player options (`PlayerStateOptions`).
    PlayerStateOptions { repeat_mode: PlayerStateOptionsRepeatMode }
);
proto_msg!(
    /// Shuffled order of queue indices (`Shuffle`).
    Shuffle { playable_indices: Vec<i64> }
);
proto_msg!(
    /// Extra info for a track queue item (`TrackInfo`).
    TrackInfo { track_source_key: i64, batch_id_optional: Option<String> }
);
proto_msg!(
    /// A queue item (`Playable`).
    Playable {
        playable_id: String,
        album_id_optional: Option<String>,
        playable_type: PlayablePlayableType,
        #[serde(rename = "from")]
        from_: String,
        title: String,
        cover_url_optional: Option<String>,
        video_clip_info: Option<Value>,
        track_info: Option<TrackInfo>,
        navigation_id_optional: Option<String>,
        playback_action_id_optional: Option<String>,
    }
);
proto_msg!(
    /// Playback queue (`PlayerQueue`). The nested `queue` oneof is kept as raw JSON.
    PlayerQueue {
        entity_id: String,
        entity_type: PlayerQueueEntityType,
        queue: Option<Value>,
        current_playable_index: i64,
        playable_list: Vec<Playable>,
        options: Option<PlayerStateOptions>,
        version: Option<UpdateVersion>,
        shuffle_optional: Option<Shuffle>,
        entity_context: PlayerQueueEntityContext,
        from_optional: Option<String>,
        initial_entity_optional: Option<Value>,
        adding_options_optional: Option<Value>,
        navigation_id_optional: Option<String>,
        filter_optional: Option<String>,
        playback_action_id_optional: Option<String>,
    }
);
proto_msg!(
    /// Player state (`PlayerState`).
    PlayerState {
        status: Option<PlayingStatus>,
        player_queue: Option<PlayerQueue>,
        player_queue_inject_optional: Option<Value>,
    }
);
proto_msg!(
    /// Device description (`DeviceInfo`).
    DeviceInfo {
        device_id: String,
        title: String,
        r#type: DeviceType,
        app_name: String,
        app_version: String,
    }
);
proto_msg!(
    /// What a device can do (`DeviceCapabilities`).
    DeviceCapabilities { can_be_player: bool, can_be_remote_controller: bool, volume_granularity: i64 }
);
proto_msg!(
    /// Device volume (`DeviceVolume`).
    DeviceVolume { volume: f64, version: Option<UpdateVersion> }
);
proto_msg!(
    /// Connection session (`Session`).
    Session {
        #[serde(serialize_with = "ser_i64", deserialize_with = "de_i64")]
        id: i64,
    }
);
proto_msg!(
    /// A device in the session (`Device`).
    Device {
        info: Option<DeviceInfo>,
        volume: f64,
        capabilities: Option<DeviceCapabilities>,
        session: Option<Session>,
        is_offline: bool,
        volume_info: Option<DeviceVolume>,
    }
);
proto_msg!(
    /// Device data sent by the device itself (`UpdateDevice`).
    UpdateDevice {
        info: Option<DeviceInfo>,
        volume: f64,
        capabilities: Option<DeviceCapabilities>,
        volume_info: Option<DeviceVolume>,
    }
);
proto_msg!(
    /// `UpdateFullState` request parameter.
    UpdateFullState {
        player_state: Option<PlayerState>,
        is_currently_active: bool,
        device: Option<UpdateDevice>,
    }
);
proto_msg!(
    /// `UpdatePlayingStatus` request parameter.
    UpdatePlayingStatus { playing_status: Option<PlayingStatus> }
);
proto_msg!(
    /// `UpdatePlayerState` request parameter.
    UpdatePlayerState { player_state: Option<PlayerState> }
);
proto_msg!(
    /// `UpdateVolumeInfo` request parameter.
    UpdateVolumeInfo { device_id: String, volume_info: Option<DeviceVolume> }
);
proto_msg!(
    /// `UpdateActiveDevice` request parameter.
    UpdateActiveDevice { device_id_optional: Option<String> }
);
proto_msg!(
    /// Client to server frame (`PutYnisonStateRequest`); exactly one `update_*` is set.
    PutYnisonStateRequest {
        update_full_state: Option<UpdateFullState>,
        update_active_device: Option<UpdateActiveDevice>,
        update_playing_status: Option<UpdatePlayingStatus>,
        update_player_state: Option<UpdatePlayerState>,
        update_volume_info: Option<UpdateVolumeInfo>,
        #[serde(serialize_with = "ser_i64", deserialize_with = "de_i64")]
        player_action_timestamp_ms: i64,
        rid: String,
        activity_interception_type: PutYnisonStateRequestActivityInterceptionType,
    }
);
proto_msg!(
    /// Server to client state frame (`PutYnisonStateResponse`).
    YnisonState {
        player_state: Option<PlayerState>,
        devices: Vec<Device>,
        active_device_id_optional: Option<String>,
        #[serde(serialize_with = "ser_i64", deserialize_with = "de_i64")]
        timestamp_ms: i64,
        rid: String,
    }
);

// ---------------------------------------------------------------- ids, time, state helpers

pub const DEFAULT_DEVICE_TITLE: &str = "ymusic";
pub const DEFAULT_APP_NAME: &str = "yandex-music";

fn now_ms() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0)
}

fn rand_u128() -> u128 {
    uuid::Uuid::new_v4().as_u128()
}

/// 12 hex chars. Random without `seed`, `sha256(seed)[..12]` with it (same as `generate_device_id`).
pub fn generate_device_id(seed: Option<&str>) -> String {
    match seed {
        None => format!("{:012x}", rand_u128() & ((1u128 << 48) - 1)),
        Some(s) => {
            use sha2::{Digest, Sha256};
            Sha256::digest(s.as_bytes()).iter().take(6).map(|b| format!("{b:02x}")).collect()
        }
    }
}

pub fn generate_request_id() -> String {
    uuid::Uuid::new_v4().to_string()
}

fn new_version(device_id: &str) -> UpdateVersion {
    UpdateVersion {
        device_id: device_id.to_owned(),
        version: (rand_u128() % 1_000_000_000_000_000_000) as i64,
        timestamp_ms: now_ms(),
    }
}

/// Current track of the queue (`utils.get_current_playable`).
pub fn current_playable(state: &YnisonState) -> Option<&Playable> {
    let q = state.player_state.as_ref()?.player_queue.as_ref()?;
    usize::try_from(q.current_playable_index).ok().and_then(|i| q.playable_list.get(i))
}

/// The device that currently plays (`utils.get_active_device`).
pub fn active_device(state: &YnisonState) -> Option<&Device> {
    let id = state.active_device_id_optional.as_deref().filter(|s| !s.is_empty())?;
    state.devices.iter().find(|d| d.info.as_ref().is_some_and(|i| i.device_id == id))
}

/// Queue indices in playback order, honouring shuffle (`utils.get_playback_order`).
pub fn playback_order(queue: &PlayerQueue) -> Vec<i64> {
    let total = queue.playable_list.len();
    match &queue.shuffle_optional {
        Some(s) if !s.playable_indices.is_empty() && s.playable_indices.len() == total => s.playable_indices.clone(),
        _ => (0..total as i64).collect(),
    }
}

/// Index of the neighbour of the current track in playback order (`utils.get_neighbour_index`).
pub fn neighbour_index(queue: &PlayerQueue, delta: i64) -> Option<i64> {
    let order = playback_order(queue);
    let pos = order.iter().position(|&i| i == queue.current_playable_index)? as i64;
    usize::try_from(pos + delta).ok().and_then(|p| order.get(p).copied())
}

/// Progress extrapolated to `now_ms` (`utils.get_current_progress_ms`).
pub fn current_progress_ms(status: &PlayingStatus, now: Option<i64>) -> i64 {
    let mut progress = status.progress_ms;
    let ts = status.version.as_ref().map_or(0, |v| v.timestamp_ms);
    if !status.paused && ts > 0 {
        let elapsed = (now.unwrap_or_else(now_ms) - ts).max(0);
        let speed = if status.playback_speed != 0.0 { status.playback_speed } else { 1.0 };
        progress += (elapsed as f64 * speed) as i64;
    }
    if status.duration_ms > 0 {
        progress = progress.min(status.duration_ms);
    }
    progress
}

// ---------------------------------------------------------------- request builders (messages.py)

fn wrap_request(mut r: PutYnisonStateRequest) -> PutYnisonStateRequest {
    r.rid = generate_request_id();
    r.player_action_timestamp_ms = now_ms();
    r.activity_interception_type = PutYnisonStateRequestActivityInterceptionType::DO_NOT_INTERCEPT_BY_DEFAULT;
    r
}

/// First frame after connecting: registers this device as a remote controller.
pub fn build_full_state_request(device_id: &str, title: &str, app_name: &str) -> PutYnisonStateRequest {
    let ver = |ts| Some(UpdateVersion { device_id: device_id.to_owned(), timestamp_ms: ts, ..Default::default() });
    PutYnisonStateRequest {
        update_full_state: Some(UpdateFullState {
            player_state: Some(PlayerState {
                player_queue: Some(PlayerQueue {
                    current_playable_index: -1,
                    options: Some(PlayerStateOptions { repeat_mode: PlayerStateOptionsRepeatMode::NONE }),
                    version: ver(0),
                    entity_type: PlayerQueueEntityType::VARIOUS,
                    entity_context: PlayerQueueEntityContext::BASED_ON_ENTITY_BY_DEFAULT,
                    from_optional: Some(String::new()),
                    ..Default::default()
                }),
                status: Some(PlayingStatus { paused: true, playback_speed: 1.0, version: ver(0), ..Default::default() }),
                ..Default::default()
            }),
            device: Some(UpdateDevice {
                capabilities: Some(DeviceCapabilities {
                    can_be_player: false,
                    can_be_remote_controller: true,
                    volume_granularity: 0,
                }),
                info: Some(DeviceInfo {
                    device_id: device_id.to_owned(),
                    r#type: DeviceType::WEB,
                    title: title.to_owned(),
                    app_name: app_name.to_owned(),
                    ..Default::default()
                }),
                volume_info: Some(DeviceVolume { volume: 0.0, version: None }),
                ..Default::default()
            }),
            is_currently_active: false,
        }),
        rid: generate_request_id(),
        ..Default::default()
    }
}

/// Pause / resume: clones the status with a fresh version and re-based progress.
pub fn build_set_paused_request(device_id: &str, current: &PlayingStatus, paused: bool) -> PutYnisonStateRequest {
    wrap_request(PutYnisonStateRequest {
        update_playing_status: Some(UpdatePlayingStatus {
            playing_status: Some(PlayingStatus {
                progress_ms: current_progress_ms(current, None),
                duration_ms: current.duration_ms,
                paused,
                playback_speed: if current.playback_speed != 0.0 { current.playback_speed } else { 1.0 },
                version: Some(new_version(device_id)),
            }),
        }),
        ..Default::default()
    })
}

/// Move `delta` tracks in playback order (`1` next, `-1` previous). Errors at queue bounds.
pub fn build_change_track_request(device_id: &str, state: &PlayerState, delta: i64) -> YResult<PutYnisonStateRequest> {
    let queue = state.player_queue.as_ref().ok_or_else(|| Error::Ynison("no player queue in state".into()))?;
    let new_index = neighbour_index(queue, delta).ok_or_else(|| {
        Error::Ynison(format!(
            "queue boundary: cannot move {delta:+} from {} in a queue of {}",
            queue.current_playable_index,
            queue.playable_list.len()
        ))
    })?;
    let old = state.status.clone().unwrap_or_default();
    let mut new_queue = queue.clone();
    new_queue.current_playable_index = new_index;
    new_queue.version = Some(new_version(device_id));
    let status = PlayingStatus {
        progress_ms: 0,
        duration_ms: 0,
        paused: old.paused,
        playback_speed: if old.playback_speed != 0.0 { old.playback_speed } else { 1.0 },
        version: Some(new_version(device_id)),
    };
    Ok(wrap_request(PutYnisonStateRequest {
        update_player_state: Some(UpdatePlayerState {
            player_state: Some(PlayerState { player_queue: Some(new_queue), status: Some(status), ..Default::default() }),
        }),
        ..Default::default()
    }))
}

/// Set the volume (clamped to 0..=1) on `target_device_id`.
pub fn build_set_volume_request(device_id: &str, target_device_id: &str, volume: f64) -> PutYnisonStateRequest {
    wrap_request(PutYnisonStateRequest {
        update_volume_info: Some(UpdateVolumeInfo {
            device_id: target_device_id.to_owned(),
            volume_info: Some(DeviceVolume { volume: volume.clamp(0.0, 1.0), version: Some(new_version(device_id)) }),
        }),
        ..Default::default()
    })
}

// ---------------------------------------------------------------- handshake (_base.py)

const BASE_URL: &str = "wss://ynison.music.yandex.ru";
const REDIRECT_SERVICE: &str = "redirector.YnisonRedirectService/GetRedirectToYnison";
const STATE_SERVICE: &str = "ynison_state.YnisonStateService/PutYnisonState";

/// `urllib.parse.quote(s)`: keeps ASCII alphanumerics and `_.-~/`, percent-encodes the rest.
fn py_quote(s: &str) -> String {
    let mut out = String::with_capacity(s.len() * 2);
    for b in s.bytes() {
        if b.is_ascii_alphanumeric() || b"_.-~/".contains(&b) {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

fn json_str(s: &str) -> String {
    serde_json::to_string(s).unwrap_or_else(|_| "\"\"".into())
}

/// Redirect service answer: where to connect and with which ticket.
#[derive(Debug, Clone, Default, PartialEq)]
struct Redirect {
    host: String,
    ticket: String,
    session_id: i64,
    keep_alive_secs: u64,
    keep_alive_timeout_secs: u64,
}

/// `Ynison-*` header JSON, formatted like Python's `json.dumps` (`", "` and `": "` separators,
/// insertion order). The device info is intentionally a JSON string inside JSON.
fn device_info_json(device_id: &str, title: &str, redirect: Option<&Redirect>) -> String {
    let info = format!("{{\"app_name\": {}, \"type\": \"1\"}}", json_str(title));
    let mut pairs = vec![("Ynison-Device-Id", json_str(device_id)), ("Ynison-Device-Info", json_str(&info))];
    if let Some(r) = redirect {
        pairs.push(("Ynison-Redirect-Ticket", json_str(&r.ticket)));
        pairs.push(("Ynison-Session-Id", json_str(&r.session_id.to_string())));
    }
    let body: Vec<String> = pairs.into_iter().map(|(k, v)| format!("{}: {}", json_str(k), v)).collect();
    format!("{{{}}}", body.join(", "))
}

/// `Sec-WebSocket-Protocol` values: `Bearer`, `v2`, url-quoted device info.
fn subprotocols(device_id: &str, title: &str, redirect: Option<&Redirect>) -> Vec<String> {
    vec!["Bearer".into(), "v2".into(), py_quote(&device_info_json(device_id, title, redirect))]
}

/// Internal connection error. `terminal` means reconnecting is pointless.
#[derive(Debug, Clone, Default)]
struct YErr {
    message: String,
    terminal: bool,
    backoff_ms: Vec<u64>,
}

impl YErr {
    fn retry(m: impl Into<String>) -> Self {
        YErr { message: m.into(), ..Default::default() }
    }
    fn fatal(m: impl Into<String>) -> Self {
        YErr { message: m.into(), terminal: true, ..Default::default() }
    }
}

impl From<YErr> for Error {
    fn from(e: YErr) -> Self {
        Error::Ynison(e.message)
    }
}

fn parse_int(v: Option<&Value>) -> Option<i64> {
    match v? {
        Value::Number(n) => n.as_i64(),
        Value::String(s) => s.trim().parse().ok(),
        _ => None,
    }
}

/// Maps the `error` object of a server frame (`parse_server_error` + `is_terminal_error`).
fn parse_server_error(payload: &Value) -> YErr {
    fn truthy(v: Option<&Value>) -> Option<&Value> {
        v.filter(|v| v.as_object().is_some_and(|o| !o.is_empty()))
    }
    let details = truthy(payload.get("details")).or_else(|| truthy(payload.get("extra_headers")));
    let detail = |k: &str| details.and_then(|d| d.get(k));

    let message = payload
        .get("message")
        .and_then(Value::as_str)
        .filter(|m| !m.is_empty())
        .unwrap_or("unknown Ynison error")
        .to_owned();
    let grpc = parse_int(payload.get("grpc_code"));
    let http = parse_int(payload.get("http_code"));
    let code = detail("ynison-error-code").and_then(Value::as_str).map(str::to_owned);
    let backoff_ms = detail("ynison-backoff-millis")
        .and_then(Value::as_str)
        .map(|s| s.split(':').filter_map(|p| p.trim().parse().ok()).collect())
        .unwrap_or_default();
    let go_away = parse_int(detail("ynison-go-away-for-seconds")).unwrap_or(0);

    let unauthorized = matches!(grpc, Some(16) | Some(7)) || matches!(http, Some(401) | Some(403));
    let displaced = code.as_deref() == Some("400090001");
    let label = if unauthorized {
        "unauthorized"
    } else if displaced {
        "device displaced"
    } else {
        "server error"
    };
    YErr {
        message: format!("{label}: {message} (grpc={grpc:?} http={http:?} code={code:?})"),
        terminal: unauthorized || displaced || go_away > 0,
        backoff_ms,
    }
}

/// Parses a JSON frame; an `error` object becomes `Err`.
fn load_frame(text: &str) -> std::result::Result<Value, YErr> {
    let v: Value = serde_json::from_str(text)
        .map_err(|_| YErr::retry(format!("invalid frame from server: {}", text.chars().take(200).collect::<String>())))?;
    if !v.is_object() {
        return Err(YErr::retry("invalid frame from server: not an object"));
    }
    match v.get("error") {
        Some(e) if e.is_object() => Err(parse_server_error(e)),
        _ => Ok(v),
    }
}

/// Redirect frame; accepts camelCase and snake_case keys, int64 as number or string.
fn parse_redirect(text: &str) -> std::result::Result<Redirect, YErr> {
    let v = load_frame(text)?;
    let pick = |a: &str, b: &str| v.get(a).or_else(|| v.get(b));
    let s = |a: &str, b: &str| pick(a, b).and_then(Value::as_str).unwrap_or_default().to_owned();
    let params = pick("keepAliveParams", "keep_alive_params");
    let secs = |a: &str, b: &str| {
        params.and_then(|p| parse_int(p.get(a).or_else(|| p.get(b)))).unwrap_or(0).max(0) as u64
    };
    let r = Redirect {
        host: s("host", "host"),
        ticket: s("redirectTicket", "redirect_ticket"),
        session_id: parse_int(pick("sessionId", "session_id")).unwrap_or(0),
        keep_alive_secs: secs("keepAliveTimeSeconds", "keep_alive_time_seconds"),
        keep_alive_timeout_secs: secs("keepAliveTimeoutSeconds", "keep_alive_timeout_seconds"),
    };
    if r.host.is_empty() || r.ticket.is_empty() || r.session_id == 0 {
        return Err(YErr::retry(format!("incomplete redirect response: {}", text.chars().take(200).collect::<String>())));
    }
    Ok(r)
}

// ---------------------------------------------------------------- transport (_transport.py + client_async.py)

use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use futures_util::{SinkExt, StreamExt};
use tokio::net::TcpStream;
use tokio::sync::mpsc;
use tokio::task::JoinHandle;
use tokio::time::{sleep, timeout};
use tokio_tungstenite::tungstenite::handshake::client::Request;
use tokio_tungstenite::tungstenite::http::Uri;
use tokio_tungstenite::tungstenite::protocol::WebSocketConfig;
use tokio_tungstenite::tungstenite::{self, client::IntoClientRequest, ClientRequestBuilder, Message};
use tokio_tungstenite::{connect_async_with_config, MaybeTlsStream, WebSocketStream};

type Ws = WebSocketStream<MaybeTlsStream<TcpStream>>;

const OPEN_TIMEOUT: Duration = Duration::from_secs(10);
const REDIRECT_TIMEOUT: Duration = Duration::from_secs(10);
const MAX_FRAME_SIZE: usize = 64 * 1024 * 1024;
const DEFAULT_BACKOFF_MS: [u64; 4] = [0, 1000, 5000, 30000];
const DEFAULT_PING_SECS: u64 = 20;
const STATE_CHANNEL: usize = 64;
const COMMAND_CHANNEL: usize = 32;

/// Connection parameters. URLs are overridable so tests can point at a local server.
#[derive(Debug, Clone)]
struct Config {
    token: String,
    device_id: String,
    title: String,
    redirect_url: String,
    /// `wss` in production, `ws` for tests.
    state_scheme: &'static str,
}

impl Config {
    fn new(token: &str, device_id: &str, title: &str) -> Self {
        let device_id = if device_id.is_empty() {
            generate_device_id(Some(&format!("yandex-music-ynison:{token}")))
        } else {
            device_id.to_owned()
        };
        Config {
            token: token.to_owned(),
            device_id,
            title: title.to_owned(),
            redirect_url: format!("{BASE_URL}/{REDIRECT_SERVICE}"),
            state_scheme: "wss",
        }
    }
}

fn map_ws_err(e: tungstenite::Error) -> YErr {
    if let tungstenite::Error::Http(resp) = &e {
        if matches!(resp.status().as_u16(), 401 | 403) {
            return YErr::fatal(format!("unauthorized: Ynison rejected the token (http {})", resp.status()));
        }
    }
    YErr::retry(format!("websocket error: {e}"))
}

/// Handshake request: `Origin` + `Authorization: OAuth` headers and the three subprotocols.
fn build_request(token: &str, uri: &str, protocols: Vec<String>) -> std::result::Result<Request, YErr> {
    let uri: Uri = uri.parse().map_err(|e| YErr::fatal(format!("bad Ynison uri {uri}: {e}")))?;
    let mut b = ClientRequestBuilder::new(uri)
        .with_header("Origin", "https://music.yandex.ru")
        .with_header("Authorization", format!("OAuth {token}"));
    for p in protocols {
        b = b.with_sub_protocol(p);
    }
    b.into_client_request().map_err(|e| YErr::fatal(format!("cannot build handshake request: {e}")))
}

async fn open_ws(token: &str, uri: &str, protocols: Vec<String>) -> std::result::Result<Ws, YErr> {
    let request = build_request(token, uri, protocols)?;
    let ws_cfg = WebSocketConfig::default().max_message_size(Some(MAX_FRAME_SIZE)).max_frame_size(Some(MAX_FRAME_SIZE));
    match timeout(OPEN_TIMEOUT, connect_async_with_config(request, Some(ws_cfg), false)).await {
        Err(_) => Err(YErr::retry("timed out opening the websocket")),
        Ok(Err(e)) => Err(map_ws_err(e)),
        Ok(Ok((ws, _))) => Ok(ws),
    }
}

/// Step 1: ask the redirect service which host to use (it answers with one frame, then closes).
async fn fetch_redirect(cfg: &Config) -> std::result::Result<Redirect, YErr> {
    let protocols = subprotocols(&cfg.device_id, &cfg.title, None);
    let mut ws = open_ws(&cfg.token, &cfg.redirect_url, protocols).await?;
    let text = timeout(REDIRECT_TIMEOUT, async {
        loop {
            match ws.next().await {
                Some(Ok(Message::Text(t))) => return Ok(t.as_str().to_owned()),
                Some(Ok(Message::Binary(_))) => return Err(YErr::retry("redirect service sent a binary frame")),
                Some(Ok(Message::Close(_))) | None => {
                    return Err(YErr::retry("redirect service closed without an answer"))
                }
                Some(Ok(_)) => continue,
                Some(Err(e)) => return Err(map_ws_err(e)),
            }
        }
    })
    .await
    .map_err(|_| YErr::retry("redirect service did not answer in time"))?;
    // the close handshake runs in the background while we connect to the state host
    tokio::spawn(async move {
        let _ = ws.close(None).await;
    });
    parse_redirect(&text?)
}

/// An open state websocket plus its keep-alive settings.
struct Conn {
    ws: Ws,
    ping_every: Duration,
    ping_timeout: Duration,
}

/// Steps 1-3: redirect, connect to the returned host with the ticket, send `UpdateFullState`.
async fn open_state(cfg: &Config) -> std::result::Result<Conn, YErr> {
    let redirect = fetch_redirect(cfg).await?;
    let uri = format!("{}://{}/{STATE_SERVICE}", cfg.state_scheme, redirect.host);
    let protocols = subprotocols(&cfg.device_id, &cfg.title, Some(&redirect));
    let mut ws = open_ws(&cfg.token, &uri, protocols).await?;
    let hello = build_full_state_request(&cfg.device_id, &cfg.title, DEFAULT_APP_NAME);
    let text = serde_json::to_string(&hello).map_err(|e| YErr::fatal(format!("serialize: {e}")))?;
    ws.send(Message::text(text)).await.map_err(map_ws_err)?;
    let secs = |v: u64| Duration::from_secs(if v == 0 { DEFAULT_PING_SECS } else { v });
    Ok(Conn { ws, ping_every: secs(redirect.keep_alive_secs), ping_timeout: secs(redirect.keep_alive_timeout_secs) })
}

/// State shared between the client handle and the background task.
#[derive(Default)]
struct Shared {
    latest: Mutex<Option<YnisonState>>,
    last_error: Mutex<Option<String>>,
}

impl Shared {
    fn set_error(&self, msg: &str) {
        *self.last_error.lock().unwrap() = Some(msg.to_owned());
    }
}

enum End {
    Stopped,
    Terminal(YErr),
    Reconnect(YErr),
}

/// Reads frames, forwards commands, keeps the connection alive. Returns why it stopped.
async fn serve(
    conn: &mut Conn,
    shared: &Shared,
    tx: &mpsc::Sender<YnisonState>,
    cmd_rx: &mut mpsc::Receiver<String>,
    attempt: &mut u32,
) -> End {
    let mut ping = tokio::time::interval(conn.ping_every);
    ping.tick().await;
    let mut awaiting_pong: Option<Instant> = None;
    loop {
        tokio::select! {
            msg = conn.ws.next() => match msg {
                None => return End::Reconnect(YErr::retry("server closed the connection")),
                Some(Err(e)) => {
                    let e = map_ws_err(e);
                    return if e.terminal { End::Terminal(e) } else { End::Reconnect(e) };
                }
                Some(Ok(Message::Close(_))) => return End::Reconnect(YErr::retry("server closed the connection")),
                Some(Ok(Message::Pong(_))) => awaiting_pong = None,
                Some(Ok(Message::Text(t))) => match load_frame(t.as_str()) {
                    Err(e) if e.terminal => return End::Terminal(e),
                    Err(e) => shared.set_error(&e.message),
                    Ok(v) => match serde_json::from_value::<YnisonState>(v) {
                        Err(e) => log::debug!("ynison: unparsable state frame: {e}"),
                        Ok(state) => {
                            *attempt = 0;
                            *shared.latest.lock().unwrap() = Some(state.clone());
                            match tx.try_send(state) {
                                // frames are full snapshots, a slow consumer may skip some
                                Ok(()) | Err(mpsc::error::TrySendError::Full(_)) => {}
                                Err(mpsc::error::TrySendError::Closed(_)) => return End::Stopped,
                            }
                        }
                    },
                },
                Some(Ok(_)) => {}
            },
            cmd = cmd_rx.recv() => match cmd {
                None => return End::Stopped,
                Some(text) => {
                    if let Err(e) = conn.ws.send(Message::text(text)).await {
                        return End::Reconnect(map_ws_err(e));
                    }
                }
            },
            _ = ping.tick() => match awaiting_pong {
                Some(t) if t.elapsed() >= conn.ping_timeout => {
                    return End::Reconnect(YErr::retry("keep-alive: pong timeout"));
                }
                Some(_) => {}
                None => {
                    if let Err(e) = conn.ws.send(Message::Ping(Default::default())).await {
                        return End::Reconnect(map_ws_err(e));
                    }
                    awaiting_pong = Some(Instant::now());
                }
            },
        }
    }
}

/// Background loop: serve the connection, reconnect (full redirect again) with backoff.
async fn run(
    cfg: Config,
    first: Conn,
    shared: Arc<Shared>,
    tx: mpsc::Sender<YnisonState>,
    mut cmd_rx: mpsc::Receiver<String>,
) {
    let mut next = Some(first);
    let mut attempt: u32 = 0;
    let mut backoff: Vec<u64> = DEFAULT_BACKOFF_MS.to_vec();
    loop {
        let mut conn = match next.take() {
            Some(c) => c,
            None => {
                attempt += 1;
                let base = backoff[(attempt as usize - 1).min(backoff.len() - 1)];
                let jitter = (rand_u128() % 250) as u64;
                sleep(Duration::from_millis(base + jitter)).await;
                match open_state(&cfg).await {
                    Ok(c) => {
                        // commands queued while offline are stale
                        while cmd_rx.try_recv().is_ok() {}
                        c
                    }
                    Err(e) => {
                        shared.set_error(&e.message);
                        if e.terminal {
                            return;
                        }
                        if !e.backoff_ms.is_empty() {
                            backoff = e.backoff_ms;
                        }
                        continue;
                    }
                }
            }
        };
        match serve(&mut conn, &shared, &tx, &mut cmd_rx, &mut attempt).await {
            End::Stopped => return,
            End::Terminal(e) => {
                shared.set_error(&e.message);
                return;
            }
            End::Reconnect(e) => {
                shared.set_error(&e.message);
                if !e.backoff_ms.is_empty() {
                    backoff = e.backoff_ms;
                }
            }
        }
    }
}

// ---------------------------------------------------------------- public client

/// Ynison remote-control client. Receive state snapshots via [`YnisonClient::states`],
/// send commands via [`YnisonClient::send`] or the `pause`/`next_track`/... helpers.
/// Reconnects automatically; the state channel closes after a terminal error
/// (bad token, device displaced), see [`YnisonClient::last_error`].
pub struct YnisonClient {
    device_id: String,
    states: mpsc::Receiver<YnisonState>,
    cmd_tx: mpsc::Sender<String>,
    shared: Arc<Shared>,
    task: JoinHandle<()>,
}

impl YnisonClient {
    /// Connects with the default device title. An empty `device_id` derives a stable one from the token.
    pub async fn connect(token: &str, device_id: &str) -> YResult<Self> {
        Self::connect_with_title(token, device_id, DEFAULT_DEVICE_TITLE).await
    }

    /// Like [`connect`](Self::connect) with a custom device title (shown to other clients).
    pub async fn connect_with_title(token: &str, device_id: &str, title: &str) -> YResult<Self> {
        Self::connect_with(Config::new(token, device_id, title)).await
    }

    async fn connect_with(cfg: Config) -> YResult<Self> {
        let first = open_state(&cfg).await?;
        let (tx, states) = mpsc::channel(STATE_CHANNEL);
        let (cmd_tx, cmd_rx) = mpsc::channel(COMMAND_CHANNEL);
        let shared = Arc::new(Shared::default());
        let device_id = cfg.device_id.clone();
        let task = tokio::spawn(run(cfg, first, shared.clone(), tx, cmd_rx));
        Ok(YnisonClient { device_id, states, cmd_tx, shared, task })
    }

    pub fn device_id(&self) -> &str {
        &self.device_id
    }

    /// Stream of server state snapshots; `recv()` returns `None` once the client has stopped.
    pub fn states(&mut self) -> &mut mpsc::Receiver<YnisonState> {
        &mut self.states
    }

    /// Last received state, if any.
    pub fn latest_state(&self) -> Option<YnisonState> {
        self.shared.latest.lock().unwrap().clone()
    }

    /// Last connection or server error message, if any.
    pub fn last_error(&self) -> Option<String> {
        self.shared.last_error.lock().unwrap().clone()
    }

    /// Sends an arbitrary request frame (see the `build_*_request` helpers).
    pub async fn send(&self, request: &PutYnisonStateRequest) -> YResult<()> {
        let text = serde_json::to_string(request)?;
        self.cmd_tx.send(text).await.map_err(|_| {
            let why = self.last_error().unwrap_or_else(|| "connection closed".into());
            Error::Ynison(format!("no active Ynison connection: {why}"))
        })
    }

    fn state(&self) -> YResult<YnisonState> {
        self.latest_state().ok_or_else(|| Error::Ynison("no state received yet".into()))
    }

    pub async fn pause(&self) -> YResult<()> {
        self.set_paused(true).await
    }

    pub async fn resume(&self) -> YResult<()> {
        self.set_paused(false).await
    }

    async fn set_paused(&self, paused: bool) -> YResult<()> {
        let state = self.state()?;
        if active_device(&state).is_none() {
            return Err(Error::Ynison("no active device to pause/resume".into()));
        }
        let status = state.player_state.and_then(|p| p.status).unwrap_or_default();
        self.send(&build_set_paused_request(&self.device_id, &status, paused)).await
    }

    pub async fn next_track(&self) -> YResult<()> {
        self.change_track(1).await
    }

    pub async fn previous_track(&self) -> YResult<()> {
        self.change_track(-1).await
    }

    async fn change_track(&self, delta: i64) -> YResult<()> {
        let player = self.state()?.player_state.unwrap_or_default();
        self.send(&build_change_track_request(&self.device_id, &player, delta)?).await
    }

    /// Volume in `[0, 1]` on `target_device_id`, or on the active device.
    pub async fn set_volume(&self, volume: f64, target_device_id: Option<&str>) -> YResult<()> {
        let target = match target_device_id {
            Some(t) => t.to_owned(),
            None => active_device(&self.state()?)
                .and_then(|d| d.info.as_ref())
                .map(|i| i.device_id.clone())
                .unwrap_or_default(),
        };
        if target.is_empty() || target == self.device_id {
            return Err(Error::Ynison("no target device for volume; pass target_device_id".into()));
        }
        self.send(&build_set_volume_request(&self.device_id, &target, volume)).await
    }

    /// Stops the background task and drops the connection.
    pub fn close(self) {}
}

impl Drop for YnisonClient {
    fn drop(&mut self) {
        self.task.abort();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use tokio::net::TcpListener;
    use tokio_tungstenite::tungstenite::handshake::server::{ErrorResponse, Request as SReq, Response as SResp};

    const DEV: &str = "abc123def456";

    fn to_value(r: &PutYnisonStateRequest) -> Value {
        serde_json::to_value(r).unwrap()
    }

    #[test]
    fn full_state_matches_betterproto_shape() {
        let mut v = to_value(&build_full_state_request(DEV, "Python SDK", "yandex-music"));
        assert!(v["rid"].as_str().is_some_and(|s| s.len() == 36));
        v.as_object_mut().unwrap().remove("rid");
        let expected = json!({
            "updateFullState": {
                "device": {
                    "capabilities": {"canBeRemoteController": true},
                    "info": {"appName": "yandex-music", "deviceId": DEV, "title": "Python SDK", "type": "WEB"},
                    "volumeInfo": {}
                },
                "playerState": {
                    "playerQueue": {
                        "currentPlayableIndex": -1,
                        "entityType": "VARIOUS",
                        "fromOptional": "",
                        "options": {"repeatMode": "NONE"},
                        "version": {"deviceId": DEV}
                    },
                    "status": {"paused": true, "playbackSpeed": 1.0, "version": {"deviceId": DEV}}
                }
            }
        });
        assert_eq!(v, expected);
    }

    #[test]
    fn paused_request_shape() {
        let status = PlayingStatus {
            progress_ms: 200_000,
            duration_ms: 200_000,
            paused: false,
            playback_speed: 1.0,
            version: Some(UpdateVersion { device_id: "p".into(), version: 1, timestamp_ms: 0 }),
        };
        let v = to_value(&build_set_paused_request(DEV, &status, true));
        let s = &v["updatePlayingStatus"]["playingStatus"];
        assert_eq!(s["durationMs"], "200000"); // int64 as decimal string
        assert_eq!(s["progressMs"], "200000");
        assert_eq!(s["paused"], true);
        assert_eq!(s["playbackSpeed"], 1.0);
        assert_eq!(s["version"]["deviceId"], DEV);
        assert!(s["version"]["version"].is_string());
        assert!(s["version"]["timestampMs"].is_string());
        assert!(v["playerActionTimestampMs"].is_string());
        assert!(v.get("activityInterceptionType").is_none()); // default enum value is omitted
    }

    #[test]
    fn volume_request_shape_and_clamp() {
        let v = to_value(&build_set_volume_request(DEV, "target", 0.5));
        let u = &v["updateVolumeInfo"];
        assert_eq!(u["deviceId"], "target");
        assert_eq!(u["volumeInfo"]["volume"], 0.5);
        assert_eq!(u["volumeInfo"]["version"]["deviceId"], DEV);
        let hi = to_value(&build_set_volume_request(DEV, "t", 1.5));
        assert_eq!(hi["updateVolumeInfo"]["volumeInfo"]["volume"], 1.0);
        let lo = to_value(&build_set_volume_request(DEV, "t", -0.2));
        assert!(lo["updateVolumeInfo"]["volumeInfo"].get("volume").is_none()); // 0.0 is the default
    }

    #[test]
    fn state_frame_parses_camel_and_snake_case() {
        let camel = r#"{"activeDeviceIdOptional":"d","devices":[{"info":{"deviceId":"d","type":"WEB"},"volume":0.5}],
            "playerState":{"playerQueue":{"currentPlayableIndex":0,"entityType":"PLAYLIST",
            "playableList":[{"playableId":"1","playableType":"TRACK","title":"t"}]},
            "status":{"paused":true,"playbackSpeed":1.0,"progressMs":"5"}},"rid":"r","timestampMs":"9"}"#;
        let s: YnisonState = serde_json::from_str(camel).unwrap();
        assert_eq!(s.timestamp_ms, 9);
        assert_eq!(s.active_device_id_optional.as_deref(), Some("d"));
        let q = s.player_state.as_ref().unwrap().player_queue.as_ref().unwrap();
        assert_eq!(q.entity_type, PlayerQueueEntityType::PLAYLIST);
        assert_eq!(q.playable_list[0].playable_type, PlayablePlayableType::TRACK);
        assert_eq!(s.player_state.as_ref().unwrap().status.as_ref().unwrap().progress_ms, 5);
        assert_eq!(current_playable(&s).map(|p| p.title.as_str()), Some("t"));
        assert_eq!(active_device(&s).and_then(|d| d.info.as_ref()).map(|i| i.r#type), Some(DeviceType::WEB));

        let snake = r#"{"active_device_id_optional":"d","timestamp_ms":9,"devices":[{"info":{"device_id":"d","type":3}}]}"#;
        // snake_case keys are not what the server sends; they must at least not break parsing
        let s2: YnisonState = serde_json::from_str(snake).unwrap();
        assert_eq!(s2.devices.len(), 1);
    }

    #[test]
    fn device_id_is_sha256_prefix() {
        assert_eq!(generate_device_id(Some("abc")), "ba7816bf8f01");
        let r = generate_device_id(None);
        assert_eq!(r.len(), 12);
        assert!(r.bytes().all(|b| b.is_ascii_hexdigit()));
    }

    #[test]
    fn py_quote_matches_urllib() {
        assert_eq!(py_quote("a b,\u{e9}+/~"), "a%20b%2C%C3%A9%2B/~");
    }

    #[test]
    fn subprotocols_carry_device_info() {
        let p = subprotocols("abc", "My Dev", None);
        assert_eq!(&p[..2], ["Bearer", "v2"]);
        assert!(p[2].starts_with("%7B%22Ynison-Device-Id%22%3A%20%22abc%22%2C%20%22Ynison-Device-Info%22"));
        assert!(!p[2].contains("Redirect"));
        let r = Redirect { host: "h".into(), ticket: "tick".into(), session_id: 77, ..Default::default() };
        let p = subprotocols("abc", "My Dev", Some(&r));
        assert!(p[2].contains("%22Ynison-Redirect-Ticket%22%3A%20%22tick%22"));
        assert!(p[2].contains("%22Ynison-Session-Id%22%3A%20%2277%22"));
        // nested JSON string, exactly like Python's double json.dumps
        let raw = device_info_json("abc", "T", None);
        assert_eq!(raw, r#"{"Ynison-Device-Id": "abc", "Ynison-Device-Info": "{\"app_name\": \"T\", \"type\": \"1\"}"}"#);
    }

    #[test]
    fn redirect_frame() {
        let r = parse_redirect(
            r#"{"host":"h:1","redirectTicket":"t","sessionId":"77","keepAliveParams":{"keepAliveTimeSeconds":60,"keepAliveTimeoutSeconds":30}}"#,
        )
        .unwrap();
        assert_eq!((r.host.as_str(), r.ticket.as_str(), r.session_id), ("h:1", "t", 77));
        assert_eq!((r.keep_alive_secs, r.keep_alive_timeout_secs), (60, 30));
        assert!(parse_redirect(r#"{"host":"h"}"#).is_err());
    }

    #[test]
    fn server_errors_are_classified() {
        let unauth = load_frame(
            r#"{"error":{"grpc_code":16,"http_code":401,"message":"UNAUTHENTICATED: x",
            "extra_headers":{"ynison-error-code":"400160000","ynison-backoff-millis":"0:1000:5000:30000"}}}"#,
        )
        .unwrap_err();
        assert!(unauth.terminal && unauth.message.starts_with("unauthorized"));

        let displaced = load_frame(
            r#"{"error":{"details":{"ynison-error-code":"400090001","ynison-go-away-for-seconds":"3600"},
            "grpc_code":9,"http_code":400,"message":"dislocated"}}"#,
        )
        .unwrap_err();
        assert!(displaced.terminal && displaced.message.starts_with("device displaced"));

        let bad = load_frame(
            r#"{"error":{"details":{"ynison-error-code":"400030002","ynison-backoff-millis":"0:1000:5000:30000"},
            "grpc_code":3,"http_code":400,"message":"Unknown update request"}}"#,
        )
        .unwrap_err();
        assert!(!bad.terminal);
        assert_eq!(bad.backoff_ms, vec![0, 1000, 5000, 30000]);

        assert!(load_frame("not json").is_err());
        assert!(load_frame("[1]").is_err());
        assert!(load_frame(r#"{"timestampMs":"1"}"#).is_ok());
    }

    fn queue(size: usize, current: i64, shuffle: Option<Vec<i64>>) -> PlayerQueue {
        PlayerQueue {
            playable_list: (0..size).map(|i| Playable { playable_id: i.to_string(), ..Default::default() }).collect(),
            current_playable_index: current,
            shuffle_optional: shuffle.map(|playable_indices| Shuffle { playable_indices }),
            ..Default::default()
        }
    }

    #[test]
    fn neighbour_index_respects_shuffle_and_bounds() {
        assert_eq!(neighbour_index(&queue(3, 1, None), 1), Some(2));
        assert_eq!(neighbour_index(&queue(3, 1, None), -1), Some(0));
        assert_eq!(neighbour_index(&queue(3, 2, None), 1), None);
        assert_eq!(neighbour_index(&queue(3, 0, None), -1), None);
        // play order: 2 -> 0 -> 1
        let sh = Some(vec![2, 0, 1]);
        assert_eq!(neighbour_index(&queue(3, 0, sh.clone()), 1), Some(1));
        assert_eq!(neighbour_index(&queue(3, 0, sh.clone()), -1), Some(2));
        assert_eq!(neighbour_index(&queue(3, 1, sh), 1), None);
        assert_eq!(neighbour_index(&queue(0, -1, None), 1), None);
    }

    #[test]
    fn change_track_request_resets_progress() {
        let state = PlayerState {
            status: Some(PlayingStatus { paused: false, playback_speed: 0.0, ..Default::default() }),
            player_queue: Some(queue(3, 0, None)),
            ..Default::default()
        };
        let v = to_value(&build_change_track_request(DEV, &state, 1).unwrap());
        let ps = &v["updatePlayerState"]["playerState"];
        assert_eq!(ps["playerQueue"]["currentPlayableIndex"], 1);
        assert_eq!(ps["playerQueue"]["version"]["deviceId"], DEV);
        assert_eq!(ps["status"]["playbackSpeed"], 1.0); // zero speed falls back to 1.0
        assert!(ps["status"].get("progressMs").is_none());
        let end = PlayerState { player_queue: Some(queue(3, 2, None)), ..state };
        assert!(build_change_track_request(DEV, &end, 1).is_err());
    }

    #[test]
    fn progress_is_extrapolated_and_clamped() {
        let st = |paused| PlayingStatus {
            progress_ms: 1000,
            duration_ms: 10_000,
            paused,
            playback_speed: 1.5,
            version: Some(UpdateVersion { timestamp_ms: 100_000, ..Default::default() }),
        };
        assert_eq!(current_progress_ms(&st(false), Some(102_000)), 4000);
        assert_eq!(current_progress_ms(&st(true), Some(102_000)), 1000);
        assert_eq!(current_progress_ms(&st(false), Some(900_000)), 10_000);
    }

    type Seen = (String, String, String, String); // path, subprotocol header, authorization, first text

    async fn fake_server(listener: TcpListener, seen: mpsc::UnboundedSender<Seen>) {
        let port = listener.local_addr().unwrap().port();
        loop {
            let Ok((sock, _)) = listener.accept().await else { return };
            let seen = seen.clone();
            tokio::spawn(async move {
                let info = Arc::new(Mutex::new((String::new(), String::new(), String::new())));
                let cap = info.clone();
                let cb = move |req: &SReq, mut resp: SResp| -> std::result::Result<SResp, ErrorResponse> {
                    let h = |n: &str| req.headers().get(n).and_then(|v| v.to_str().ok()).unwrap_or("").to_owned();
                    *cap.lock().unwrap() = (req.uri().path().to_owned(), h("Sec-WebSocket-Protocol"), h("Authorization"));
                    resp.headers_mut().insert("Sec-WebSocket-Protocol", "Bearer".parse().unwrap());
                    Ok(resp)
                };
                let Ok(mut ws) = tokio_tungstenite::accept_hdr_async(sock, cb).await else { return };
                let (path, proto, auth) = info.lock().unwrap().clone();
                if path == "/redirect" {
                    let _ = seen.send((path, proto, auth, String::new()));
                    let frame = json!({"host": format!("127.0.0.1:{port}"), "redirectTicket": "ticket-1",
                        "sessionId": "123", "keepAliveParams": {"keepAliveTimeSeconds": 60, "keepAliveTimeoutSeconds": 30}});
                    let _ = ws.send(Message::text(frame.to_string())).await;
                    let _ = ws.close(None).await;
                    return;
                }
                let state = json!({
                    "activeDeviceIdOptional": "player1",
                    "devices": [{"info": {"deviceId": "player1", "type": "WEB"}}],
                    "playerState": {"status": {"playbackSpeed": 1.0, "progressMs": "5"}, "playerQueue": {}},
                    "rid": "r", "timestampMs": "9"
                });
                let mut first = true;
                while let Some(Ok(msg)) = ws.next().await {
                    if let Message::Text(t) = msg {
                        let _ = seen.send((path.clone(), proto.clone(), auth.clone(), t.as_str().to_owned()));
                        if first {
                            first = false;
                            let _ = ws.send(Message::text(state.to_string())).await;
                        }
                    }
                }
            });
        }
    }

    #[tokio::test]
    async fn end_to_end_against_local_server() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let (seen_tx, mut seen_rx) = mpsc::unbounded_channel::<Seen>();
        tokio::spawn(fake_server(listener, seen_tx));

        let mut cfg = Config::new("tok", "devid1", "T");
        cfg.redirect_url = format!("ws://127.0.0.1:{port}/redirect");
        cfg.state_scheme = "ws";
        let mut client = timeout(Duration::from_secs(5), YnisonClient::connect_with(cfg)).await.unwrap().unwrap();

        let redirect = seen_rx.recv().await.unwrap();
        assert_eq!(redirect.0, "/redirect");
        assert_eq!(redirect.2, "OAuth tok");
        assert!(redirect.1.starts_with("Bearer, v2, %7B"));
        assert!(!redirect.1.contains("Redirect-Ticket"));

        let hello = seen_rx.recv().await.unwrap();
        assert!(hello.0.ends_with("/ynison_state.YnisonStateService/PutYnisonState"));
        assert_eq!(hello.2, "OAuth tok");
        assert!(hello.1.contains("%22Ynison-Redirect-Ticket%22%3A%20%22ticket-1%22"));
        assert!(hello.1.contains("%22Ynison-Session-Id%22%3A%20%22123%22"));
        let v: Value = serde_json::from_str(&hello.3).unwrap();
        assert_eq!(v["updateFullState"]["device"]["info"]["deviceId"], "devid1");

        let state = timeout(Duration::from_secs(5), client.states().recv()).await.unwrap().unwrap();
        assert_eq!(state.timestamp_ms, 9);
        assert_eq!(state.active_device_id_optional.as_deref(), Some("player1"));
        assert_eq!(client.latest_state().unwrap().rid, "r");

        client.pause().await.unwrap();
        let cmd = timeout(Duration::from_secs(5), seen_rx.recv()).await.unwrap().unwrap();
        let v: Value = serde_json::from_str(&cmd.3).unwrap();
        assert_eq!(v["updatePlayingStatus"]["playingStatus"]["paused"], true);
        assert_eq!(v["updatePlayingStatus"]["playingStatus"]["version"]["deviceId"], "devid1");
    }

    #[tokio::test]
    async fn send_without_state_reports_error() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let (seen_tx, _seen_rx) = mpsc::unbounded_channel::<Seen>();
        tokio::spawn(fake_server(listener, seen_tx));
        let mut cfg = Config::new("tok", "", "T");
        cfg.redirect_url = format!("ws://127.0.0.1:{port}/redirect");
        cfg.state_scheme = "ws";
        let client = YnisonClient::connect_with(cfg).await.unwrap();
        assert_eq!(client.device_id().len(), 12); // derived from the token
        assert!(matches!(client.pause().await, Err(Error::Ynison(_)) | Ok(())));
    }
}
