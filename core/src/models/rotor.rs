//! Models of the `yandex_music/rotor` package (radio stations, sessions, wave settings).

use serde::Deserialize;
use serde::Serialize;

/// Advertising parameters of a station.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct AdParams {
    /// Advertiser id.
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub partner_id: Option<String>,
    /// Advertising category id.
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub category_id: Option<String>,
    /// Referring page link.
    pub page_ref: Option<String>,
    /// Target page link.
    pub target_ref: Option<String>,
    /// Other parameters.
    pub other_params: Option<String>,
    /// Ad volume.
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub ad_volume: Option<i64>,
    /// Genre id.
    pub genre_id: Option<String>,
    /// Genre name.
    pub genre_name: Option<String>,
}

/// Element of a combined radio session (`CLIP` or `TRACK`).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct CombinedSessionItem {
    /// Element type.
    pub r#type: Option<String>,
    /// Raw element payload; deserialize as `crate::models::clip::Clip` or `crate::models::track::Track` by `r#type`.
    pub data: Option<serde_json::Value>,
}

/// Landing (showcase) of a combined radio session.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct CombinedSessionLanding {
    /// Title.
    pub title: Option<String>,
    /// Description.
    pub description: Option<String>,
    /// Button text.
    pub button: Option<String>,
    /// Showcase items.
    pub list: Option<Vec<crate::models::rotor::CombinedSessionItem>>,
}

/// Queue item used when creating a combined radio session.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct CombinedSessionQueueItem {
    /// Element type (`CLIP` or `TRACK`).
    pub r#type: Option<String>,
    /// Clip or track id.
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub id: Option<String>,
}

/// Combined radio session (tracks and clips).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct CombinedSession {
    /// Session id.
    pub session_id: Option<String>,
    /// Batch id.
    pub batch_id: Option<String>,
    /// Pumpkin flag.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub pumpkin: Option<bool>,
    /// Session items.
    pub list: Option<Vec<crate::models::rotor::CombinedSessionItem>>,
}

/// User's recommended stations dashboard.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Dashboard {
    /// Dashboard id.
    pub dashboard_id: Option<String>,
    /// Stations with all settings.
    pub stations: Option<Vec<crate::models::rotor::StationResult>>,
    /// Pumpkin flag.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub pumpkin: Option<bool>,
}

/// Discrete scale setting (`discrete-scale`).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct DiscreteScale {
    /// Scale type.
    pub r#type: Option<String>,
    /// Scale name.
    pub name: Option<String>,
    /// Minimum value.
    pub min: Option<crate::models::rotor::Value>,
    /// Maximum value.
    pub max: Option<crate::models::rotor::Value>,
}

/// Enumeration setting (`enum`).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Enum {
    /// Enum type.
    pub r#type: Option<String>,
    /// Enum name.
    pub name: Option<String>,
    /// Possible values.
    pub possible_values: Option<Vec<crate::models::rotor::Value>>,
}

/// Visual appearance of a generative station.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct GenerativeStreamData {
    /// Station title.
    pub title: Option<String>,
    /// Station subtitle.
    pub subtitle: Option<String>,
    /// Background color in HEX.
    pub background_color: Option<String>,
    /// Derived cover colors.
    pub derived_colors: Option<crate::models::common::CoverDerivedColors>,
    /// Image url.
    pub image_url: Option<String>,
    /// Video cover uri.
    pub video_cover_uri: Option<String>,
    /// Station explanation.
    pub explanations: Option<String>,
}

/// Feedback response of a generative station.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct GenerativeStreamFeedback {
    /// Whether the stream must be reloaded.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub reload_stream: Option<bool>,
    /// Whether the stream is playing (not paused).
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub not_paused: Option<bool>,
}

/// Stream of a generative station.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct GenerativeStreamInfo {
    /// Stream id.
    pub id: Option<String>,
    /// Stream url.
    pub url: Option<String>,
}

