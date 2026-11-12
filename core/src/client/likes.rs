//! Port of `yandex_music/_client/likes.py`.

use serde_json::Value;

use super::Client;
use crate::error::Result;
use crate::http::{from_value, from_value_opt, is_ok, join, Params};
use crate::models::artist::Artist;
use crate::models::clip::ClipsWillLike;
use crate::models::common::{Like, TracksList};

impl Client {
    /// Like/dislike add/remove for `object_type` (`track`/`artist`/`playlist`/`album`) under `section` (`likes`/`dislikes`).
    async fn like_action<S: AsRef<str>>(
        &self,
        section: &str,
        object_type: &str,
        ids: &[S],
        remove: bool,
        user_id: Option<&str>,
    ) -> Result<bool> {
        let uid = self.uid(user_id)?;
        let action = if remove { "remove" } else { "add-multiple" };
        let url = self.url(&format!("/users/{uid}/{section}/{object_type}s/{action}"));
        let key = format!("{object_type}-ids");
        let v = self.http.post(&url, &[(key.as_str(), join(ids))]).await?;
        if object_type == "track" {
            Ok(v.get("revision").is_some())
        } else {
            Ok(is_ok(&v))
        }
    }

    /// Get likes/dislikes list of `object_type` (`likes` or `dislikes` section) as raw value.
    async fn get_likes_raw(&self, section: &str, object_type: &str, user_id: Option<&str>, params: Params<'_>) -> Result<Value> {
        let uid = self.uid(user_id)?;
        let url = self.url(&format!("/users/{uid}/{section}/{object_type}s"));
        self.http.get(&url, params).await
    }

    /// Mark track(s) as liked.
    pub async fn users_likes_tracks_add<S: AsRef<str>>(&self, track_ids: &[S], user_id: Option<&str>) -> Result<bool> {
        self.like_action("likes", "track", track_ids, false, user_id).await
    }

    /// Unmark track(s) as liked.
    pub async fn users_likes_tracks_remove<S: AsRef<str>>(&self, track_ids: &[S], user_id: Option<&str>) -> Result<bool> {
        self.like_action("likes", "track", track_ids, true, user_id).await
    }

    /// Mark artist(s) as liked.
    pub async fn users_likes_artists_add<S: AsRef<str>>(&self, artist_ids: &[S], user_id: Option<&str>) -> Result<bool> {
        self.like_action("likes", "artist", artist_ids, false, user_id).await
    }

    /// Unmark artist(s) as liked.
    pub async fn users_likes_artists_remove<S: AsRef<str>>(&self, artist_ids: &[S], user_id: Option<&str>) -> Result<bool> {
        self.like_action("likes", "artist", artist_ids, true, user_id).await
    }

    /// Mark playlist(s) (`owner_id:playlist_id`) as liked.
    pub async fn users_likes_playlists_add<S: AsRef<str>>(&self, playlist_ids: &[S], user_id: Option<&str>) -> Result<bool> {
        self.like_action("likes", "playlist", playlist_ids, false, user_id).await
    }

    /// Unmark playlist(s) as liked.
    pub async fn users_likes_playlists_remove<S: AsRef<str>>(&self, playlist_ids: &[S], user_id: Option<&str>) -> Result<bool> {
        self.like_action("likes", "playlist", playlist_ids, true, user_id).await
    }

    /// Mark album(s) as liked.
    pub async fn users_likes_albums_add<S: AsRef<str>>(&self, album_ids: &[S], user_id: Option<&str>) -> Result<bool> {
        self.like_action("likes", "album", album_ids, false, user_id).await
    }

    /// Unmark album(s) as liked.
    pub async fn users_likes_albums_remove<S: AsRef<str>>(&self, album_ids: &[S], user_id: Option<&str>) -> Result<bool> {
        self.like_action("likes", "album", album_ids, true, user_id).await
    }

    /// Get liked tracks.
    pub async fn users_likes_tracks(&self, user_id: Option<&str>, if_modified_since_revision: i64) -> Result<Option<TracksList>> {
        let params = [("if-modified-since-revision", if_modified_since_revision.to_string())];
        let v = self.get_likes_raw("likes", "track", user_id, &params).await?;
        Ok(match v.get("library") {
            Some(lib) => Some(from_value(lib.clone())?),
            None => None,
        })
    }

