//! Port of `yandex_music/_client/disclaimers.py`.

use super::Client;
use crate::error::Result;
use crate::http::from_value_opt;
use crate::models::common::Disclaimer;

impl Client {
    async fn get_disclaimer(&self, entity_type: &str, entity_id: &str) -> Result<Option<Disclaimer>> {
        let url = self.url(&format!("/{entity_type}/{entity_id}/disclaimer"));
        let result = self.http.get(&url, &[]).await?;
        from_value_opt(result)
    }

    /// Get the content disclaimer of a track.
    pub async fn tracks_disclaimer<S: AsRef<str>>(&self, track_id: S) -> Result<Option<Disclaimer>> {
        self.get_disclaimer("tracks", track_id.as_ref()).await
    }

    /// Get the content disclaimer of a clip.
    pub async fn clips_disclaimer<S: AsRef<str>>(&self, clip_id: S) -> Result<Option<Disclaimer>> {
        self.get_disclaimer("clips", clip_id.as_ref()).await
    }

    /// Get the content disclaimer of an album.
    pub async fn albums_disclaimer<S: AsRef<str>>(&self, album_id: S) -> Result<Option<Disclaimer>> {
        self.get_disclaimer("albums", album_id.as_ref()).await
    }

    /// Get the content disclaimer of an artist.
    pub async fn artists_disclaimer<S: AsRef<str>>(&self, artist_id: S) -> Result<Option<Disclaimer>> {
        self.get_disclaimer("artists", artist_id.as_ref()).await
    }
}
