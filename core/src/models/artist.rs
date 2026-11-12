//! Models of the `yandex_music/artist` package.

use serde::{Deserialize, Serialize};

/// External link of an artist (tickets, socials).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Link {
    pub title: Option<String>,
    pub href: Option<String>,
    pub r#type: Option<String>,
    pub social_network: Option<String>,
}

/// Artist link with an optional subtitle and image.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ArtistLink {
    pub title: Option<String>,
    pub subtitle: Option<String>,
    pub url: Option<String>,
    pub img_url: Option<String>,
}

/// Collection of artist links.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ArtistLinks {
    pub links: Option<Vec<ArtistLink>>,
}

/// Artist counters.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Counts {
    #[serde(default, deserialize_with = "crate::models::de::opt_i64")]
    pub tracks: Option<i64>,
    #[serde(default, deserialize_with = "crate::models::de::opt_i64")]
    pub direct_albums: Option<i64>,
    #[serde(default, deserialize_with = "crate::models::de::opt_i64")]
    pub also_albums: Option<i64>,
    #[serde(default, deserialize_with = "crate::models::de::opt_i64")]
    pub also_tracks: Option<i64>,
}

/// Artist chart ratings.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Ratings {
    #[serde(default, deserialize_with = "crate::models::de::opt_i64")]
    pub month: Option<i64>,
    #[serde(default, deserialize_with = "crate::models::de::opt_i64")]
    pub week: Option<i64>,
    #[serde(default, deserialize_with = "crate::models::de::opt_i64")]
    pub day: Option<i64>,
}

/// Artist listening statistics.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Stats {
    #[serde(default, deserialize_with = "crate::models::de::opt_i64")]
    pub last_month_listeners: Option<i64>,
    #[serde(default, deserialize_with = "crate::models::de::opt_i64")]
    pub last_month_listeners_delta: Option<i64>,
}

/// Artist description text.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Description {
    pub text: Option<String>,
    pub uri: Option<String>,
}

/// Artist trailer availability.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ArtistTrailerStatus {
    #[serde(default, deserialize_with = "crate::models::de::opt_bool")]
    pub available: Option<bool>,
}

/// Artist trailer with the artist object.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ArtistTrailer {
    pub artist: Option<Box<Artist>>,
    pub trailer: Option<crate::models::common::TrailerInfo>,
}

/// Donation campaign goal.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ArtistDonationGoal {
    pub title: Option<String>,
}

/// Artist donation/tip information.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ArtistDonationInfo {
    pub title: Option<String>,
    pub url: Option<String>,
}

/// Payload of a donation item.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ArtistDonationData {
    pub tip_url: Option<String>,
    pub artist: Option<Box<Artist>>,
    pub goal: Option<ArtistDonationGoal>,
}

/// Single donation item.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ArtistDonationItem {
    pub r#type: Option<String>,
    pub data: Option<ArtistDonationData>,
}

/// List of artist donations.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ArtistDonations {
    pub donations: Option<Vec<ArtistDonationItem>>,
}

/// Payload of a clip item of an artist.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ArtistClipData {
    pub clip: Option<crate::models::clip::Clip>,
    pub artists: Option<Vec<Artist>>,
}

/// Single clip item of an artist.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ArtistClipItem {
    pub r#type: Option<String>,
    pub data: Option<ArtistClipData>,
}

/// Paged list of artist clips.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ArtistClips {
    pub items: Option<Vec<ArtistClipItem>>,
    pub pager: Option<crate::models::common::Pager>,
}

/// Similar artists block.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ArtistSimilar {
    pub artist: Option<Box<Artist>>,
    pub similar_artists: Option<Vec<Artist>>,
}

/// Full artist about information.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ArtistAbout {
    pub artist: Option<Box<Artist>>,
    pub stats: Option<Stats>,
    pub description: Option<String>,
    pub links: Option<Vec<ArtistLink>>,
    pub covers: Option<Vec<crate::models::common::Cover>>,
    pub artist_type: Option<String>,
}

/// Paged list of artist albums.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ArtistAlbums {
    pub albums: Option<Vec<crate::models::album::Album>>,
    pub pager: Option<crate::models::common::Pager>,
}

/// Paged list of artist tracks.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ArtistTracks {
    pub tracks: Option<Vec<crate::models::track::Track>>,
    pub pager: Option<crate::models::common::Pager>,
}

/// Artist info block (likes, stats, trailer, covers).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ArtistInfo {
    pub artist: Option<Box<Artist>>,
    #[serde(default, deserialize_with = "crate::models::de::opt_i64")]
    pub likes_count: Option<i64>,
    pub stats: Option<Stats>,
    pub trailer: Option<ArtistTrailerStatus>,
    pub covers: Option<Vec<crate::models::common::Cover>>,
    pub description: Option<String>,
    pub artist_type: Option<String>,
}

/// Artist landing skeleton.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ArtistSkeleton {
    #[serde(default, deserialize_with = "crate::models::de::opt_id")]
    pub id: Option<String>,
    pub title: Option<String>,
    pub blocks: Option<Vec<crate::models::skeleton::SkeletonBlock>>,
}

