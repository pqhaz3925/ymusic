//! Port of `yandex_music/_client/search.py`.

use crate::http::{from_value_opt, Params};
use crate::models::search::{Search, Suggestions};

use super::Client;

impl Client {
    /// Search by query and type (`GET /search`); type_: all, artist, user, album, playlist, track, podcast, podcast_episode.
    pub async fn search(
        &self,
        text: &str,
        nocorrect: bool,
        type_: &str,
        page: i64,
        playlist_in_best: bool,
    ) -> crate::Result<Option<Search>> {
        let url = self.url("/search");
        let params: Params<'_> = &[
            ("text", text.to_owned()),
            ("nocorrect", nocorrect.to_string()),
            ("type", type_.to_owned()),
            ("page", page.to_string()),
            ("playlist-in-best", playlist_in_best.to_string()),
        ];
        let v = self.http.get(&url, params).await?;
        from_value_opt(v)
    }

    /// Get search suggestions for a partial query (`GET /search/suggest`).
    pub async fn search_suggest(&self, part: &str) -> crate::Result<Option<Suggestions>> {
        let url = self.url("/search/suggest");
        let v = self.http.get(&url, &[("part", part.to_owned())]).await?;
        from_value_opt(v)
    }
}
