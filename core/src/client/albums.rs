//! Port of `yandex_music/_client/albums.py`.

use crate::http::{from_value, from_value_opt};
use crate::models::album::{Album, AlbumSimilarEntities, AlbumTrailer};

use super::Client;

impl Client {
    /// Get album(s) by id (`GET /albums`, batched via `get_list_raw`).
    pub async fn albums<S: AsRef<str>>(&self, album_ids: &[S]) -> crate::Result<Vec<Album>> {
        let v = self.get_list_raw("album", album_ids).await?;
        from_value(v)
    }

    /// Get album with its tracks (`GET /albums/{id}/with-tracks`).
    pub async fn albums_with_tracks(&self, album_id: &str) -> crate::Result<Option<Album>> {
        let v = self.http.get(&self.url(&format!("/albums/{album_id}/with-tracks")), &[]).await?;
        from_value_opt(v)
    }

    /// Get similar entities for an album (`GET /albums/{id}/similar-entities`).
    pub async fn albums_similar_entities(
        &self,
        album_id: &str,
    ) -> crate::Result<Option<AlbumSimilarEntities>> {
        let v = self
            .http
            .get(&self.url(&format!("/albums/{album_id}/similar-entities")), &[])
            .await?;
        from_value_opt(v)
    }

    /// Get an album trailer (`GET /albums/{id}/trailer`).
    pub async fn albums_trailer(&self, album_id: &str) -> crate::Result<Option<AlbumTrailer>> {
        let v = self.http.get(&self.url(&format!("/albums/{album_id}/trailer")), &[]).await?;
        from_value_opt(v)
    }
}
