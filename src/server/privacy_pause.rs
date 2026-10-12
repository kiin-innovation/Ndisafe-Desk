use hbb_common::{message_proto::*, tokio::sync::watch};
use std::{
    sync::{
        atomic::{AtomicBool, Ordering},
        Mutex, RwLock, RwLockReadGuard,
    },
    time::Instant,
};

pub(super) struct PauseState {
    paused: AtomicBool,
    gate: RwLock<()>,
    cutoff: Mutex<Option<Instant>>,
    changes: watch::Sender<(bool, bool)>,
}

impl Default for PauseState {
    fn default() -> Self {
        Self {
            paused: AtomicBool::new(false),
            gate: RwLock::new(()),
            cutoff: Mutex::new(None),
            changes: watch::channel((false, true)).0,
        }
    }
}

impl PauseState {
    pub(super) fn is_paused(&self) -> bool {
        self.paused.load(Ordering::SeqCst)
    }

    pub(super) fn set(&self, paused: bool) {
        let _gate = self.gate.write().unwrap();
        if self.is_paused() != paused {
            *self.cutoff.lock().unwrap() = Some(Instant::now());
            self.paused.store(paused, Ordering::SeqCst);
        }
    }

    pub(super) fn permits(&self, queued_at: Instant) -> bool {
        !self.is_paused()
            && self
                .cutoff
                .lock()
                .unwrap()
                .map_or(true, |cutoff| queued_at > cutoff)
    }

    pub(super) fn permit(&self, queued_at: Instant) -> Option<RwLockReadGuard<'_, ()>> {
        let guard = self.gate.read().unwrap();
        self.permits(queued_at).then_some(guard)
    }
}

lazy_static::lazy_static! {
    pub(super) static ref STATE: PauseState = PauseState::default();
}

static REQUEST_IN_PROGRESS: AtomicBool = AtomicBool::new(false);

pub fn is_paused() -> bool {
    STATE.is_paused()
}

pub(super) fn subscribe() -> watch::Receiver<(bool, bool)> {
    STATE.changes.subscribe()
}

pub(super) fn permits(queued_at: Instant) -> bool {
    STATE.permits(queued_at)
}

pub(super) fn permit(queued_at: Instant) -> Option<RwLockReadGuard<'static, ()>> {
    STATE.permit(queued_at)
}

pub(super) fn set_local(paused: bool) {
    STATE.set(paused);
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    if paused {
        super::input_service::release_for_privacy_pause();
    }
}

pub(super) async fn request(paused: bool) -> hbb_common::ResultType<()> {
    if REQUEST_IN_PROGRESS
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_err()
    {
        hbb_common::bail!("A privacy change is already in progress");
    }
    let _reset = crate::SimpleCallOnReturn {
        b: true,
        f: Box::new(|| REQUEST_IN_PROGRESS.store(false, Ordering::SeqCst)),
    };
    hbb_common::tokio::task::spawn_blocking(move || set_local(paused)).await?;
    #[cfg(windows)]
    if let Err(err) = super::portable_service::client::sync_privacy_pause(paused).await {
        // Never confirm privacy until the elevated input helper has stopped too.
        STATE.changes.send_replace((STATE.is_paused(), false));
        return Err(err);
    }
    STATE.changes.send_replace((paused, true));
    Ok(())
}

pub(super) fn sensitive(message: &Message) -> bool {
    match message.union.as_ref() {
        Some(message::Union::VideoFrame(_))
        | Some(message::Union::CursorData(_))
        | Some(message::Union::CursorPosition(_))
        | Some(message::Union::CursorId(_))
        | Some(message::Union::Clipboard(_))
        | Some(message::Union::MultiClipboards(_))
        | Some(message::Union::Cliprdr(_))
        | Some(message::Union::ScreenshotResponse(_))
        | Some(message::Union::FileResponse(_))
        | Some(message::Union::TerminalResponse(_)) => true,
        _ => false,
    }
}

