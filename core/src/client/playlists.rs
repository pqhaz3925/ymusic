//! Port of `yandex_music/_client/playlists.py` and `yandex_music/utils/difference.py`.

use serde_json::{json, Value};

use super::Client;
use crate::error::Result;
use crate::http::{from_value_opt, is_ok, join};
use crate::models::account::UserSettings;
use crate::models::feed::GeneratedPlaylist;
use crate::models::playlist::{
    Playlist, PlaylistRecommendations, PlaylistSimilarEntities, PlaylistTrailer, PlaylistsList,
};

/// Port of `utils.difference.Difference`: a list of insert/delete operations for a playlist.
#[derive(Debug, Clone, Default)]
pub struct Difference {
    /// Accumulated operations.
    pub operations: Vec<Value>,
}

impl Difference {
    pub fn new() -> Self {
        Self::default()
    }

    /// Add a delete operation for the index range `from..to`.
    pub fn add_delete(mut self, from: i64, to: i64) -> Self {
        self.operations.push(json!({"op": "delete", "from": from, "to": to}));
        self
    }

    /// Add an insert operation at index `at`; `tracks` are `(track_id, album_id)` pairs.
    pub fn add_insert<T: AsRef<str>, A: AsRef<str>>(mut self, at: i64, tracks: &[(T, A)]) -> Self {
        let tracks: Vec<Value> = tracks
            .iter()
            .map(|(t, a)| json!({"id": t.as_ref(), "albumId": a.as_ref()}))
            .collect();
        self.operations.push(json!({"op": "insert", "at": at, "tracks": tracks}));
        self
    }

    /// Serialize all operations into the JSON string sent as `diff`.
    pub fn to_json(&self) -> Result<String> {
        Ok(serde_json::to_string(&self.operations)?)
    }
}

impl Client {
    /// GET `/users/{uid}/settings`: user settings.
    pub async fn users_settings(&self, user_id: Option<&str>) -> Result<Option<UserSettings>> {
        let uid = self.uid(user_id)?;
        let url = self.url(&format!("/users/{uid}/settings"));
        let result = self.http.get(&url, &[]).await?;
        match result {
            Value::Object(mut map) => from_value_opt(map.remove("userSettings").unwrap_or(Value::Null)),
            _ => Ok(None),
        }
    }

    /// GET `/users/{uid}/playlists/{kind}`: a single playlist.
    pub async fn users_playlists(&self, kind: &str, user_id: Option<&str>) -> Result<Option<Playlist>> {
        let uid = self.uid(user_id)?;
        let url = self.url(&format!("/users/{uid}/playlists/{kind}"));
        from_value_opt(self.http.get(&url, &[]).await?)
    }

    /// POST `/users/{uid}/playlists` with `kinds`: several playlists (list form of `users_playlists`).
    pub async fn users_playlists_many<S: AsRef<str>>(
        &self,
        kinds: &[S],
        user_id: Option<&str>,
    ) -> Result<Vec<Playlist>> {
        let uid = self.uid(user_id)?;
        let url = self.url(&format!("/users/{uid}/playlists"));
        let result = self.http.post(&url, &[("kinds", join(kinds))]).await?;
        Ok(from_value_opt(result)?.unwrap_or_default())
    }

    /// GET `/users/{uid}/playlists/{kind}/recommendations`.
    pub async fn users_playlists_recommendations(
        &self,
        kind: &str,
        user_id: Option<&str>,
    ) -> Result<Option<PlaylistRecommendations>> {
        let uid = self.uid(user_id)?;
        let url = self.url(&format!("/users/{uid}/playlists/{kind}/recommendations"));
        from_value_opt(self.http.get(&url, &[]).await?)
    }