    /// Get liked albums.
    pub async fn users_likes_albums(&self, user_id: Option<&str>, rich: bool) -> Result<Vec<Like>> {
        let params = [("rich", rich.to_string())];
        from_value(self.get_likes_raw("likes", "album", user_id, &params).await?)
    }

    /// Get liked artists.
    pub async fn users_likes_artists(&self, user_id: Option<&str>, with_timestamps: bool) -> Result<Vec<Like>> {
        let params = [("with-timestamps", with_timestamps.to_string())];
        from_value(self.get_likes_raw("likes", "artist", user_id, &params).await?)
    }

    /// Get liked playlists.
    pub async fn users_likes_playlists(&self, user_id: Option<&str>) -> Result<Vec<Like>> {
        from_value(self.get_likes_raw("likes", "playlist", user_id, &[]).await?)
    }

    /// Get disliked tracks.
    pub async fn users_dislikes_tracks(&self, user_id: Option<&str>, if_modified_since_revision: i64) -> Result<Option<TracksList>> {
        let params = [("if_modified_since_revision", if_modified_since_revision.to_string())];
        let v = self.get_likes_raw("dislikes", "track", user_id, &params).await?;
        Ok(match v.get("library") {
            Some(lib) => Some(from_value(lib.clone())?),
            None => None,
        })
    }

    /// Mark track(s) as disliked.
    pub async fn users_dislikes_tracks_add<S: AsRef<str>>(&self, track_ids: &[S], user_id: Option<&str>) -> Result<bool> {
        self.like_action("dislikes", "track", track_ids, false, user_id).await
    }

    /// Unmark track(s) as disliked.
    pub async fn users_dislikes_tracks_remove<S: AsRef<str>>(&self, track_ids: &[S], user_id: Option<&str>) -> Result<bool> {
        self.like_action("dislikes", "track", track_ids, true, user_id).await
    }

    /// Get disliked artists.
    pub async fn users_dislikes_artists(&self, user_id: Option<&str>) -> Result<Vec<Artist>> {
        from_value(self.get_likes_raw("dislikes", "artist", user_id, &[]).await?)
    }

    /// Mark artist as disliked.
    pub async fn users_dislikes_artists_add(&self, artist_id: &str, user_id: Option<&str>) -> Result<bool> {
        self.like_action("dislikes", "artist", &[artist_id], false, user_id).await
    }

    /// Unmark artist as disliked.
    pub async fn users_dislikes_artists_remove(&self, artist_id: &str, user_id: Option<&str>) -> Result<bool> {
        self.like_action("dislikes", "artist", &[artist_id], true, user_id).await
    }

    /// Get liked clips (paged).
    pub async fn users_likes_clips(&self, user_id: Option<&str>, page: i64, page_size: i64) -> Result<Option<ClipsWillLike>> {
        let uid = self.uid(user_id)?;
        let url = self.url(&format!("/users/{uid}/likes/clips"));
        let params = [("page", page.to_string()), ("pageSize", page_size.to_string())];
        from_value_opt(self.http.get(&url, &params).await?)
    }

    /// Mark clip as liked.
    pub async fn users_likes_clips_add(&self, clip_id: &str, user_id: Option<&str>) -> Result<bool> {
        let uid = self.uid(user_id)?;
        let url = self.url(&format!("/users/{uid}/likes/clips/add"));
        let v = self.http.post(&url, &[("clip-id", clip_id.to_owned())]).await?;
        Ok(v.is_object() || is_ok(&v))
    }

    /// Unmark clip as liked.
    pub async fn users_likes_clips_remove(&self, clip_id: &str, user_id: Option<&str>) -> Result<bool> {
        let uid = self.uid(user_id)?;
        let url = self.url(&format!("/users/{uid}/likes/clips/{clip_id}/remove"));
        let v = self.http.post(&url, &[]).await?;
        Ok(v.is_object() || is_ok(&v))
    }
}
