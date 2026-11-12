//! Port of `yandex_music/playlist`.

use serde::{Deserialize, Serialize};

/// Playlist brand (image, background, tracking pixels).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Brand {
    /// Image URL.
    pub image: Option<String>,
    /// Background color.
    pub background: Option<String>,
    /// URI reference to the content.
    pub reference: Option<String>,
    /// Web-beacon GIF URLs.
    pub pixels: Vec<String>,
    /// Theme.
    pub theme: Option<String>,
    /// Playlist theme.
    pub playlist_theme: Option<String>,
    /// Button text.
    pub button: Option<String>,
}

/// Name declensions.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct CaseForms {
    /// Nominative case.
    pub nominative: Option<String>,
    /// Genitive case.
    pub genitive: Option<String>,
    /// Dative case.
    pub dative: Option<String>,
    /// Accusative case.
    pub accusative: Option<String>,
    /// Instrumental case.
    pub instrumental: Option<String>,
    /// Prepositional case.
    pub prepositional: Option<String>,
}

/// Playlist contest.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Contest {
    /// Unique id.
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub contest_id: Option<String>,
    /// Status (`editing`, `withdrew-moderator`).
    pub status: Option<String>,
    /// Whether editing is allowed.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub can_edit: Option<bool>,
    /// Submission date.
    pub sent: Option<String>,
    /// Withdrawal date.
    pub withdrawn: Option<String>,
}

/// Additional playlist description (wave).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct CustomWave {
    /// Playlist title.
    pub title: Option<String>,
    /// Lottie animation JSON URL.
    pub animation_url: Option<String>,
    /// Position.
    pub position: Option<String>,
    /// Wave header.
    pub header: Option<String>,
    /// Background image URL.
    pub background_image_url: Option<String>,
    /// Square agent animation URL.
    pub square_agent_animation: Option<String>,
}

/// Marker of a playlist made for the current user.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct MadeForUser {
    /// Whether the playlist is made for the current user.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub is_made_for_user: Option<bool>,
    /// User name declensions.
    pub case_forms: Option<CaseForms>,
}

/// User a playlist was made for.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct MadeFor {
    /// The user.
    pub user_info: Option<crate::models::playlist::User>,
    /// User name declensions.
    pub case_forms: Option<CaseForms>,
}

/// Open Graph data.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct OpenGraphData {
    /// Title.
    pub title: Option<String>,
    /// Description.
    pub description: Option<String>,
    /// Image.
    pub image: Option<crate::models::common::Cover>,
}

/// Consecutive-days counter of the playlist of the day.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct PlayCounter {
    /// Number of days.
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub value: Option<i64>,
    /// Counter description.
    pub description: Option<String>,
    /// Whether it was updated today.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub updated: Option<bool>,
}

/// Reason why a playlist is absent.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct PlaylistAbsence {
    /// Playlist kind.
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub kind: Option<String>,
    /// Reason.
    pub reason: Option<String>,
}

/// Playlist trailer availability.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct PlaylistAvailability {
    /// Whether the trailer is available.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub available: Option<bool>,
}

/// Unique playlist identifier.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct PlaylistId {
    /// Owner uid.
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub uid: Option<String>,
    /// Playlist kind.
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub kind: Option<String>,
}

impl PlaylistId {
    /// Full playlist id (`uid:kind`).
    pub fn playlist_id(&self) -> String {
        format!(
            "{}:{}",
            self.uid.as_deref().unwrap_or(""),
            self.kind.as_deref().unwrap_or("")
        )
    }
}

/// Recommended tracks for a playlist.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct PlaylistRecommendations {
    /// Recommended tracks.
    pub tracks: Vec<crate::models::track::Track>,
    /// Batch id.
    pub batch_id: Option<String>,
}

/// Similar entities of a playlist.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct PlaylistSimilarEntities {
    /// Similar entity items (typed in the `wave` module).
    pub items: Vec<serde_json::Value>,
}