    /// POST `/users/{uid}/playlists/create`: create a playlist (`visibility` is usually `public`).
    pub async fn users_playlists_create(
        &self,
        title: &str,
        visibility: &str,
        user_id: Option<&str>,
    ) -> Result<Option<Playlist>> {
        let uid = self.uid(user_id)?;
        let url = self.url(&format!("/users/{uid}/playlists/create"));
        let form = [("title", title.to_owned()), ("visibility", visibility.to_owned())];
        from_value_opt(self.http.post(&url, &form).await?)
    }

    /// POST `/users/{uid}/playlists/{kind}/delete`: delete a playlist.
    pub async fn users_playlists_delete(&self, kind: &str, user_id: Option<&str>) -> Result<bool> {
        let uid = self.uid(user_id)?;
        let url = self.url(&format!("/users/{uid}/playlists/{kind}/delete"));
        Ok(is_ok(&self.http.post(&url, &[]).await?))
    }

    /// POST `/users/{uid}/playlists/{kind}/name`: rename a playlist.
    pub async fn users_playlists_name(
        &self,
        kind: &str,
        name: &str,
        user_id: Option<&str>,
    ) -> Result<Option<Playlist>> {
        let uid = self.uid(user_id)?;
        let url = self.url(&format!("/users/{uid}/playlists/{kind}/name"));
        from_value_opt(self.http.post(&url, &[("value", name.to_owned())]).await?)
    }

    /// POST `/users/{uid}/playlists/{kind}/visibility`: change playlist visibility.
    pub async fn users_playlists_visibility(
        &self,
        kind: &str,
        visibility: &str,
        user_id: Option<&str>,
    ) -> Result<Option<Playlist>> {
        let uid = self.uid(user_id)?;
        let url = self.url(&format!("/users/{uid}/playlists/{kind}/visibility"));
        from_value_opt(self.http.post(&url, &[("value", visibility.to_owned())]).await?)
    }

    /// POST `/users/{uid}/playlists/{kind}/change`: apply a JSON `diff` at `revision`.
    pub async fn users_playlists_change(
        &self,
        kind: &str,
        diff: &str,
        revision: i64,
        user_id: Option<&str>,
    ) -> Result<Option<Playlist>> {
        let uid = self.uid(user_id)?;
        let url = self.url(&format!("/users/{uid}/playlists/{kind}/change"));
        let form = [
            ("kind", kind.to_owned()),
            ("revision", revision.to_string()),
            ("diff", diff.to_owned()),
        ];
        from_value_opt(self.http.post(&url, &form).await?)
    }

    /// Insert a track into a playlist at `at` (builds a `Difference` and calls `users_playlists_change`).
    pub async fn users_playlists_insert_track(
        &self,
        kind: &str,
        track_id: &str,
        album_id: &str,
        at: i64,
        revision: i64,
        user_id: Option<&str>,
    ) -> Result<Option<Playlist>> {
        let diff = Difference::new().add_insert(at, &[(track_id, album_id)]);
        self.users_playlists_change(kind, &diff.to_json()?, revision, user_id).await
    }

    /// Delete tracks `from..to` from a playlist (builds a `Difference` and calls `users_playlists_change`).
    pub async fn users_playlists_delete_track(
        &self,
        kind: &str,
        from: i64,
        to: i64,
        revision: i64,
        user_id: Option<&str>,
    ) -> Result<Option<Playlist>> {
        let diff = Difference::new().add_delete(from, to);
        self.users_playlists_change(kind, &diff.to_json()?, revision, user_id).await
    }

    /// POST `/playlists/collective/join?uid=&token=`: join a collective playlist (numeric `user_id`).
    pub async fn playlists_collective_join(&self, user_id: i64, token: &str) -> Result<bool> {
        let url = self.url("/playlists/collective/join");
        let params = [("uid", user_id.to_string()), ("token", token.to_owned())];
        let rb = self.http.builder(reqwest::Method::POST, &url).query(&params);
        Ok(is_ok(&self.http.send(rb).await?))
    }

