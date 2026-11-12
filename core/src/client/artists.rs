//! Port of `yandex_music/_client/artists.py`.


use super::Client;
use crate::error::Result;
use crate::http::{from_value, from_value_opt};
use crate::models::artist::{
    Artist, ArtistAbout, ArtistAlbums, ArtistClips, ArtistDonations, ArtistInfo, ArtistLinks, ArtistSimilar,
    ArtistSkeleton, ArtistTracks, ArtistTrailer, BriefInfo,
};

impl Client {
    /// Get artist(s) by id(s) (`POST /artists`).
    pub async fn artists<S: AsRef<str>>(&self, artist_ids: &[S]) -> Result<Vec<Artist>> {
        let raw = self.get_list_raw("artist", artist_ids).await?;
        from_value(raw)
    }

    /// Get brief artist info (`GET /artists/{id}/brief-info`).
    pub async fn artists_brief_info(&self, artist_id: &str) -> Result<Option<BriefInfo>> {
        let url = self.url(&format!("/artists/{artist_id}/brief-info"));
        from_value_opt(self.http.get(&url, &[]).await?)
    }

    /// Get artist tracks page (`GET /artists/{id}/tracks`).
    pub async fn artists_tracks(&self, artist_id: &str, page: u32, page_size: u32) -> Result<Option<ArtistTracks>> {
        let url = self.url(&format!("/artists/{artist_id}/tracks"));
        let params = [("page", page.to_string()), ("page-size", page_size.to_string())];
        from_value_opt(self.http.get(&url, &params).await?)
    }

    /// Get artist direct albums (`GET /artists/{id}/direct-albums`).
    pub async fn artists_direct_albums(
        &self,
        artist_id: &str,
        page: u32,
        page_size: u32,
        sort_by: &str,
    ) -> Result<Option<ArtistAlbums>> {
        let url = self.url(&format!("/artists/{artist_id}/direct-albums"));
        let params = [
            ("sort-by", sort_by.to_owned()),
            ("page", page.to_string()),
            ("page-size", page_size.to_string()),
        ];
        from_value_opt(self.http.get(&url, &params).await?)
    }

    /// Get similar artists (`GET /artists/{id}/similar`).
    pub async fn artists_similar(&self, artist_id: &str) -> Result<Option<ArtistSimilar>> {
        let url = self.url(&format!("/artists/{artist_id}/similar"));
        from_value_opt(self.http.get(&url, &[]).await?)
    }

    /// Get artist links (`GET /artists/{id}/artist-links`).
    pub async fn artists_links(&self, artist_id: &str) -> Result<Option<ArtistLinks>> {
        let url = self.url(&format!("/artists/{artist_id}/artist-links"));
        from_value_opt(self.http.get(&url, &[]).await?)
    }

    /// Get albums the artist participated in (`GET /artists/{id}/also-albums`).
    pub async fn artists_also_albums(
        &self,
        artist_id: &str,
        page: u32,
        page_size: u32,
        sort_by: &str,
    ) -> Result<Option<ArtistAlbums>> {
        let url = self.url(&format!("/artists/{artist_id}/also-albums"));
        let params = [
            ("sort-by", sort_by.to_owned()),
            ("page", page.to_string()),
            ("page-size", page_size.to_string()),
        ];
        from_value_opt(self.http.get(&url, &params).await?)
    }

    /// Get artist discography albums (`GET /artists/{id}/discography-albums`).
    pub async fn artists_discography_albums(
        &self,
        artist_id: &str,
        page: u32,
        page_size: u32,
        sort_by: &str,
    ) -> Result<Option<ArtistAlbums>> {
        let url = self.url(&format!("/artists/{artist_id}/discography-albums"));
        let params = [
            ("sort-by", sort_by.to_owned()),
            ("page", page.to_string()),
            ("page-size", page_size.to_string()),
        ];
        from_value_opt(self.http.get(&url, &params).await?)
    }

    /// Get safe artist albums (`GET /artists/{id}/safe-direct-albums`).
    pub async fn artists_safe_direct_albums(
        &self,
        artist_id: &str,
        sort_by: &str,
        sort_order: &str,
        limit: u32,
    ) -> Result<Option<ArtistAlbums>> {
        let url = self.url(&format!("/artists/{artist_id}/safe-direct-albums"));
        let params = [
            ("sort-by", sort_by.to_owned()),
            ("sort-order", sort_order.to_owned()),
            ("limit", limit.to_string()),
        ];
        from_value_opt(self.http.get(&url, &params).await?)
    }

    /// Get artist track ids (`GET /artists/{id}/track-ids`).
    pub async fn artists_track_ids(&self, artist_id: &str, page: u32, page_size: u32) -> Result<Vec<String>> {
        let url = self.url(&format!("/artists/{artist_id}/track-ids"));
        let params = [("page", page.to_string()), ("page-size", page_size.to_string())];
        let raw = self.http.get(&url, &params).await?;
        Ok(raw
            .as_array()
            .map(|a| a.iter().filter_map(|v| v.as_str().map(str::to_owned)).collect())
            .unwrap_or_default())
    }

    /// Get "about artist" info (`GET /artists/{id}/about-artist`).
    pub async fn artists_about(&self, artist_id: &str) -> Result<Option<ArtistAbout>> {
        let url = self.url(&format!("/artists/{artist_id}/about-artist"));
        from_value_opt(self.http.get(&url, &[]).await?)
    }

    /// Get artist clips (`GET /artists/{id}/blocks/artist-clips`).
    pub async fn artists_clips(&self, artist_id: &str) -> Result<Option<ArtistClips>> {
        let url = self.url(&format!("/artists/{artist_id}/blocks/artist-clips"));
        from_value_opt(self.http.get(&url, &[]).await?)
    }

    /// Get artist donations (`GET /artists/{id}/blocks/artist-donation`).
    pub async fn artists_donation(&self, artist_id: &str) -> Result<Option<ArtistDonations>> {
        let url = self.url(&format!("/artists/{artist_id}/blocks/artist-donation"));
        from_value_opt(self.http.get(&url, &[]).await?)
    }

    /// Get detailed artist info (`GET /artists/{id}/info`).
    pub async fn artists_info(&self, artist_id: &str) -> Result<Option<ArtistInfo>> {
        let url = self.url(&format!("/artists/{artist_id}/info"));
        from_value_opt(self.http.get(&url, &[]).await?)
    }

    /// Get artist page skeleton (`GET /artists/{id}/skeletons/{skeleton_id}`).
    pub async fn artists_skeleton(&self, artist_id: &str, skeleton_id: &str) -> Result<Option<ArtistSkeleton>> {
        let url = self.url(&format!("/artists/{artist_id}/skeletons/{skeleton_id}"));
        from_value_opt(self.http.get(&url, &[]).await?)
    }

    /// Get artist trailer (`GET /artists/{id}/trailer`).
    pub async fn artists_trailer(&self, artist_id: &str) -> Result<Option<ArtistTrailer>> {
        let url = self.url(&format!("/artists/{artist_id}/trailer"));
        from_value_opt(self.http.get(&url, &[]).await?)
    }
}
