//! Port of `yandex_music/_client/wave.py`.

use super::Client;
use crate::error::Result;
use crate::http::{from_value_opt, is_ok, join, Params};
use crate::models::wave::{Wave, WaveSettings};

impl Client {
    /// GET `/rotor/wave/last` — last played wave.
    pub async fn rotor_wave_last(&self) -> Result<Option<Wave>> {
        let v = self.http.get(&self.url("/rotor/wave/last"), &[]).await?;
        from_value_opt::<Wave>(v)
    }

    /// POST `/rotor/wave/last/reset` — reset the last wave to "My wave".
    pub async fn rotor_wave_last_reset(&self) -> Result<bool> {
        let v = self.http.post(&self.url("/rotor/wave/last/reset"), &[]).await?;
        Ok(is_ok(&v))
    }

    /// GET `/rotor/wave/settings` — wave settings (contexts and available values).
    pub async fn rotor_wave_settings<S: AsRef<str>>(&self, seeds: &[S]) -> Result<Option<WaveSettings>> {
        let seeds = join(seeds);
        let params: Vec<(&str, String)> = if seeds.is_empty() {
            Vec::new()
        } else {
            vec![("seeds", seeds)]
        };
        let v = self
            .http
            .get(&self.url("/rotor/wave/settings"), &params as Params)
            .await?;
        from_value_opt::<WaveSettings>(v)
    }
}