/// Playlist trailer.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct PlaylistTrailer {
    /// Playlist.
    pub playlist: Option<Box<Playlist>>,
    /// Trailer info.
    pub trailer: Option<crate::models::common::TrailerInfo>,
    /// Whether the trailer is shareable.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub shareable: Option<bool>,
}

/// List of playlists.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct PlaylistsList {
    /// Playlists.
    pub playlists: Vec<Playlist>,
}

/// Tag with the ids of its playlists.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct TagResult {
    /// Playlist ids.
    pub ids: Vec<PlaylistId>,
    /// Tag (may be absent).
    pub tag: Option<Tag>,
}

/// Tag (collection).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Tag {
    /// Unique tag id.
    pub id: Option<String>,
    /// Lower-case tag value.
    pub value: Option<String>,
    /// Display name.
    pub name: Option<String>,
    /// Open Graph description.
    pub og_description: Option<String>,
    /// Open Graph image URL.
    pub og_image: Option<String>,
}

/// User (owner of a playlist or playlist author).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct User {
    /// User uid.
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub uid: Option<String>,
    /// Login.
    pub login: Option<String>,
    /// Name.
    pub name: Option<String>,
    /// Display name.
    pub display_name: Option<String>,
    /// Full name.
    pub full_name: Option<String>,
    /// Sex.
    pub sex: Option<String>,
    /// Whether the user participates in playlist generation.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub verified: Option<bool>,
    /// Regions.
    pub regions: Vec<String>,
}

