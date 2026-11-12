//! Port of `yandex_music/_client/metatags.py`.

use crate::http::{from_value_opt, Params};
use crate::models::metatag::{Metatag, MetatagAlbums, MetatagArtists, MetatagPlaylists, Metatags};

use super::Client;

impl Client {
    /// Get the metatag tree (`GET /landing3/metatags`).
    pub async fn metatags(&self) -> crate::Result<Option<Metatags>> {
        let v = self.http.get(&self.url("/landing3/metatags"), &[]).await?;
        from_value_opt(v)
    }

    /// Get metatag info (`GET /metatags/{id}`).
    #[allow(clippy::too_many_arguments)]
    pub async fn metatag(
        &self,
        metatag_id: &str,
        tracks_count: Option<i64>,
        artists_count: Option<i64>,
        composers_count: Option<i64>,
        albums_count: Option<i64>,
        promotions_count: Option<i64>,
        features_count: Option<i64>,
        playlists_count: Option<i64>,
        concerts_count: Option<i64>,
        tracks_sort_by: Option<&str>,
        albums_sort_by: Option<&str>,
        with_likes_count: Option<bool>,
    ) -> crate::Result<Option<Metatag>> {
        let mut p: Vec<(&str, String)> = Vec::new();
        let nums = [
            ("tracksCount", tracks_count),
            ("artistsCount", artists_count),
            ("composersCount", composers_count),
            ("albumsCount", albums_count),
            ("promotionsCount", promotions_count),
            ("featuresCount", features_count),
            ("playlistsCount", playlists_count),
            ("concertsCount", concerts_count),
        ];
        for (k, v) in nums {
            if let Some(v) = v {
                p.push((k, v.to_string()));
            }
        }
        if let Some(v) = tracks_sort_by {
            p.push(("tracksSortBy", v.to_owned()));
        }
        if let Some(v) = albums_sort_by {
            p.push(("albumsSortBy", v.to_owned()));
        }
        if let Some(v) = with_likes_count {
            p.push(("withLikesCount", v.to_string()));
        }
        let v = self
            .http
            .get(&self.url(&format!("/metatags/{metatag_id}")), &p as Params)
            .await?;
        from_value_opt(v)
    }

    /// Get metatag albums (`GET /metatags/{id}/albums`).
    pub async fn metatag_albums(
        &self,
        metatag_id: &str,
        period: Option<&str>,
        sort_by: Option<&str>,
        offset: i64,
        limit: i64,
    ) -> crate::Result<Option<MetatagAlbums>> {
        let mut p: Vec<(&str, String)> =
            vec![("offset", offset.to_string()), ("limit", limit.to_string())];
        if let Some(v) = period {
            p.push(("period", v.to_owned()));
        }
        if let Some(v) = sort_by {
            p.push(("sortBy", v.to_owned()));
        }
        let v = self
            .http
            .get(&self.url(&format!("/metatags/{metatag_id}/albums")), &p as Params)
            .await?;
        from_value_opt(v)
    }

    /// Get metatag artists (`GET /metatags/{id}/artists`); `period` is required.
    pub async fn metatag_artists(
        &self,
        metatag_id: &str,
        period: &str,
        sort_by: Option<&str>,
        offset: i64,
        limit: i64,
        tracks_per_artist: Option<i64>,
    ) -> crate::Result<Option<MetatagArtists>> {
        let mut p: Vec<(&str, String)> = vec![
            ("period", period.to_owned()),
            ("offset", offset.to_string()),
            ("limit", limit.to_string()),
        ];
        if let Some(v) = sort_by {
            p.push(("sortBy", v.to_owned()));
        }
        if let Some(v) = tracks_per_artist {
            p.push(("tracksPerArtist", v.to_string()));
        }
        let v = self
            .http
            .get(&self.url(&format!("/metatags/{metatag_id}/artists")), &p as Params)
            .await?;
        from_value_opt(v)
    }

    /// Get metatag playlists (`GET /metatags/{id}/playlists`).
    pub async fn metatag_playlists(
        &self,
        metatag_id: &str,
        sort_by: Option<&str>,
        offset: i64,
        limit: i64,
        with_likes_count: Option<bool>,
    ) -> crate::Result<Option<MetatagPlaylists>> {
        let mut p: Vec<(&str, String)> =
            vec![("offset", offset.to_string()), ("limit", limit.to_string())];
        if let Some(v) = sort_by {
            p.push(("sortBy", v.to_owned()));
        }
        if let Some(v) = with_likes_count {
            p.push(("withLikesCount", v.to_string()));
        }
        let v = self
            .http
            .get(&self.url(&format!("/metatags/{metatag_id}/playlists")), &p as Params)
            .await?;
        from_value_opt(v)
    }
}
