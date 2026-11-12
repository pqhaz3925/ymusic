//! Port of `yandex_music/_client/concerts.py`.

use crate::error::Result;
use crate::http::{from_value_opt, join};
use crate::models::concert::{
    ArtistConcerts, ConcertFeed, ConcertInfo, ConcertLocations, ConcertSkeleton, ConcertTabConfig,
};

use super::Client;

impl Client {
    /// Get an artist's concerts (`GET /artists/{artist_id}/concerts`).
    pub async fn artists_concerts<S: AsRef<str>>(&self, artist_id: S) -> Result<Option<ArtistConcerts>> {
        let url = self.url(&format!("/artists/{}/concerts", artist_id.as_ref()));
        from_value_opt(self.http.get(&url, &[]).await?)
    }

    /// Get information about a concert (`GET /concerts/{concert_id}/info`).
    pub async fn concert_info(&self, concert_id: &str) -> Result<Option<ConcertInfo>> {
        let url = self.url(&format!("/concerts/{concert_id}/info"));
        from_value_opt(self.http.get(&url, &[]).await?)
    }

    /// Get a concert page skeleton (`GET /concerts/{concert_id}/skeletons/{skeleton_id}`).
    pub async fn concert_skeleton(
        &self,
        concert_id: &str,
        skeleton_id: &str,
    ) -> Result<Option<ConcertSkeleton>> {
        let url = self.url(&format!("/concerts/{concert_id}/skeletons/{skeleton_id}"));
        from_value_opt(self.http.get(&url, &[]).await?)
    }

    /// Get the concerts feed, optionally filtered by locations (`GET /concerts/feed`).
    pub async fn concerts_feed<S: AsRef<str>>(&self, locations: Option<&[S]>) -> Result<Option<ConcertFeed>> {
        let url = self.url("/concerts/feed");
        let query = match locations {
            Some(l) if !l.is_empty() => vec![("locations", join(l))],
            _ => vec![],
        };
        from_value_opt(self.http.get(&url, &query).await?)
    }

    /// Get the locations available for filtering concerts (`GET /concerts/locations`).
    pub async fn concerts_locations(&self) -> Result<Option<ConcertLocations>> {
        let url = self.url("/concerts/locations");
        from_value_opt(self.http.get(&url, &[]).await?)
    }

    /// Get the concerts tab configuration (`GET /concerts/tab-config`).
    pub async fn concerts_tab_config(&self) -> Result<Option<ConcertTabConfig>> {
        let url = self.url("/concerts/tab-config");
        from_value_opt(self.http.get(&url, &[]).await?)
    }
}