/// Playlist.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Playlist {
    /// Cover.
    pub cover: Option<crate::models::common::Cover>,
    /// Owner.
    pub owner: Option<User>,
    /// User the playlist was made for.
    pub made_for: Option<MadeFor>,
    /// Days counter (playlist of the day only).
    pub play_counter: Option<PlayCounter>,
    /// Absence reason.
    #[serde(
        default,
        alias = "playlistAbsense",
        alias = "playlist_absense",
        deserialize_with = "opt_absence"
    )]
    pub playlist_absence: Option<PlaylistAbsence>,
    /// Owner uid.
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub uid: Option<String>,
    /// Playlist kind.
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub kind: Option<String>,
    /// Title.
    pub title: Option<String>,
    /// Track count.
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub track_count: Option<i64>,
    /// Tags.
    pub tags: Vec<serde_json::Value>,
    /// Revision.
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub revision: Option<i64>,
    /// Snapshot version.
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub snapshot: Option<i64>,
    /// Visibility (`public` / `private`).
    pub visibility: Option<String>,
    /// Whether the playlist has coauthors.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub collective: Option<bool>,
    /// URL part (`daily`).
    pub url_part: Option<String>,
    /// Creation date (ISO 8601).
    pub created: Option<String>,
    /// Last modification date (ISO 8601).
    pub modified: Option<String>,
    /// Whether the playlist is available.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub available: Option<bool>,
    /// Whether the playlist is a banner.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub is_banner: Option<bool>,
    /// Whether the playlist is a premiere.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub is_premiere: Option<bool>,
    /// Duration in milliseconds.
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub duration_ms: Option<i64>,
    /// Open Graph preview URL.
    pub og_image: Option<String>,
    /// Open Graph title.
    pub og_title: Option<String>,
    /// Open Graph description.
    pub og_description: Option<String>,
    /// Image.
    pub image: Option<String>,
    /// Cover without text.
    pub cover_without_text: Option<crate::models::common::Cover>,
    /// Contest.
    pub contest: Option<Contest>,
    /// Background color.
    pub background_color: Option<String>,
    /// Text color.
    pub text_color: Option<String>,
    /// Source event id.
    pub id_for_from: Option<String>,
    /// Placeholder description.
    pub dummy_description: Option<String>,
    /// Placeholder page description.
    pub dummy_page_description: Option<String>,
    /// Placeholder cover.
    pub dummy_cover: Option<crate::models::common::Cover>,
    /// Placeholder rollover cover.
    pub dummy_rollover_cover: Option<crate::models::common::Cover>,
    /// Open Graph data.
    pub og_data: Option<OpenGraphData>,
    /// Brand.
    pub branding: Option<Brand>,
    /// Metrika counter id.
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub metrika_id: Option<i64>,
    /// Coauthor account ids.
    #[serde(deserialize_with = "crate::models::de::opt_ids")]
    pub coauthors: Option<Vec<String>>,
    /// Top artists.
    pub top_artist: Vec<crate::models::artist::Artist>,
    /// Recent track ids.
    pub recent_tracks: Vec<crate::models::landing::TrackId>,
    /// Tracks.
    pub tracks: Vec<crate::models::common::TrackShort>,
    /// Preroll items.
    pub prerolls: Vec<serde_json::Value>,
    /// Likes count.
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub likes_count: Option<i64>,
    /// Similar playlists.
    pub similar_playlists: Vec<Playlist>,
    /// Last owner playlists.
    pub last_owner_playlists: Vec<Playlist>,
    /// Generated playlist type.
    pub generated_playlist_type: Option<String>,
    /// Animated cover URI.
    pub animated_cover_uri: Option<String>,
    /// Whether the playlist was ever played.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub ever_played: Option<bool>,
    /// Markdown description.
    pub description: Option<String>,
    /// Plain-text description.
    pub description_formatted: Option<String>,
    /// Playlist UUID.
    pub playlist_uuid: Option<String>,
    /// Type.
    pub r#type: Option<String>,
    /// Whether the playlist is ready.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub ready: Option<bool>,
    /// Source event data.
    pub is_for_from: Option<serde_json::Value>,
    /// Regions.
    pub regions: Option<serde_json::Value>,
    /// Custom wave description.
    pub custom_wave: Option<CustomWave>,
    /// Pager.
    pub pager: Option<crate::models::common::Pager>,
    /// Whether the playlist has a trailer.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub has_trailer: Option<bool>,
    /// Trailer availability.
    pub trailer: Option<PlaylistAvailability>,
    /// Background video URL.
    pub background_video_url: Option<String>,
    /// Background video id.
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub background_video_id: Option<String>,
    /// Background image URL.
    pub background_image_url: Option<String>,
    /// Action button.
    pub action_button: Option<crate::models::album::AlbumActionButton>,
    /// Artist playlist type (`TOP`, `SIMILAR`).
    pub artist_playlist_type: Option<String>,
    /// Whether the playlist is child content.
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub child_content: Option<bool>,
    /// Cover derived colors.
    pub derived_colors: Option<crate::models::common::CoverDerivedColors>,
    /// Marker of a personal playlist.
    pub made_for_user: Option<MadeForUser>,
}

impl Playlist {
    /// Full playlist id (`owner:kind`, or just kind when there is no owner).
    pub fn playlist_id(&self) -> String {
        match (&self.owner, &self.kind) {
            (Some(owner), kind) => format!("{}:{}", owner.uid.as_deref().unwrap_or(""), kind.as_deref().unwrap_or("")),
            (None, Some(kind)) => kind.clone(),
            (None, None) => String::new(),
        }
    }

    /// Whether the playlist belongs to the given account uid.
    pub fn is_mine(&self, account_uid: Option<&str>) -> bool {
        match (&self.owner, account_uid) {
            (Some(owner), Some(acc)) => owner.uid.as_deref() == Some(acc),
            _ => false,
        }
    }

    /// Animated cover URL for the given size.
    pub fn animated_cover_url(&self, size: &str) -> Option<String> {
        self.animated_cover_uri
            .as_ref()
            .map(|uri| format!("https://{}", uri.replace("%%", size)))
    }

    /// Open Graph image URL for the given size.
    pub fn og_image_url(&self, size: &str) -> Option<String> {
        self.og_image
            .as_ref()
            .map(|uri| format!("https://{}", uri.replace("%%", size)))
    }
}

