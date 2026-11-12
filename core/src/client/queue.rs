//! Port of `yandex_music/_client/queue.py`: listening queue of devices.

use reqwest::Method;
use serde_json::Value;

use super::Client;
use crate::error::Result;
use crate::http::{from_value_opt, is_ok};
use crate::models::queue::{Queue, QueueItem};

impl Client {
    /// `GET /queues` with `X-Yandex-Music-Device`: queues of all devices.
    pub async fn queues_list(&self, device: Option<&str>) -> Result<Vec<QueueItem>> {
        let device = device.filter(|d| !d.is_empty()).unwrap_or("android");
        let url = self.url("/queues");
        let v = self
            .http
            .send(self.http.builder(Method::GET, &url).header("X-Yandex-Music-Device", device))
            .await?;
        match v.get("queues") {
            Some(Value::Array(items)) => Ok(from_value_opt::<Vec<QueueItem>>(Value::Array(items.clone()))?.unwrap_or_default()),
            _ => Ok(Vec::new()),
        }
    }

    /// `GET /queues/{queue_id}`: queue info with its tracks.
    pub async fn queue(&self, queue_id: &str) -> Result<Option<Queue>> {
        let url = self.url(&format!("/queues/{queue_id}"));
        let v = self.http.get(&url, &[]).await?;
        from_value_opt(v)
    }

    /// `POST /queues/{queue_id}/update-position` with `currentIndex` query: sets the current track index.
    pub async fn queue_update_position(
        &self,
        queue_id: &str,
        current_index: i64,
        device: Option<&str>,
    ) -> Result<bool> {
        let device = device.filter(|d| !d.is_empty()).unwrap_or("android");
        let url = self.url(&format!("/queues/{queue_id}/update-position"));
        let idx = current_index.to_string();
        let rb = self
            .http
            .builder(Method::POST, &url)
            .header("X-Yandex-Music-Device", device)
            .query(&[("currentIndex", idx.as_str())])
            .form(&[("isInteractive", "false")]);
        let v = self.http.send(rb).await?;
        Ok(is_ok(&v))
    }

    /// `POST /queues` with the queue JSON body: creates a queue, returns its id.
    pub async fn queue_create(&self, queue: &Queue, device: Option<&str>) -> Result<Option<String>> {
        let device = device.filter(|d| !d.is_empty()).unwrap_or("android");
        let url = self.url("/queues");
        let body = serde_json::to_value(queue).map_err(|e| crate::error::Error::Other(e.to_string()))?;
        let rb = self
            .http
            .builder(Method::POST, &url)
            .header("X-Yandex-Music-Device", device)
            .json(&body);
        let v = self.http.send(rb).await?;
        Ok(v.get("id").and_then(|id| match id {
            Value::String(s) => Some(s.clone()),
            Value::Number(n) => Some(n.to_string()),
            _ => None,
        }))
    }
}