/// Generative station information.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct GenerativeStream {
    /// Station appearance.
    pub data: Option<crate::models::rotor::GenerativeStreamData>,
    /// Generative model version.
    pub version: Option<String>,
    /// Station stream.
    pub stream: Option<crate::models::rotor::GenerativeStreamInfo>,
}

/// Unique station identifier.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Id {
    /// Station type.
    pub r#type: Option<String>,
    /// Station tag.
    pub tag: Option<String>,
}

/// Station settings restrictions.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Restrictions {
    /// Language values.
    pub language: Option<crate::models::rotor::Enum>,
    /// Diversity values.
    pub diversity: Option<crate::models::rotor::Enum>,
    /// Mood restriction.
    pub mood: Option<crate::models::rotor::DiscreteScale>,
    /// Energy restriction.
    pub energy: Option<crate::models::rotor::DiscreteScale>,
    /// Mood values.
    pub mood_energy: Option<crate::models::rotor::Enum>,
}

/// Radio seed (`type:tag`).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct RotorSeed {
    /// Seed type.
    pub r#type: Option<String>,
    /// Seed tag.
    pub tag: Option<String>,
    /// Seed value.
    pub value: Option<String>,
}

/// Next batch of tracks of a radio session.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct RotorSessionTracks {
    /// Batch id.
    pub batch_id: Option<String>,
    /// Pumpkin flag.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub pumpkin: Option<bool>,
    /// Track sequence.
    pub sequence: Option<Vec<crate::models::rotor::Sequence>>,
    /// Whether the session is terminated.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub terminated: Option<bool>,
    /// Whether the session was not found.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub unknown_session: Option<bool>,
    /// Offline recommender data.
    pub offline_recommender_data: Option<Vec<i64>>,
}

/// Radio session.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct RotorSession {
    /// Radio session id.
    pub radio_session_id: Option<String>,
    /// Batch id.
    pub batch_id: Option<String>,
    /// Pumpkin flag.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub pumpkin: Option<bool>,
    /// Track sequence.
    pub sequence: Option<Vec<crate::models::rotor::Sequence>>,
    /// Accepted seeds.
    pub accepted_seeds: Option<Vec<crate::models::rotor::RotorSeed>>,
    /// Seed describing the session.
    pub description_seed: Option<crate::models::rotor::RotorSeed>,
    /// Whether the session is terminated.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub terminated: Option<bool>,
    /// Session wave model.
    pub wave: Option<crate::models::wave::Wave>,
    /// Offline recommender data.
    pub offline_recommender_data: Option<Vec<i64>>,
    /// Whether the session is interactive.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub interactive: Option<bool>,
}

/// Station settings.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct RotorSettings {
    /// Language.
    pub language: Option<String>,
    /// Diversity.
    pub diversity: Option<String>,
    /// Mood (legacy settings).
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub mood: Option<i64>,
    /// Energy (legacy settings).
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub energy: Option<i64>,
    /// Mood values.
    pub mood_energy: Option<String>,
}

/// Sequence link of a radio session.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Sequence {
    /// Link type (`track`).
    pub r#type: Option<String>,
    /// Track.
    pub track: Option<Box<crate::models::track::Track>>,
    /// Whether the track is liked.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub liked: Option<bool>,
    /// Track parameters in radio.
    pub track_parameters: Option<crate::models::rotor::TrackParameters>,
}

/// Radio session feedback event.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct SessionEvent {
    /// Event type.
    pub r#type: Option<String>,
    /// Event time (ISO 8601 string or unix number).
    pub timestamp: Option<serde_json::Value>,
    /// Track id (`id` or `id:album_id`).
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub track_id: Option<String>,
    /// Played seconds.
    #[serde(deserialize_with = "crate::models::de::opt_f64")]
    pub total_played_seconds: Option<f64>,
    /// Playable object.
    pub playable: Option<crate::models::rotor::SessionPlayable>,
}