fn opt_absence<'de, D>(d: D) -> Result<Option<PlaylistAbsence>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    Ok(Option::<PlaylistAbsence>::deserialize(d).ok().flatten())
}
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deserialize_playlist() {
        let json = r##"{
            "uid": 503646255,
            "kind": 69814820,
            "title": "Плейлист дня",
            "trackCount": 57,
            "tags": [],
            "revision": 0,
            "snapshot": 1,
            "visibility": "public",
            "collective": false,
            "urlPart": "daily",
            "created": "2018-04-29T21:00:00+00:00",
            "available": true,
            "durationMs": 12402690,
            "ogImage": "avatars.yandex.net/get-music-user-playlist/38125/q0ahkhfQE3neTk/%%?1572609906461",
            "image": "",
            "background_color": "",
            "idForFrom": "playlist_of_the_day",
            "metrikaId": 666666,
            "coauthors": [1130000003905541],
            "prerolls": [],
            "likesCount": 1,
            "generatedPlaylistType": "playlistOfTheDay",
            "animatedCoverUri": "avatars.yandex.net/get-music-user-playlist/30088/q0ahjvoZK5FT4A/%%",
            "type": "missedLikes",
            "owner": {"uid": 503646255, "login": "example", "verified": true, "regions": []},
            "cover": {"uri": "avatars.yandex.net/get-music-user-playlist/38125/q0ahkhfQE3neTk/%%", "type": "mosaic"},
            "madeFor": {"userInfo": {"uid": 1}, "caseForms": {"nominative": "Иван"}},
            "playCounter": {"value": 3, "description": "3 дня подряд", "updated": true},
            "playlistAbsense": {"kind": 1, "reason": "not-found"},
            "branding": {"image": "https://x", "background": "#fff", "reference": "ym:brand", "pixels": ["https://p"]},
            "customWave": {"title": "Волна", "animationUrl": "https://a"},
            "pager": {"total": 100, "page": 1, "perPage": 100},
            "similarPlaylists": [{"kind": 2, "title": "x"}],
            "tracks": [{"id": 1, "albumId": 2}],
            "madeForUser": {"isMadeForUser": true}
        }"##;
        let p: Playlist = serde_json::from_str(json).unwrap();
        assert_eq!(p.uid.as_deref(), Some("503646255"));
        assert_eq!(p.kind.as_deref(), Some("69814820"));
        assert_eq!(p.track_count, Some(57));
        assert_eq!(p.r#type.as_deref(), Some("missedLikes"));
        assert_eq!(p.playlist_id(), "503646255:69814820");
        assert!(p.is_mine(Some("503646255")));
        assert_eq!(p.playlist_absence.as_ref().unwrap().reason.as_deref(), Some("not-found"));
        assert_eq!(p.coauthors.as_deref(), Some(&["1130000003905541".to_string()][..]));
        assert_eq!(p.similar_playlists.len(), 1);
        assert_eq!(p.tracks.len(), 1);
        assert_eq!(
            p.og_image_url("300x300").unwrap(),
            "https://avatars.yandex.net/get-music-user-playlist/38125/q0ahkhfQE3neTk/300x300?1572609906461"
        );
    }

    #[test]
    fn deserialize_small_models() {
        let tag: TagResult = serde_json::from_str(
            r##"{"ids": [{"uid": 1, "kind": 2}], "tag": {"id": "x", "value": "v", "name": "N"}}"##,
        )
        .unwrap();
        assert_eq!(tag.ids[0].playlist_id(), "1:2");
        assert_eq!(tag.tag.unwrap().value.as_deref(), Some("v"));

        let t: PlaylistTrailer = serde_json::from_str(
            r##"{"playlist": {"kind": 5}, "trailer": {"available": true}, "shareable": false}"##,
        )
        .unwrap();
        assert_eq!(t.playlist.unwrap().kind.as_deref(), Some("5"));
        assert_eq!(t.shareable, Some(false));
    }
}