/// Upcoming album of an artist.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct UpcomingAlbum {
    #[serde(default, deserialize_with = "crate::models::de::opt_id")]
    pub id: Option<String>,
    pub title: Option<String>,
    pub r#type: Option<String>,
    pub release_date: Option<String>,
    #[serde(default, deserialize_with = "crate::models::de::opt_i64")]
    pub milliseconds_until_release: Option<i64>,
    pub cover_uri: Option<String>,
    #[serde(default, deserialize_with = "crate::models::de::opt_bool")]
    pub presaved: Option<bool>,
    pub artists: Vec<Artist>,
    pub content_restrictions: Option<crate::models::common::ContentRestrictions>,
}

/// Vinyl release offer.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Vinyl {
    pub url: Option<String>,
    pub title: Option<String>,
    #[serde(default, deserialize_with = "crate::models::de::opt_i64")]
    pub year: Option<i64>,
    #[serde(default, deserialize_with = "crate::models::de::opt_i64")]
    pub price: Option<i64>,
    pub media: Option<String>,
    #[serde(default, deserialize_with = "crate::models::de::opt_id")]
    pub offer_id: Option<String>,
    #[serde(default, deserialize_with = "crate::models::de::opt_ids")]
    pub artist_ids: Option<Vec<String>>,
    pub picture: Option<String>,
}

/// Brief artist card with releases, clips and backgrounds.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct BriefInfo {
    pub artist: Option<Box<Artist>>,
    pub albums: Option<Vec<crate::models::album::Album>>,
    pub playlists: Option<Vec<crate::models::playlist::Playlist>>,
    pub also_albums: Option<Vec<crate::models::album::Album>>,
    #[serde(default, deserialize_with = "crate::models::de::opt_ids")]
    pub last_release_ids: Option<Vec<String>>,
    pub last_releases: Option<Vec<crate::models::album::Album>>,
    pub popular_tracks: Option<Vec<crate::models::track::Track>>,
    pub similar_artists: Option<Vec<Artist>>,
    pub all_covers: Option<Vec<crate::models::common::Cover>>,
    pub concerts: Option<serde_json::Value>,
    pub videos: Option<Vec<crate::models::common::Video>>,
    pub vinyls: Option<Vec<Vinyl>>,
    #[serde(default, deserialize_with = "crate::models::de::opt_bool")]
    pub has_promotions: Option<bool>,
    pub playlist_ids: Option<Vec<crate::models::playlist::PlaylistId>>,
    pub stats: Option<Stats>,
    pub tracks_in_chart: Vec<crate::models::landing::Chart>,
    pub action_button: Option<crate::models::album::AlbumActionButton>,
    pub background_image_url: Option<String>,
    pub background_video_id: Option<String>,
    pub background_video_url: Option<String>,
    pub bandlink_scanner_link: Option<ArtistLink>,
    pub clips: Vec<crate::models::clip::Clip>,
    pub custom_wave: Option<crate::models::playlist::CustomWave>,
    #[serde(default, deserialize_with = "crate::models::de::opt_bool")]
    pub has_trailer: Option<bool>,
    pub links: Vec<ArtistLink>,
    pub upcoming_album: Option<UpcomingAlbum>,
}

