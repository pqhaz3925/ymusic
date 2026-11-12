//! Port of `yandex_music/_client/account.py`.

use serde_json::Value;

use super::Client;
use crate::error::Result;
use crate::http::{from_value_opt, Params};
use crate::models::account::{Status, UserSettings};
use crate::models::common::{Experiments, PermissionAlerts, PromoCodeStatus, Settings};
use crate::models::experiment::ExperimentsDetails;

impl Client {
    /// `account_status` + store the account uid on the client.
    pub async fn init(&self) -> Result<Option<Status>> {
        let me = self.account_status().await?;
        if let Some(uid) = me.as_ref().and_then(|s| s.account.as_ref()).and_then(|a| a.uid.as_deref()) {
            self.set_account_uid(uid.parse().ok());
        }
        Ok(me)
    }

    /// GET `/account/status`; also stores the account uid on the client.
    pub async fn account_status(&self) -> Result<Option<Status>> {
        let v = self.http.get(&self.url("/account/status"), &[]).await?;
        let me = from_value_opt::<Status>(v)?;
        if let Some(uid) = me.as_ref().and_then(|s| s.account.as_ref()).and_then(|a| a.uid.as_deref()) {
            self.set_account_uid(uid.parse().ok());
        }
        Ok(me)
    }

    /// GET `/account/settings`.
    pub async fn account_settings(&self) -> Result<Option<UserSettings>> {
        let v = self.http.get(&self.url("/account/settings"), &[]).await?;
        from_value_opt(v)
    }

    /// POST `/account/settings` with `param=value` or a `data` map.
    pub async fn account_settings_set(&self, param: Option<&str>, value: Option<&str>, data: Option<&Value>) -> Result<Option<UserSettings>> {
        let empty = data.map(|d| d.as_object().map(|o| o.is_empty()).unwrap_or(true)).unwrap_or(true);
        let mut form: Vec<(&str, String)> = Vec::new();
        if empty {
            if let (Some(p), Some(v)) = (param, value) {
                if !p.is_empty() {
                    form.push((p, v.to_owned()));
                }
            }
        } else if let Some(Value::Object(o)) = data {
            for (k, v) in o {
                form.push((k.as_str(), v.as_str().map(str::to_owned).unwrap_or_else(|| v.to_string())));
            }
        }
        let v = self.http.post(&self.url("/account/settings"), &form).await?;
        from_value_opt(v)
    }

    /// GET `/settings` (purchase offers).
    pub async fn settings(&self) -> Result<Option<Settings>> {
        let v = self.http.get(&self.url("/settings"), &[]).await?;
        from_value_opt(v)
    }

    /// GET `/permission-alerts`.
    pub async fn permission_alerts(&self) -> Result<Option<PermissionAlerts>> {
        let v = self.http.get(&self.url("/permission-alerts"), &[]).await?;
        from_value_opt(v)
    }

    /// GET `/account/experiments`.
    pub async fn account_experiments(&self) -> Result<Option<Experiments>> {
        let v = self.http.get(&self.url("/account/experiments"), &[]).await?;
        from_value_opt(v)
    }

    /// GET `/account/experiments/details`.
    pub async fn account_experiments_details(&self) -> Result<Option<ExperimentsDetails>> {
        let v = self.http.get(&self.url("/account/experiments/details"), &[]).await?;
        from_value_opt(v)
    }

    /// POST `/account/consume-promo-code` with `code` and `language` (defaults to client language).
    pub async fn consume_promo_code(&self, code: &str, language: Option<&str>) -> Result<Option<PromoCodeStatus>> {
        let language = match language {
            Some(l) if !l.is_empty() => l.to_owned(),
            _ => self.language.clone(),
        };
        let form: Params<'_> = &[("code", code.to_owned()), ("language", language)];
        let v = self.http.post(&self.url("/account/consume-promo-code"), form).await?;
        from_value_opt(v)
    }
}
