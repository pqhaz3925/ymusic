//! API models. One module per Python package in `yandex_music/`.
//! Root-level Python models (Cover, Pager, Like, TrackShort, ...) live in `common`.

pub mod de;

pub mod account;
pub mod album;
pub mod artist;
pub mod clip;
pub mod common;
pub mod concert;
pub mod device_auth;
pub mod experiment;
pub mod feed;
pub mod genre;
pub mod label;
pub mod landing;
pub mod metatag;
pub mod music_history;
pub mod pin;
pub mod playlist;
pub mod presave;
pub mod queue;
pub mod rotor;
pub mod search;
pub mod shot;
pub mod skeleton;
pub mod supplement;
pub mod track;
pub mod wave;
