//! Port of `yandex_music/account` (account status, subscriptions, products).

use serde::{Deserialize, Serialize};

/// Main information about a user's account.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Account {
    pub now: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub service_available: Option<bool>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub region: Option<i64>,
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub uid: Option<String>,
    pub login: Option<String>,
    pub full_name: Option<String>,
    pub second_name: Option<String>,
    pub first_name: Option<String>,
    pub display_name: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub hosted_user: Option<bool>,
    pub birthday: Option<String>,
    pub passport_phones: Vec<PassportPhone>,
    pub registered_at: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub has_info_for_app_metrica: Option<bool>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub child: Option<bool>,
    pub region_code: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub non_owner_family_member: Option<bool>,
}

/// Phone number attached to a passport account.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct PassportPhone {
    pub phone: Option<String>,
}

/// Button inside an alert.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct AlertButton {
    pub text: Option<String>,
    pub bg_color: Option<String>,
    pub text_color: Option<String>,
    pub uri: Option<String>,
}

/// Alert block (subscription end / gift promos).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Alert {
    #[serde(rename = "alertId")]
    pub alert_id: Option<String>,
    pub text: Option<String>,
    pub bg_color: Option<String>,
    pub text_color: Option<String>,
    #[serde(rename = "alertType")]
    pub alert_type: Option<String>,
    pub button: Option<AlertButton>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub close_button: Option<bool>,
}

/// Auto-renewing subscription info.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct AutoRenewable {
    pub expires: Option<String>,
    pub vendor: Option<String>,
    pub vendor_help_url: Option<String>,
    pub product: Option<Product>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub finished: Option<bool>,
    pub master_info: Option<Box<crate::models::playlist::User>>,
    pub product_id: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub order_id: Option<String>,
}

/// Ways to deactivate a mobile service.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Deactivation {
    pub method: Option<String>,
    pub instructions: Option<String>,
}

/// Disabled auto-renewal info.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct NonAutoRenewable {
    pub start: Option<String>,
    pub end: Option<String>,
}

/// Mobile operator service.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Operator {
    pub product_id: Option<String>,
    pub phone: Option<String>,
    pub payment_regularity: Option<String>,
    pub deactivation: Vec<Deactivation>,
    pub title: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub suspended: Option<bool>,
}

/// User permissions with their default values and expiry.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Permissions {
    pub until: Option<String>,
    pub values: Vec<String>,
    pub default: Vec<String>,
}

/// Plus subscription presence.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Plus {
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub has_plus: Option<bool>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub is_tutorial_completed: Option<bool>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub migrated: Option<bool>,
}

/// Price of a product.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Price {
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub amount: Option<i64>,
    pub currency: Option<String>,
}

/// Sellable product.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Product {
    pub product_id: Option<String>,
    #[serde(rename = "type")]
    pub r#type: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub duration: Option<i64>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub trial_duration: Option<i64>,
    pub feature: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub debug: Option<bool>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub plus: Option<bool>,
    pub price: Option<Price>,
    pub common_period_duration: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub cheapest: Option<bool>,
    pub title: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub family_sub: Option<bool>,
    pub fb_image: Option<String>,
    pub fb_name: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub family: Option<bool>,
    pub features: Option<Vec<String>>,
    pub description: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub available: Option<bool>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub trial_available: Option<bool>,
    pub trial_period_duration: Option<String>,
    pub intro_period_duration: Option<String>,
    pub intro_price: Option<Price>,
    pub start_period_duration: Option<String>,
    pub start_price: Option<Price>,
    pub licence_text_parts: Vec<crate::models::track::LicenceTextPart>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub vendor_trial_available: Option<bool>,
    pub button_text: Option<String>,
    pub button_additional_text: Option<String>,
    pub payment_method_types: Option<Vec<String>>,
}

/// Subscription renewal reminder.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct RenewableRemainder {
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub days: Option<i64>,
}

/// Detailed user account status.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Status {
    pub account: Option<Account>,
    pub permissions: Option<Permissions>,
    pub advertisement: Option<String>,
    pub subscription: Option<Subscription>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub cache_limit: Option<i64>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub subeditor: Option<bool>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub subeditor_level: Option<i64>,
    pub plus: Option<Plus>,
    pub default_email: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub skips_per_hour: Option<i64>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub station_exists: Option<bool>,
    pub station_data: Option<crate::models::rotor::StationData>,
    pub bar_below: Option<Alert>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub premium_region: Option<i64>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub experiment: Option<i64>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub pretrial_active: Option<bool>,
    pub userhash: Option<String>,
    pub has_options: Option<Vec<String>>,
}

/// User subscription information.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Subscription {
    pub auto_renewable: Vec<AutoRenewable>,
    pub family_auto_renewable: Vec<AutoRenewable>,
    pub non_auto_renewable_remainder: Option<RenewableRemainder>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub had_any_subscription: Option<bool>,
    pub operator: Vec<Operator>,
    pub non_auto_renewable: Option<NonAutoRenewable>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub can_start_trial: Option<bool>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub mcdonalds: Option<bool>,
    pub end: Option<String>,
}