/// Radio session feedback.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct SessionFeedback {
    /// Event.
    pub event: Option<crate::models::rotor::SessionEvent>,
    /// Batch id the event relates to.
    pub batch_id: Option<String>,
    /// Playback origin.
    #[serde(rename = "from")]
    pub from_: Option<String>,
}

/// Feedback set for a single radio session.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct SessionFeedbacks {
    /// Radio session id.
    pub session_id: Option<String>,
    /// Feedbacks.
    pub feedbacks: Option<Vec<crate::models::rotor::SessionFeedback>>,
}

/// Playable object in a radio session event (`track` or `clip`).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct SessionPlayable {
    /// Object type.
    pub r#type: Option<String>,
    /// Track id.
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub track_id: Option<String>,
    /// Clip id.
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub id: Option<String>,
}

/// Personal station information.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct StationData {
    /// Station name.
    pub name: Option<String>,
}

/// Radio station with settings.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct StationResult {
    /// Station.
    pub station: Option<crate::models::rotor::Station>,
    /// First settings set.
    pub settings: Option<crate::models::rotor::RotorSettings>,
    /// Second settings set.
    pub settings2: Option<crate::models::rotor::RotorSettings>,
    /// Ad parameters.
    pub ad_params: Option<crate::models::rotor::AdParams>,
    /// Explanation.
    pub explanation: Option<String>,
    /// Prerolls.
    pub prerolls: Option<Vec<String>>,
    /// Station title.
    pub rup_title: Option<String>,
    /// Station description.
    pub rup_description: Option<String>,
    /// Custom station name.
    pub custom_name: Option<String>,
}

/// Track sequence of a station.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct StationTracksResult {
    /// Station id.
    pub id: Option<crate::models::rotor::Id>,
    /// Track sequence.
    pub sequence: Option<Vec<crate::models::rotor::Sequence>>,
    /// Batch id.
    pub batch_id: Option<String>,
    /// Pumpkin flag.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub pumpkin: Option<bool>,
    /// Radio session id.
    pub radio_session_id: Option<String>,
}

/// Radio station.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Station {
    /// Station id.
    pub id: Option<crate::models::rotor::Id>,
    /// Station name.
    pub name: Option<String>,
    /// Station icon.
    pub icon: Option<crate::models::common::Icon>,
    /// MTS icon.
    pub mts_icon: Option<crate::models::common::Icon>,
    /// Station category.
    pub id_for_from: Option<String>,
    /// Legacy settings restrictions.
    pub restrictions: Option<crate::models::rotor::Restrictions>,
    /// Settings restrictions.
    pub restrictions2: Option<crate::models::rotor::Restrictions>,
    /// Geocell icon.
    pub geocell_icon: Option<crate::models::common::Icon>,
    /// Full image url.
    pub full_image_url: Option<String>,
    /// Full MTS image url.
    pub mts_full_image_url: Option<String>,
    /// Parent station id.
    pub parent_id: Option<crate::models::rotor::Id>,
    /// Whether the station is a special wave context.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub special_context: Option<bool>,
    /// Listeners count.
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub listeners: Option<i64>,
    /// Owner login.
    pub login: Option<String>,
    /// Owner full name.
    pub full_name: Option<String>,
    /// Owner display name.
    pub display_name: Option<String>,
    /// Visibility.
    pub visibility: Option<String>,
}

/// Track parameters in radio.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct TrackParameters {
    /// Tempo (beats per minute).
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub bpm: Option<i64>,
    /// Energy.
    #[serde(deserialize_with = "crate::models::de::opt_f64")]
    pub energy: Option<f64>,
    /// Hue.
    #[serde(deserialize_with = "crate::models::de::opt_f64")]
    pub hue: Option<f64>,
    /// User collection hue.
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub user_collection_hue: Option<i64>,
    /// Mix fade parameters.
    pub mix_fade: Option<crate::models::track::Fade>,
}