pub(super) fn allows_incoming(message: &Message) -> bool {
    match message.union.as_ref() {
        Some(message::Union::TestDelay(_))
        | Some(message::Union::AudioFrame(_))
        | Some(message::Union::VoiceCallRequest(_))
        | Some(message::Union::VoiceCallResponse(_)) => true,
        Some(message::Union::Misc(misc)) => matches!(
            misc.union.as_ref(),
            Some(misc::Union::ChatMessage(_))
                | Some(misc::Union::CloseReason(_))
                | Some(misc::Union::VideoReceived(_))
                | Some(misc::Union::AudioFormat(_))
        ),
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use hbb_common::protobuf::Message as _;

    #[test]
    fn privacy_pause_drops_queued_data_across_resume() {
        let state = PauseState::default();
        let before = Instant::now();
        assert!(state.permits(before));
        state.set(true);
        let during = Instant::now();
        assert!(!state.permits(before));
        assert!(!state.permits(during));
        state.set(false);
        assert!(!state.permits(before));
        assert!(!state.permits(during));
        assert!(state.permits(Instant::now()));
    }

    #[test]
    fn privacy_pause_waits_for_in_flight_input_or_capture() {
        let state = std::sync::Arc::new(PauseState::default());
        let permit = state.permit(Instant::now()).unwrap();
        let other = state.clone();
        let worker = std::thread::spawn(move || other.set(true));
        assert!(!state.is_paused());
        drop(permit);
        worker.join().unwrap();
        assert!(state.is_paused());
        assert!(state.permit(Instant::now()).is_none());
    }

    #[test]
    fn privacy_pause_preserves_only_chat_voice_and_keepalive() {
        let mut message = Message::new();
        message.set_mouse_event(MouseEvent::new());
        assert!(!allows_incoming(&message));
        message.set_key_event(KeyEvent::new());
        assert!(!allows_incoming(&message));
        message.set_clipboard(Clipboard::new());
        assert!(!allows_incoming(&message));
        message.set_screenshot_request(ScreenshotRequest::new());
        assert!(!allows_incoming(&message));
        message.set_terminal_action(TerminalAction::new());
        assert!(!allows_incoming(&message));
        message.set_file_action(FileAction::new());
        assert!(!allows_incoming(&message));
        message.set_test_delay(TestDelay::new());
        assert!(allows_incoming(&message));
        let mut misc = Misc::new();
        misc.set_privacy_pause(false);
        message.set_misc(misc);
        assert!(!allows_incoming(&message));
        let mut misc = Misc::new();
        misc.set_chat_message(ChatMessage::new());
        message.set_misc(misc);
        assert!(allows_incoming(&message));
    }

    #[test]
    fn privacy_pause_filters_sensitive_output() {
        let mut message = Message::new();
        message.set_video_frame(VideoFrame::new());
        assert!(sensitive(&message));
        message.set_multi_clipboards(MultiClipboards::new());
        assert!(sensitive(&message));
        message.set_screenshot_response(ScreenshotResponse::new());
        assert!(sensitive(&message));
        message.set_test_delay(TestDelay::new());
        assert!(!sensitive(&message));
    }

    #[test]
    fn privacy_pause_notifies_all_viewers_and_late_subscribers() {
        let state = PauseState::default();
        let first = state.changes.subscribe();
        let second = state.changes.subscribe();
        state.set(true);
        state.changes.send_replace((true, true));
        assert_eq!(*first.borrow(), (true, true));
        assert_eq!(*second.borrow(), (true, true));
        assert_eq!(*state.changes.subscribe().borrow(), (true, true));
        state.changes.send_replace((true, false));
        assert_eq!(*first.borrow(), (true, false));
        state.set(false);
        state.changes.send_replace((false, true));
        assert_eq!(*second.borrow(), (false, true));
    }

    #[test]
    fn privacy_pause_protocol_round_trip() {
        for paused in [true, false] {
            let mut misc = Misc::new();
            misc.set_privacy_pause(paused);
            let mut message = Message::new();
            message.set_misc(misc);
            let decoded = Message::parse_from_bytes(&message.write_to_bytes().unwrap()).unwrap();
            assert_eq!(
                decoded.misc().union,
                Some(misc::Union::PrivacyPause(paused))
            );
        }
    }
}
