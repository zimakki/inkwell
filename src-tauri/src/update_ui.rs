use std::sync::Mutex;
use tauri_plugin_updater::Update;

#[derive(Clone)]
pub enum UpdateBannerState {
    None,
    Available {
        version: String,
        current_version: String,
    },
    Downloading {
        downloaded: u64,
        total: Option<u64>,
    },
    ReadyToRestart,
    Error(String),
    Dismissed,
}

pub struct PendingUpdate {
    pub update: Mutex<Option<Update>>,
    pub banner_state: Mutex<UpdateBannerState>,
}

impl PendingUpdate {
    pub fn new() -> Self {
        Self {
            update: Mutex::new(None),
            banner_state: Mutex::new(UpdateBannerState::None),
        }
    }
}