/// Artist with metadata, covers, stats and links.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Artist {
    #[serde(default, deserialize_with = "crate::models::de::opt_id")]
    pub id: Option<String>,
    pub error: Option<String>,
    pub reason: Option<String>,
    pub name: Option<String>,
    pub cover: Option<crate::models::common::Cover>,
    #[serde(default, deserialize_with = "crate::models::de::opt_bool")]
    pub various: Option<bool>,
    #[serde(default, deserialize_with = "crate::models::de::opt_bool")]
    pub composer: Option<bool>,
    pub genres: Option<Vec<String>>,
    pub og_image: Option<String>,
    pub op_image: Option<String>,
    pub no_pictures_from_search: Option<serde_json::Value>,
    pub counts: Option<Counts>,
    #[serde(default, deserialize_with = "crate::models::de::opt_bool")]
    pub available: Option<bool>,
    pub ratings: Option<Ratings>,
    pub links: Option<Vec<Link>>,
    #[serde(default, deserialize_with = "crate::models::de::opt_bool")]
    pub tickets_available: Option<bool>,
    #[serde(default, deserialize_with = "crate::models::de::opt_i64")]
    pub likes_count: Option<i64>,
    pub popular_tracks: Option<Vec<crate::models::track::Track>>,
    pub regions: Option<Vec<String>>,
    pub decomposed: Option<Vec<serde_json::Value>>,
    pub full_names: Option<serde_json::Value>,
    pub hand_made_description: Option<String>,
    pub description: Option<Description>,
    pub countries: Option<Vec<String>>,
    pub en_wikipedia_link: Option<String>,
    pub db_aliases: Option<Vec<String>>,
    pub aliases: Option<serde_json::Value>,
    pub init_date: Option<String>,
    pub end_date: Option<String>,
    pub ya_money_id: Option<String>,
    pub disclaimers: Option<Vec<String>>,
    pub content_restrictions: Option<crate::models::common::ContentRestrictions>,
    pub cutout_cover: Option<crate::models::common::Cover>,
    pub derived_colors: Option<crate::models::common::CoverDerivedColors>,
    pub action_button: Option<crate::models::album::AlbumActionButton>,
    pub donation_info: Option<ArtistDonationInfo>,
    #[serde(default, deserialize_with = "crate::models::de::opt_bool")]
    pub has_trailer: Option<bool>,
    pub trailer: Option<ArtistTrailerStatus>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn artist_deserialize() {
        let json = r#"{
            "id": 10987,
            "name": "Elvis Presley",
            "various": false,
            "composer": 0,
            "ogImage": "",
            "ticketsAvailable": false,
            "likesCount": 657469,
            "initDate": "1935-01-08",
            "yaMoneyId": "4100170623944",
            "disclaimers": ["foreignAgent"],
            "hasTrailer": true,
            "counts": {"tracks": 1251, "directAlbums": 33, "alsoAlbums": 200, "alsoTracks": 1254},
            "ratings": {"month": 42, "week": 41, "day": 40},
            "links": [{"title": "tickets", "href": "https://example.com", "type": "tickets"}],
            "description": {"text": "Elvis Aaron Presley", "uri": "artist-description"},
            "popularTracks": [{"id": "123", "title": "Blue Suede Shoes"}],
            "decomposed": ["Elvis", {"id": 1, "name": "Presley"}]
        }"#;
        let a: Artist = serde_json::from_str(json).unwrap();
        assert_eq!(a.id.as_deref(), Some("10987"));
        assert_eq!(a.name.as_deref(), Some("Elvis Presley"));
        assert_eq!(a.composer, Some(false));
        assert_eq!(a.likes_count, Some(657469));
        assert_eq!(a.counts.unwrap().tracks, Some(1251));
        assert_eq!(a.ratings.unwrap().week, Some(41));
        assert_eq!(a.links.unwrap()[0].r#type.as_deref(), Some("tickets"));
        assert_eq!(a.description.unwrap().uri.as_deref(), Some("artist-description"));
        assert_eq!(a.decomposed.unwrap().len(), 2);
    }

    #[test]
    fn brief_info_deserialize() {
        let json = r#"{
            "artist": {"id": 1, "name": "Kino"},
            "albums": [], "playlists": [], "alsoAlbums": [], "lastReleaseIds": [1, 2],
            "lastReleases": [], "popularTracks": [], "similarArtists": [], "allCovers": [],
            "concerts": {}, "videos": [], "vinyls": [{"url": "u", "title": "t", "year": 2019,
            "price": 100, "media": "lp", "offerId": 5, "artistIds": [1]}],
            "hasPromotions": false, "playlistIds": [{"uid": 1, "kind": 2}],
            "stats": {"lastMonthListeners": 10, "lastMonthListenersDelta": -1},
            "backgroundImageUrl": "bg.jpg", "hasTrailer": 1,
            "upcomingAlbum": {"id": 7, "title": "Next", "presaved": true, "artists": [{"name": "A"}]}
        }"#;
        let b: BriefInfo = serde_json::from_str(json).unwrap();
        assert_eq!(b.artist.unwrap().name.as_deref(), Some("Kino"));
        assert_eq!(b.vinyls.as_ref().unwrap()[0].offer_id.as_deref(), Some("5"));
        assert_eq!(b.vinyls.as_ref().unwrap()[0].artist_ids.clone(), Some(vec!["1".to_string()]));
        assert_eq!(b.stats.unwrap().last_month_listeners_delta, Some(-1));
        assert_eq!(b.has_trailer, Some(true));
        assert_eq!(b.background_image_url.as_deref(), Some("bg.jpg"));
        let up = b.upcoming_album.unwrap();
        assert_eq!(up.id.as_deref(), Some("7"));
        assert_eq!(up.artists.len(), 1);
    }

    #[test]
    fn misc_deserialize() {
        let a: ArtistAlbums =
            serde_json::from_str(r#"{"albums": [{"id": 1}], "pager": {"total": 1}}"#).unwrap();
        assert_eq!(a.albums.unwrap().len(), 1);
        let s: ArtistSkeleton = serde_json::from_str(r#"{"id": "1", "blocks": []}"#).unwrap();
        assert_eq!(s.id.as_deref(), Some("1"));
        let ab: ArtistAbout = serde_json::from_str(
            r#"{"artist": {"id": 2}, "stats": {"lastMonthListeners": 3}, "artistType": "musician"}"#,
        )
        .unwrap();
        assert_eq!(ab.artist_type.as_deref(), Some("musician"));
        assert_eq!(ab.stats.unwrap().last_month_listeners, Some(3));
    }
}
