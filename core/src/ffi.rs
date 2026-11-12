//! UniFFI facade for the iOS app (proc-macro based, uniffi 0.32).
//!
//! The Swift side maps the `Ffi*` records into its own models (see `MusicService.swift`).

use std::collections::HashMap;
use std::sync::Mutex;

use crate::models::rotor::Sequence;
use crate::models::search::SearchResult;

use futures_util::stream::{self, StreamExt};
use serde::de::DeserializeOwned;
use serde_json::Value;
use tokio::sync::OnceCell;

use crate::client::rotor_sessions::{SessionParams, WaveFeedback};
use crate::client::tracks::Quality;
use crate::models::album::Album;
use crate::models::artist::Artist;
use crate::models::common::{Cover, TrackShort};
use crate::models::feed::GeneratedPlaylist;
use crate::models::landing::BlockEntity;
use crate::models::playlist::Playlist;
use crate::models::track::Track;
use crate::Client;

// ---------------------------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------------------------

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum FfiError {
    /// No connectivity, timeout or a gateway hiccup: worth retrying later / falling back to cache.
    #[error("{msg}")]
    Network { msg: String },
    /// Token rejected.
    #[error("{msg}")]
    Unauthorized { msg: String },
    #[error("{msg}")]
    Message { msg: String },
}

impl From<crate::Error> for FfiError {
    fn from(e: crate::Error) -> Self {
        let msg = e.to_string();
        match e {
            crate::Error::Network(_) | crate::Error::TimedOut => FfiError::Network { msg },
            crate::Error::Unauthorized(_) => FfiError::Unauthorized { msg },
            _ => FfiError::Message { msg },
        }
    }
}