/// User settings.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct UserSettings {
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub uid: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub last_fm_scrobbling_enabled: Option<bool>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub shuffle_enabled: Option<bool>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub volume_percents: Option<i64>,
    pub modified: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub facebook_scrobbling_enabled: Option<bool>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub add_new_track_on_playlist_top: Option<bool>,
    pub user_music_visibility: Option<String>,
    pub user_social_visibility: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub rbt_disabled: Option<bool>,
    pub theme: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub promos_disabled: Option<bool>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub auto_play_radio: Option<bool>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub sync_queue_enabled: Option<bool>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub ads_disabled: Option<bool>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub disk_enabled: Option<bool>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub show_disk_tracks_in_library: Option<bool>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deserialize_status() {
        let json = r#"{
            "account": {
                "now": "2024-01-01T00:00:00+00:00",
                "uid": 1130000002804400,
                "login": "user@yandex.ru",
                "displayName": "User",
                "serviceAvailable": true,
                "child": false,
                "region": 213,
                "passportPhones": [{"phone": "+70000000000"}]
            },
            "permissions": {"until": "2024-01-01T00:00:00+00:00", "values": ["landing-play"], "default": []},
            "subscription": {
                "autoRenewable": [{
                    "expires": "2024-02-01T00:00:00+00:00",
                    "vendor": "yndx",
                    "vendorHelpUrl": "https://help.yandex.ru",
                    "product": {"productId": "p1", "type": "ym", "duration": 30, "trialDuration": 0,
                                "feature": "ym", "debug": false, "plus": true,
                                "price": {"amount": 29900, "currency": "RUB"}},
                    "finished": false,
                    "productId": "p1",
                    "orderId": 12345
                }],
                "familyAutoRenewable": [],
                "operator": [{"productId": "op", "phone": "+7000", "paymentRegularity": "monthly",
                              "deactivation": [{"method": "ussd"}], "title": "op", "suspended": false}],
                "nonAutoRenewableRemainder": {"days": 3},
                "hadAnySubscription": true
            },
            "cacheLimit": 99,
            "subeditor": false,
            "plus": {"hasPlus": true, "isTutorialCompleted": false},
            "defaultEmail": "user@yandex.ru",
            "experiment": 109,
            "barBelow": {
                "alertId": "x", "text": "t", "bgColor": "ffffff", "textColor": "000000", "alertType": "test",
                "button": {"text": "ok", "bgColor": "ffffff", "textColor": "000000", "uri": "https://x"},
                "closeButton": true
            },
            "hasOptions": ["bookmate"]
        }"#;
        let s: Status = serde_json::from_str(json).unwrap();
        let acc = s.account.unwrap();
        assert_eq!(acc.uid.as_deref(), Some("1130000002804400"));
        assert_eq!(acc.service_available, Some(true));
        assert_eq!(acc.passport_phones[0].phone.as_deref(), Some("+70000000000"));
        let sub = s.subscription.unwrap();
        let ar = &sub.auto_renewable[0];
        assert_eq!(ar.order_id.as_deref(), Some("12345"));
        assert_eq!(ar.product.as_ref().unwrap().price.as_ref().unwrap().amount, Some(29900));
        assert_eq!(sub.operator[0].deactivation[0].method.as_deref(), Some("ussd"));
        assert_eq!(s.bar_below.unwrap().alert_type.as_deref(), Some("test"));
        assert_eq!(s.plus.unwrap().has_plus, Some(true));
    }

    #[test]
    fn deserialize_user_settings() {
        let json = r#"{
            "uid": 1130000002804400,
            "lastFmScrobblingEnabled": false,
            "shuffleEnabled": false,
            "volumePercents": 70,
            "modified": "2020-01-25T22:52:21+00:00",
            "facebookScrobblingEnabled": false,
            "addNewTrackOnPlaylistTop": false,
            "userMusicVisibility": "public",
            "userSocialVisibility": "public",
            "rbtDisabled": false,
            "theme": "black",
            "promosDisabled": true,
            "autoPlayRadio": true,
            "syncQueueEnabled": true,
            "adsDisabled": null,
            "diskEnabled": false,
            "showDiskTracksInLibrary": false
        }"#;
        let us: UserSettings = serde_json::from_str(json).unwrap();
        assert_eq!(us.volume_percents, Some(70));
        assert_eq!(us.theme.as_deref(), Some("black"));
        assert_eq!(us.ads_disabled, None);
    }
}

/// User info of a playlist owner.
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct User {
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub uid: Option<i64>,
    pub login: Option<String>,
    pub name: Option<String>,
    pub display_name: Option<String>,
    pub full_name: Option<String>,
    pub sex: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_bool")]
    pub verified: Option<bool>,
    pub regions: Vec<String>,
}
