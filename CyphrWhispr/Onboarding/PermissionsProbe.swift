import AVFoundation
import AppKit
import ApplicationServices
import Combine

/// Live status of the two system permissions CyphrWhispr requires to function:
/// **Microphone** (audio capture) and **Accessibility** (synthesising ⌘V into
/// the focused app).
///
/// macOS doesn't deliver KVO notifications when the user toggles these in
/// System Settings, so a 1Hz polling timer is the cleanest way to make the
/// onboarding checklist's badges flip the moment a checkbox is ticked. The
/// probe runs only while a view that cares is on screen (`start()` / `stop()`).
@MainActor
final class PermissionsProbe: ObservableObject {

    enum MicrophoneStatus: Equatable {
        /// The user hasn't been asked yet — `requestMicrophone()` will trigger
        /// the OS prompt.
        case notDetermined
        case granted
        /// Includes `.denied` and `.restricted`. The OS won't show the prompt
        /// again; the user must visit System Settings to re-grant.
        case denied
    }

    enum AccessibilityStatus: Equatable {
        case granted
        case missing
    }

    @Published private(set) var microphone: MicrophoneStatus = .notDetermined
    @Published private(set) var accessibility: AccessibilityStatus = .missing

    /// True iff both required permissions are in place. Callers compose any
    /// non-required items (model, hotkey) on top of this.
    var bothGranted: Bool {
        microphone == .granted && accessibility == .granted
    }

    private var timer: Timer?

    init() {
        refresh()
    }

    // MARK: - Lifecycle

    /// Start polling. Idempotent.
    func start() {
        refresh()
        guard timer == nil else { return }
        // Timer.scheduledTimer's closure isn't async and isn't on MainActor;
        // hop back explicitly so the @Published writes happen on the main
        // actor.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    /// Stop polling. Idempotent.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - State refresh

    /// Pull the latest values from the OS and publish only when they change.
    /// Public so callers (e.g. the microphone-request callback) can force a
    /// refresh without waiting for the next tick.
    func refresh() {
        let mic: MicrophoneStatus
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:                  mic = .granted
        case .denied, .restricted:         mic = .denied
        case .notDetermined:               mic = .notDetermined
        @unknown default:                  mic = .notDetermined
        }
        if mic != microphone { microphone = mic }

        let acc: AccessibilityStatus = AXIsProcessTrusted() ? .granted : .missing
        if acc != accessibility { accessibility = acc }
    }

    // MARK: - Actions

    /// Trigger the OS microphone-permission prompt. No-op when the user has
    /// already granted or denied — once denied, macOS won't show the prompt
    /// again, so callers should fall through to `openMicrophoneSystemSettings()`.
    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            Task { @MainActor in self.refresh() }
        }
    }

    /// Open System Settings → Privacy & Security → Microphone.
    func openMicrophoneSystemSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// Open System Settings → Privacy & Security → Accessibility. macOS does
    /// not allow apps to grant Accessibility programmatically, so this is the
    /// only path to flipping the checkbox.
    func openAccessibilitySystemSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