// ---------------------------------------------------------------------------------------------
// Records
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiArtistRef {
    pub id: String,
    pub name: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiTrack {
    pub id: String,
    pub title: String,
    pub version: Option<String>,
    pub artists: Vec<FfiArtistRef>,
    pub album_id: Option<String>,
    pub cover_uri: Option<String>,
    pub duration_ms: i64,
    pub explicit: bool,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiAlbum {
    pub id: String,
    pub title: String,
    pub artists: Vec<FfiArtistRef>,
    pub cover_uri: Option<String>,
    pub year: Option<i64>,
    pub track_count: Option<i64>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiArtist {
    pub id: String,
    pub name: String,
    pub cover_uri: Option<String>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiPlaylist {
    /// "ownerUid:kind"
    pub id: String,
    pub title: String,
    pub owner_name: Option<String>,
    pub cover_uri: Option<String>,
    pub track_count: Option<i64>,
}

/// One shelf entry; `kind` is "track" | "album" | "playlist" | "artist" and the matching field is set.
#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiShelfItem {
    pub kind: String,
    pub track: Option<FfiTrack>,
    pub album: Option<FfiAlbum>,
    pub playlist: Option<FfiPlaylist>,
    pub artist: Option<FfiArtist>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiShelf {
    pub id: String,
    pub title: String,
    pub items: Vec<FfiShelfItem>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiWaveSeed {
    pub id: String,
    pub title: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiMix {
    pub id: String,
    pub title: String,
    pub subtitle: String,
    pub cover_uris: Vec<String>,
    pub station_id: String,
}

/// `dest_kind` is "liked" | "history" | "playlist" | "album" | "artist"; `dest_id` is its id.
#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiQuickTile {
    pub id: String,
    pub title: String,
    pub subtitle: Option<String>,
    pub cover_uri: Option<String>,
    pub dest_kind: String,
    pub dest_id: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiHome {
    pub wave: FfiWaveSeed,
    pub wave_seeds: Vec<FfiWaveSeed>,
    pub mixes: Vec<FfiMix>,
    pub quick_access: Vec<FfiQuickTile>,
    pub shelves: Vec<FfiShelf>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiSearch {
    pub best: Option<FfiShelfItem>,
    pub tracks: Vec<FfiTrack>,
    pub albums: Vec<FfiAlbum>,
    pub artists: Vec<FfiArtist>,
    pub playlists: Vec<FfiPlaylist>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiStream {
    pub url: String,
    /// Hex AES-128-CTR key (zero IV) when the stream is `encraw`; `None` for plain streams.
    pub key: Option<String>,
    /// `flac` | `flac-mp4` | `aac-mp4` | `he-aac-mp4` | `aac` | `he-aac` | `mp3` (may be empty).
    pub codec: String,
    /// kbit/s, when the server reports it.
    pub bitrate: Option<i64>,
    /// Quality actually granted: `lossless` | `hq` | `nq`.
    pub quality: String,
}

// ---------------------------------------------------------------------------------------------
// Mapping helpers
// ---------------------------------------------------------------------------------------------

fn cover_of(c: &Option<Cover>) -> Option<String> {
    let c = c.as_ref()?;
    c.uri
        .clone()
        .filter(|u| !u.is_empty())
        .or_else(|| c.items_uri.as_ref().and_then(|v| v.first().cloned()))
}

fn map_artist_refs(list: &[Artist]) -> Vec<FfiArtistRef> {
    list.iter()
        .map(|a| FfiArtistRef { id: a.id.clone().unwrap_or_default(), name: a.name.clone().unwrap_or_default() })
        .collect()
}

fn map_track(t: &Track) -> Option<FfiTrack> {
    let id = t.id.clone().or_else(|| t.real_id.clone())?;
    Some(FfiTrack {
        id,
        title: t.title.clone().unwrap_or_default(),
        version: t.version.clone().filter(|v| !v.is_empty()),
        artists: map_artist_refs(&t.artists),
        album_id: t.albums.first().and_then(|a| a.id.clone()),
        cover_uri: t.cover_uri.clone().or_else(|| t.og_image.clone()),
        duration_ms: t.duration_ms.unwrap_or(0),
        explicit: t.explicit.unwrap_or(false),
    })
}

fn map_album(a: &Album) -> Option<FfiAlbum> {
    Some(FfiAlbum {
        id: a.id.clone()?,
        title: a.title.clone().unwrap_or_default(),
        artists: map_artist_refs(&a.artists),
        cover_uri: a.cover_uri.clone().or_else(|| cover_of(&a.cover)),
        year: a.year.or(a.original_release_year),
        track_count: a.track_count,
    })
}

fn map_artist(a: &Artist) -> Option<FfiArtist> {
    Some(FfiArtist { id: a.id.clone()?, name: a.name.clone().unwrap_or_default(), cover_uri: cover_of(&a.cover) })
}

fn map_playlist(p: &Playlist) -> Option<FfiPlaylist> {
    let uid = p.uid.clone().or_else(|| p.owner.as_ref().and_then(|o| o.uid.clone()))?;
    let kind = p.kind.clone()?;
    Some(FfiPlaylist {
        id: format!("{uid}:{kind}"),
        title: p.title.clone().unwrap_or_default(),
        owner_name: p.owner.as_ref().and_then(|o| o.name.clone().or_else(|| o.login.clone())),
        cover_uri: cover_of(&p.cover).or_else(|| p.og_image.clone()),
        track_count: p.track_count,
    })
}

fn item(kind: &str) -> FfiShelfItem {
    FfiShelfItem { kind: kind.to_owned(), track: None, album: None, playlist: None, artist: None }
}
fn item_track(t: &Track) -> Option<FfiShelfItem> {
    Some(FfiShelfItem { track: Some(map_track(t)?), ..item("track") })
}
fn item_album(a: &Album) -> Option<FfiShelfItem> {
    Some(FfiShelfItem { album: Some(map_album(a)?), ..item("album") })
}
fn item_playlist(p: &Playlist) -> Option<FfiShelfItem> {
    Some(FfiShelfItem { playlist: Some(map_playlist(p)?), ..item("playlist") })
}
fn item_artist(a: &Artist) -> Option<FfiShelfItem> {
    Some(FfiShelfItem { artist: Some(map_artist(a)?), ..item("artist") })
}

fn from_json<T: DeserializeOwned>(v: &Value) -> Option<T> {
    serde_json::from_value(v.clone()).ok()
}

fn item_from_typed(kind: &str, v: &Value) -> Option<FfiShelfItem> {
    match kind {
        "track" => item_track(&from_json::<Track>(v)?),
        "album" => item_album(&from_json::<Album>(v)?),
        "artist" => item_artist(&from_json::<Artist>(v)?),
        "playlist" => item_playlist(&from_json::<Playlist>(v)?),
        _ => None,
    }
}

fn generated_item(v: &Value) -> Option<FfiShelfItem> {
    item_playlist(&from_json::<GeneratedPlaylist>(v)?.data?)
}

fn entity_item(e: &BlockEntity) -> Option<FfiShelfItem> {
    let d = e.data.as_ref()?;
    match e.r#type.as_deref().unwrap_or("") {
        "chart-item" => d.get("track").and_then(|t| item_from_typed("track", t)),
        "personal-playlist" => generated_item(d),
        t @ ("album" | "playlist" | "track" | "artist") => item_from_typed(t, d),
        _ if d.get("data").is_some() => generated_item(d),
        _ if d.get("kind").is_some() => item_from_typed("playlist", d),
        _ => None,
    }
}

fn item_cover(i: &FfiShelfItem) -> Option<String> {
    i.playlist
        .as_ref()
        .and_then(|p| p.cover_uri.clone())
        .or_else(|| i.album.as_ref().and_then(|a| a.cover_uri.clone()))
        .or_else(|| i.track.as_ref().and_then(|t| t.cover_uri.clone()))
        .or_else(|| i.artist.as_ref().and_then(|a| a.cover_uri.clone()))
}

fn push_shelf(out: &mut Vec<FfiShelf>, id: String, title: String, items: Vec<FfiShelfItem>) {
    if !items.is_empty() {
        out.push(FfiShelf { id, title, items });
    }
}

// ---------------------------------------------------------------------------------------------
// Client object
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Clone)]
struct Session {
    id: String,
    batch: Option<String>,
}

fn msg(s: impl Into<String>) -> FfiError {
    FfiError::Message { msg: s.into() }
}

/// "753 трека", "1 трек", "5 треков".
fn tracks_count_ru(n: i64) -> String {
    let word = match (n % 10, n % 100) {
        (_, 11..=14) => "треков",
        (1, _) => "трек",
        (2..=4, _) => "трека",
        _ => "треков",
    };
    format!("{n} {word}")
}

/// Likes in the order the official apps show them: most recently liked first.
///
/// The API already answers newest-first (measured), but the order is sorted by the like
/// timestamp rather than trusted. The sort is stable, so entries without a timestamp keep
/// their place relative to each other (after the dated ones).
fn newest_first(shorts: &mut [TrackShort]) {
    shorts.sort_by(|a, b| b.timestamp.cmp(&a.timestamp));
}

fn seq_tracks(seq: Option<&[Sequence]>) -> Vec<FfiTrack> {
    seq.unwrap_or(&[]).iter().filter_map(|s| s.track.as_deref().and_then(map_track)).collect()
}

fn results_of<T: DeserializeOwned>(r: &Option<SearchResult>) -> Vec<T> {
    r.as_ref().map(|r| r.results.iter().filter_map(from_json::<T>).collect()).unwrap_or_default()
}

#[derive(uniffi::Object)]
pub struct YmClient {
    inner: Client,
    init: OnceCell<()>,
    /// station id -> rotor radio session
    sessions: Mutex<HashMap<String, Session>>,
}

impl YmClient {
    /// Resolve the account uid once (needed by likes / playlists / history).
    async fn ensure_init(&self) -> Result<(), FfiError> {
        self.init
            .get_or_try_init(|| async { self.inner.init().await.map(|_| ()) })
            .await?;
        Ok(())
    }

    async fn fetch_tracks(&self, ids: Vec<String>) -> Result<HashMap<String, Track>, FfiError> {
        let chunks: Vec<Vec<String>> = ids.chunks(100).map(|c| c.to_vec()).collect();
        let inner = &self.inner;
        let results: Vec<_> = stream::iter(chunks)
            .map(move |c| async move { inner.tracks_lenient(&c).await })
            .buffered(4)
            .collect()
            .await;
        let mut out = HashMap::new();
        for r in results {
            for t in r? {
                if let Some(id) = t.id.clone() {
                    out.insert(id, t);
                }
            }
        }
        Ok(out)
    }

    /// Map short tracks, fetching full models for those that came without one.
    async fn resolve_shorts(&self, shorts: &[TrackShort]) -> Result<Vec<FfiTrack>, FfiError> {
        let missing: Vec<String> = shorts.iter().filter(|s| s.track.is_none()).filter_map(|s| s.id.clone()).collect();
        let fetched = if missing.is_empty() { HashMap::new() } else { self.fetch_tracks(missing).await? };
        Ok(shorts
            .iter()
            .filter_map(|s| {
                let mut t = match s.track.as_deref() {
                    Some(t) => map_track(t),
                    None => s.id.as_ref().and_then(|i| fetched.get(i)).and_then(map_track),
                }?;
                if t.album_id.is_none() {
                    t.album_id = s.album_id.clone();
                }
                Some(t)
            })
            .collect())
    }

    async fn liked(&self) -> Result<Vec<FfiTrack>, FfiError> {
        self.ensure_init().await?;
        let list = self.inner.users_likes_tracks(None, 0).await?;
        let mut shorts = list.and_then(|l| l.tracks).unwrap_or_default();
        newest_first(&mut shorts);
        self.resolve_shorts(&shorts).await
    }

    /// (count, cover of the newest liked track) for the home tile.
    async fn liked_summary(&self) -> Result<(i64, Option<String>), FfiError> {
        let list = self.inner.users_likes_tracks(None, 0).await?;
        let mut shorts = list.and_then(|l| l.tracks).unwrap_or_default();
        newest_first(&mut shorts);
        let count = shorts.len() as i64;
        let cover = match shorts.first().and_then(|s| s.id.clone()) {
            Some(id) => self
                .inner
                .tracks_lenient(&[id])
                .await
                .ok()
                .and_then(|t| t.first().and_then(map_track))
                .and_then(|t| t.cover_uri),
            None => None,
        };
        Ok((count, cover))
    }

    async fn history(&self) -> Result<Vec<FfiTrack>, FfiError> {
        self.ensure_init().await?;
        let h = self.inner.music_history(30).await?;
        let mut direct: Vec<(usize, FfiTrack)> = Vec::new();
        let mut missing: Vec<(usize, String)> = Vec::new();
        let mut n = 0usize;
        for tab in h.and_then(|h| h.history_tabs).unwrap_or_default() {
            for group in tab.items.unwrap_or_default() {
                for it in group.tracks.unwrap_or_default() {
                    let Some(data) = it.data else { continue };
                    n += 1;
                    let full = data.full_model.as_ref().and_then(from_json::<Track>).and_then(|t| map_track(&t));
                    match (full, data.item_id.and_then(|i| i.track_id)) {
                        (Some(t), _) => direct.push((n, t)),
                        (None, Some(id)) => missing.push((n, id)),
                        _ => {}
                    }
                }
            }
        }
        if !missing.is_empty() {
            let fetched = self.fetch_tracks(missing.iter().map(|(_, id)| id.clone()).collect()).await?;
            for (i, id) in missing {
                if let Some(t) = fetched.get(&id).and_then(map_track) {
                    direct.push((i, t));
                }
            }
        }
        direct.sort_by_key(|(i, _)| *i);
        Ok(direct.into_iter().map(|(_, t)| t).collect())
    }
}

#[uniffi::export(async_runtime = "tokio")]
impl YmClient {
    #[uniffi::constructor]
    pub fn new(token: String) -> Result<std::sync::Arc<Self>, FfiError> {
        let token = Some(token).filter(|t| !t.is_empty());
        Ok(std::sync::Arc::new(Self {
            inner: Client::new(token)?,
            init: OnceCell::new(),
            sessions: Mutex::new(HashMap::new()),
        }))
    }

    pub async fn home(&self) -> Result<FfiHome, FfiError> {
        self.ensure_init().await?;
        let blocks = ["personalplaylists", "new-releases", "new-playlists", "chart"];
        let (feed, landing, last, plists, liked, history) = tokio::join!(
            self.inner.feed(),
            self.inner.landing(&blocks),
            self.inner.rotor_wave_last(),
            self.inner.users_playlists_list(None),
            self.liked_summary(),
            self.history()
        );

        let mut shelves: Vec<FfiShelf> = Vec::new();
        if let Ok(Some(feed)) = &feed {
            let items = feed
                .generated_playlists
                .iter()
                .filter_map(|g| g.data.as_ref().and_then(item_playlist))
                .collect();
            push_shelf(&mut shelves, "feed".into(), "Собрано для вас".into(), items);
        }
        let have_feed = !shelves.is_empty();
        if let Ok(Some(l)) = &landing {
            for b in &l.blocks {
                if have_feed && b.r#type.as_deref() == Some("personal-playlists") {
                    continue;
                }
                let items: Vec<FfiShelfItem> = b.entities.iter().filter_map(entity_item).take(30).collect();
                let kind = b.r#type.clone().unwrap_or_default();
                let title = b.title.clone().filter(|t| !t.is_empty()).unwrap_or_else(|| match kind.as_str() {
                    "personal-playlists" => "Собрано для вас".into(),
                    "new-releases" => "Новые релизы".into(),
                    "new-playlists" => "Новые плейлисты".into(),
                    "chart" => "Чарт".into(),
                    other => other.to_owned(),
                });
                // Stable id = block type ("new-releases", "chart", …) so the app can style a
                // shelf by kind; the API's own block ids are random per response.
                let mut id = if kind.is_empty() { b.id.clone().unwrap_or_default() } else { kind };
                if shelves.iter().any(|s| s.id == id) {
                    id = format!("{id}-{}", shelves.len());
                }
                push_shelf(&mut shelves, id, title, items);
            }
        }
        if shelves.is_empty() {
            if let Err(e) = &landing {
                return Err(msg(e.to_string()));
            }
            if let Err(e) = &feed {
                return Err(msg(e.to_string()));
            }
        }

        let mut wave_seeds = Vec::new();
        if let Ok(Some(w)) = &last {
            // A tuned My Wave ("user:onyourwave" + setting seeds) is not a seed wave: no chips.
            let my_wave = w.seeds.iter().flatten().any(|s| s == "user:onyourwave");
            for s in w.seeds.iter().flatten().filter(|s| !my_wave && !s.starts_with("setting")) {
                wave_seeds.push(FfiWaveSeed { id: s.clone(), title: w.name.clone().unwrap_or_else(|| s.clone()) });
            }
        }

        let covers: Vec<String> = shelves.iter().flat_map(|s| s.items.iter()).filter_map(item_cover).take(6).collect();
        let mix = |i: usize, id: &str, title: &str, subtitle: &str, station: &str| FfiMix {
            id: id.into(),
            title: title.into(),
            subtitle: subtitle.into(),
            cover_uris: covers.iter().skip(i * 2).take(2).cloned().collect(),
            station_id: station.into(),
        };
        let mixes = vec![
            mix(0, "foryou", "Для вас", "По вашим вкусам", "personal:recent-tracks"),
            mix(1, "trends", "Тренды", "Сейчас слушают", "personal:hits"),
            mix(2, "new", "Незнакомое", "Вы ещё не слышали", "personal:never-heard"),
            mix(3, "collection", "Коллекция", "Ваша музыка", "personal:collection"),
        ];

        let (liked_count, liked_cover) = liked.unwrap_or((0, None));
        let history = history.unwrap_or_default();
        let mut history_artists: Vec<String> = Vec::new();
        for a in history.iter().flat_map(|t| t.artists.iter()).map(|a| a.name.clone()) {
            if !a.is_empty() && !history_artists.contains(&a) {
                history_artists.push(a);
            }
            if history_artists.len() == 2 {
                break;
            }
        }
        let mut quick_access = vec![
            FfiQuickTile {
                id: "liked".into(),
                title: "Мне нравится".into(),
                subtitle: (liked_count > 0).then(|| tracks_count_ru(liked_count)),
                cover_uri: liked_cover,
                dest_kind: "liked".into(),
                dest_id: "liked".into(),
            },
            FfiQuickTile {
                id: "history".into(),
                title: "История".into(),
                subtitle: (!history_artists.is_empty()).then(|| history_artists.join(", ")),
                cover_uri: history.first().and_then(|t| t.cover_uri.clone()),
                dest_kind: "history".into(),
                dest_id: "history".into(),
            },
        ];
        if let Ok(pl) = &plists {
            for p in pl.iter().filter_map(map_playlist).take(2) {
                quick_access.push(FfiQuickTile {
                    id: format!("pl:{}", p.id),
                    title: p.title,
                    subtitle: p.owner_name,
                    cover_uri: p.cover_uri,
                    dest_kind: "playlist".into(),
                    dest_id: p.id,
                });
            }
        }

        Ok(FfiHome {
            wave: FfiWaveSeed { id: "user:onyourwave".into(), title: "Моя волна".into() },
            wave_seeds,
            mixes,
            quick_access,
            shelves,
        })
    }

    /// Next batch for a station. Creates (and caches) a rotor session on first use.
    pub async fn wave_tracks(&self, station_id: String, queue: Vec<String>) -> Result<Vec<FfiTrack>, FfiError> {
        let existing = self.sessions.lock().unwrap().get(&station_id).cloned();
        if let Some(s) = existing {
            if let Ok(Some(r)) = self.inner.rotor_session_tracks(&s.id, Some(queue.as_slice()), None).await {
                let tracks = seq_tracks(r.sequence.as_deref());
                if !tracks.is_empty() {
                    if let Some(sess) = self.sessions.lock().unwrap().get_mut(&station_id) {
                        sess.batch = r.batch_id.or(sess.batch.take());
                    }
                    return Ok(tracks);
                }
            }
            // Session expired or exhausted: start a fresh one below.
            self.sessions.lock().unwrap().remove(&station_id);
        }

        let params = SessionParams {
            queue: (!queue.is_empty()).then(|| queue.clone()),
            include_tracks_in_response: Some(true),
            ..Default::default()
        };
        // A station id may carry extra seeds after commas: "user:onyourwave,settingMoodEnergy:calm".
        let seeds: Vec<&str> = station_id.split(',').map(str::trim).filter(|s| !s.is_empty()).collect();
        let r = self
            .inner
            .rotor_session_new(&seeds, &params)
            .await?
            .ok_or_else(|| msg("empty rotor session"))?;
        let sid = r.radio_session_id.clone().ok_or_else(|| msg("rotor session without id"))?;
        let mut batch = r.batch_id.clone();
        let mut tracks = seq_tracks(r.sequence.as_deref());
        // Announce the radio start once per session (the app's `radioStarted` event is a no-op).
        let _ = self.inner.rotor_session_feedback_radio_started(&sid, batch.as_deref(), None, None).await;
        if tracks.is_empty() {
            if let Some(t) = self.inner.rotor_session_tracks(&sid, Some(queue.as_slice()), None).await? {
                tracks = seq_tracks(t.sequence.as_deref());
                batch = t.batch_id.or(batch);
            }
        }
        self.sessions.lock().unwrap().insert(station_id, Session { id: sid, batch });
        Ok(tracks)
    }

    /// `kind`: radioStarted | trackStarted | trackFinished | skip | like | dislike.
    pub async fn wave_feedback(
        &self,
        station_id: String,
        track_id: Option<String>,
        kind: String,
        played_seconds: f64,
    ) -> Result<(), FfiError> {
        let Some(s) = self.sessions.lock().unwrap().get(&station_id).cloned() else { return Ok(()) };
        let fb = match (kind.as_str(), track_id) {
            ("trackStarted", Some(track_id)) => WaveFeedback::TrackStarted { track_id },
            ("trackFinished", Some(track_id)) => WaveFeedback::TrackFinished { track_id, played_seconds },
            ("skip", Some(track_id)) => WaveFeedback::Skip { track_id, played_seconds },
            ("like", Some(track_id)) => WaveFeedback::Like { track_id },
            ("dislike", Some(track_id)) => WaveFeedback::Dislike { track_id },
            // radioStarted is sent when the session is created; anything else is ignored.
            _ => return Ok(()),
        };
        self.inner.rotor_session_feedback(&s.id, &fb, s.batch.as_deref(), None).await?;
        Ok(())
    }

    /// Resolve a playable stream.
    ///
    /// - `quality`: `lossless` (FLAC) | `hq` (AAC 256) | `nq` (AAC 192) | `lq` (HE-AAC 64).
    /// - `codecs`: acceptable codecs, empty = every codec the API knows.
    /// - `key` in the result is set only for encrypted (`encraw`) streams.
    ///
    /// The API itself has no "lq" quality: the 64 kbit/s HE-AAC file is what it serves when the
    /// client accepts nothing but `he-aac-mp4`. If that one is missing we fall back to `nq`.
    pub async fn stream_url(&self, track_id: String, quality: String, codecs: Vec<String>) -> Result<FfiStream, FfiError> {
        let low = quality == "lq" && codecs.is_empty();
        let q = Quality::parse(&quality);
        let list: Vec<&str> = if low { vec!["he-aac-mp4"] } else { codecs.iter().map(String::as_str).collect() };
        let mut found = self.inner.direct_link(&track_id, q, (!list.is_empty()).then_some(list.as_slice())).await;
        if low && matches!(&found, Err(e) if !matches!(e, crate::Error::Network(_) | crate::Error::TimedOut)) {
            found = self.inner.direct_link(&track_id, q, None).await;
        }
        let s = found?;
        let granted = match s.quality.as_deref() {
            Some(v @ ("lossless" | "hq" | "nq" | "lq")) => v.to_owned(),
            _ if s.codec.starts_with("he-aac") => "lq".to_owned(),
            _ => q.as_str().to_owned(),
        };
        Ok(FfiStream { url: s.url, key: s.key.filter(|k| !k.is_empty()), codec: s.codec, bitrate: s.bitrate, quality: granted })
    }

    /// Report a listen to the service (`/play-audio`) so history and recommendations follow.
    pub async fn report_play(
        &self,
        track_id: String,
        album_id: Option<String>,
        duration_seconds: f64,
        played_seconds: f64,
        from_cache: bool,
    ) -> Result<(), FfiError> {
        self.ensure_init().await?;
        self.inner
            .play_audio(
                &track_id,
                "mobile-own-ymusic",
                album_id.as_deref().unwrap_or(""),
                None,
                from_cache,
                None,
                None,
                None,
                duration_seconds.max(0.0) as i64,
                played_seconds.max(0.0),
                played_seconds.max(0.0),
                None,
            )
            .await?;
        Ok(())
    }

    pub async fn search(&self, query: String) -> Result<FfiSearch, FfiError> {
        let s = self.inner.search(&query, false, "all", 0, true).await?.unwrap_or_default();
        let best = s.best.as_ref().and_then(|b| {
            let kind = b.r#type.as_deref()?;
            item_from_typed(kind, b.result.as_ref()?)
        });
        Ok(FfiSearch {
            best,
            tracks: results_of::<Track>(&s.tracks).iter().filter_map(map_track).collect(),
            albums: results_of::<Album>(&s.albums).iter().filter_map(map_album).collect(),
            artists: results_of::<Artist>(&s.artists).iter().filter_map(map_artist).collect(),
            playlists: results_of::<Playlist>(&s.playlists).iter().filter_map(map_playlist).collect(),
        })
    }

    pub async fn liked_tracks(&self) -> Result<Vec<FfiTrack>, FfiError> {
        self.liked().await
    }

    pub async fn set_liked(&self, track_id: String, liked: bool) -> Result<(), FfiError> {
        self.ensure_init().await?;
        let ids = [track_id];
        if liked {
            self.inner.users_likes_tracks_add(&ids, None).await?;
        } else {
            self.inner.users_likes_tracks_remove(&ids, None).await?;
        }
        Ok(())
    }

    /// Ids of liked tracks, newest first. One light request (no track models).
    pub async fn liked_ids(&self) -> Result<Vec<String>, FfiError> {
        self.ensure_init().await?;
        let list = self.inner.users_likes_tracks(None, 0).await?;
        let mut shorts = list.and_then(|l| l.tracks).unwrap_or_default();
        newest_first(&mut shorts);
        Ok(shorts.into_iter().filter_map(|t| t.id).collect())
    }

    pub async fn liked_albums(&self) -> Result<Vec<FfiAlbum>, FfiError> {
        self.ensure_init().await?;
        let likes = self.inner.users_likes_albums(None, true).await?;
        Ok(likes.iter().filter_map(|l| l.album.as_deref().and_then(map_album)).collect())
    }

    pub async fn liked_artists(&self) -> Result<Vec<FfiArtist>, FfiError> {
        self.ensure_init().await?;
        let likes = self.inner.users_likes_artists(None, true).await?;
        Ok(likes.iter().filter_map(|l| l.artist.as_deref().and_then(map_artist)).collect())
    }

    pub async fn my_playlists(&self) -> Result<Vec<FfiPlaylist>, FfiError> {
        self.ensure_init().await?;
        let list = self.inner.users_playlists_list(None).await?;
        Ok(list.iter().filter_map(map_playlist).collect())
    }

    /// `kind`: liked | history | playlist ("uid:kind") | album | artist.
    pub async fn tracks_of(&self, kind: String, id: String) -> Result<Vec<FfiTrack>, FfiError> {
        match kind.as_str() {
            "liked" => self.liked().await,
            "history" => self.history().await,
            "playlist" => {
                self.ensure_init().await?;
                let (uid, pkind) = id.split_once(':').ok_or_else(|| msg(format!("bad playlist id {id}")))?;
                let p = self
                    .inner
                    .users_playlists(pkind, Some(uid))
                    .await?
                    .ok_or_else(|| msg("playlist not found"))?;
                self.resolve_shorts(&p.tracks).await
            }
            "album" => {
                let a = self.inner.albums_with_tracks(&id).await?.ok_or_else(|| msg("album not found"))?;
                let album_id = a.id.clone();
                Ok(a.volumes
                    .unwrap_or_default()
                    .iter()
                    .flatten()
                    .filter_map(map_track)
                    .map(|mut t| {
                        if t.album_id.is_none() {
                            t.album_id = album_id.clone();
                        }
                        t
                    })
                    .collect())
            }
            "artist" => {
                let r = self.inner.artists_tracks(&id, 0, 50).await?;
                Ok(r.and_then(|r| r.tracks).unwrap_or_default().iter().filter_map(map_track).collect())
            }
            other => Err(msg(format!("unknown destination kind {other}"))),
        }
    }
}