/// Setting value.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Value {
    /// Value (string or number).
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub value: Option<String>,
    /// Name.
    pub name: Option<String>,
    /// Image url.
    pub image_url: Option<String>,
    /// Serialized seed (e.g. `settingDiversity:favorite`).
    pub serialized_seed: Option<String>,
    /// Whether the value is the default ("Any").
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub unspecified: Option<bool>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deserialize_station_tracks_result() {
        let json = r#"{
            "id": {"type": "genre", "tag": "rock"},
            "sequence": [
                {
                    "type": "track",
                    "track": {"id": "12345", "title": "Song", "durationMs": 200000},
                    "liked": false,
                    "trackParameters": {"bpm": 120, "energy": 0.5, "hue": 1.0}
                }
            ],
            "batchId": "1573227402825981-2727432063278102211",
            "pumpkin": false,
            "radioSessionId": "fake-radio-session-id"
        }"#;
        let r: StationTracksResult = serde_json::from_str(json).unwrap();
        assert_eq!(r.batch_id.as_deref(), Some("1573227402825981-2727432063278102211"));
        assert_eq!(r.id.unwrap().tag.as_deref(), Some("rock"));
        let seq = &r.sequence.unwrap()[0];
        assert_eq!(seq.track.as_ref().unwrap().id.as_deref(), Some("12345"));
        assert_eq!(seq.track_parameters.as_ref().unwrap().bpm, Some(120));
    }

    #[test]
    fn deserialize_restrictions_and_dashboard() {
        let json = r#"{
            "dashboardId": "mobile-main",
            "pumpkin": false,
            "stations": [{
                "station": {
                    "id": {"type": "user", "tag": "onyourwave"},
                    "name": "Моя волна",
                    "icon": {"imageUrl": "https://img/yandex-music.png"},
                    "restrictions": {
                        "language": {"type": "enum", "name": "Язык",
                            "possibleValues": [{"value": "any", "name": "Любой", "unspecified": true}]},
                        "diversity": {"type": "enum", "name": "Разнообразие", "possibleValues": []},
                        "energy": {"type": "discrete-scale", "name": "Энергичность",
                            "min": {"value": "0", "name": "0"}, "max": {"value": "1", "name": "1"}}
                    },
                    "restrictions2": {}
                },
                "settings": {"language": "any", "diversity": "default", "mood": 0},
                "settings2": {"language": "any", "diversity": "default", "moodEnergy": "all"},
                "adParams": {"partnerId": 123, "categoryId": "456", "pageRef": "p", "targetRef": "t",
                    "otherParams": "user:1", "adVolume": 100},
                "rupTitle": "Моя волна", "rupDescription": "Твоя музыка"
            }]
        }"#;
        let d: Dashboard = serde_json::from_str(json).unwrap();
        let st = &d.stations.unwrap()[0];
        let station = st.station.as_ref().unwrap();
        let restr = station.restrictions.as_ref().unwrap();
        assert_eq!(restr.language.as_ref().unwrap().r#type.as_deref(), Some("enum"));
        assert_eq!(restr.energy.as_ref().unwrap().max.as_ref().unwrap().value.as_deref(), Some("1"));
        assert_eq!(st.settings2.as_ref().unwrap().mood_energy.as_deref(), Some("all"));
        assert_eq!(st.ad_params.as_ref().unwrap().partner_id.as_deref(), Some("123"));
    }

    #[test]
    fn deserialize_session_feedback() {
        let json = r#"{
            "event": {"type": "trackFinished", "timestamp": 1700000000, "trackId": 42, "totalPlayedSeconds": 30},
            "batchId": "b1",
            "from": "radio-mobile-user-onyourwave"
        }"#;
        let f: SessionFeedback = serde_json::from_str(json).unwrap();
        let ev = f.event.unwrap();
        assert_eq!(ev.track_id.as_deref(), Some("42"));
        assert_eq!(ev.total_played_seconds, Some(30.0));
        assert_eq!(f.from_.as_deref(), Some("radio-mobile-user-onyourwave"));
    }
}
