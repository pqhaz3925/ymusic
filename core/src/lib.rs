//! Rust port of the unofficial Yandex Music API client (MarshalX/yandex-music-api).

pub mod client;
pub mod error;
pub mod ffi;
pub mod http;
pub mod models;
pub mod utils;
pub mod ynison;

pub use client::Client;
pub use error::{Error, Result};

uniffi::setup_scaffolding!();