    /// GET `/users/{uid}/playlists/list`: all playlists of a user.
    pub async fn users_playlists_list(&self, user_id: Option<&str>) -> Result<Vec<Playlist>> {
        let uid = self.uid(user_id)?;
        let url = self.url(&format!("/users/{uid}/playlists/list"));
        Ok(from_value_opt(self.http.get(&url, &[]).await?)?.unwrap_or_default())
    }

    /// GET `/playlist/{uuid}`: playlist by UUID.
    pub async fn playlist(&self, playlist_uuid: &str) -> Result<Option<Playlist>> {
        let url = self.url(&format!("/playlist/{playlist_uuid}"));
        from_value_opt(self.http.get(&url, &[]).await?)
    }

    /// GET `/playlist/{uuid}/similar-entities`.
    pub async fn playlist_similar_entities(
        &self,
        playlist_uuid: &str,
    ) -> Result<Option<PlaylistSimilarEntities>> {
        let url = self.url(&format!("/playlist/{playlist_uuid}/similar-entities"));
        from_value_opt(self.http.get(&url, &[]).await?)
    }

    /// GET `/playlists?playlistIds=uid:kind,...`.
    pub async fn playlists<S: AsRef<str>>(&self, playlist_ids: &[S]) -> Result<Option<PlaylistsList>> {
        let url = self.url("/playlists");
        let result = self.http.get(&url, &[("playlistIds", join(playlist_ids))]).await?;
        from_value_opt(result)
    }

    /// POST `/playlists/list` with `playlist-ids` (short playlist models, no tracks).
    pub async fn playlists_list<S: AsRef<str>>(&self, playlist_ids: &[S]) -> Result<Vec<Playlist>> {
        let raw = self.get_list_raw("playlist", playlist_ids).await?;
        Ok(from_value_opt(raw)?.unwrap_or_default())
    }

    /// GET `/playlists/personal/{playlist_id}`: personal playlist (`daily`, `missedLikes`, ...).
    pub async fn playlists_personal(&self, playlist_id: &str) -> Result<Option<GeneratedPlaylist>> {
        let url = self.url(&format!("/playlists/personal/{playlist_id}"));
        from_value_opt(self.http.get(&url, &[]).await?)
    }

    /// POST `/users/{uid}/playlists/{kind}/description`: change the description.
    pub async fn users_playlists_description(
        &self,
        kind: &str,
        description: &str,
        user_id: Option<&str>,
    ) -> Result<Option<Playlist>> {
        let uid = self.uid(user_id)?;
        let url = self.url(&format!("/users/{uid}/playlists/{kind}/description"));
        from_value_opt(self.http.post(&url, &[("value", description.to_owned())]).await?)
    }

    /// GET `/users/{uid}/playlists/{kind}/trailer`.
    pub async fn users_playlists_trailer(
        &self,
        kind: &str,
        user_id: Option<&str>,
    ) -> Result<Option<PlaylistTrailer>> {
        let uid = self.uid(user_id)?;
        let url = self.url(&format!("/users/{uid}/playlists/{kind}/trailer"));
        from_value_opt(self.http.get(&url, &[]).await?)
    }

    /// GET `/users/{uid}/playlists/list/kinds`: playlist kinds (integers only).
    pub async fn users_playlists_kinds(&self, user_id: Option<&str>) -> Result<Vec<i64>> {
        let uid = self.uid(user_id)?;
        let url = self.url(&format!("/users/{uid}/playlists/list/kinds"));
        let result = self.http.get(&url, &[]).await?;
        Ok(match result {
            Value::Array(items) => items.iter().filter_map(Value::as_i64).collect(),
            _ => Vec::new(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn difference_json() {
        let d = Difference::new().add_insert(0, &[("1", "2")]).add_delete(1, 3);
        assert_eq!(
            d.to_json().unwrap(),
            r#"[{"at":0,"op":"insert","tracks":[{"albumId":"2","id":"1"}]},{"from":1,"op":"delete","to":3}]"#
        );
    }
}
