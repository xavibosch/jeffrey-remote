import SwiftUI
import Combine
import UIKit
import AVFoundation
import Network

enum JeffreyRemoteTab: String, CaseIterable, Identifiable {
    case remote
    case controls
    case media
    case apps
    case voice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .remote: return "Remote"
        case .controls: return "Controls"
        case .media: return "Media"
        case .apps: return "Apps"
        case .voice: return "Voice"
        }
    }

    var icon: String {
        switch self {
        case .remote: return "iphone.gen3.radiowaves.left.and.right"
        case .controls: return "switch.2"
        case .media: return "play.circle"
        case .apps: return "square.grid.2x2"
        case .voice: return "waveform.bubble"
        }
    }
}

enum RemoteMode: String, CaseIterable {
    case cursor = "Cursor"
    case click = "Click"
    case hold = "Hold"
    case double = "Double"
    case right = "Right"
    case scroll = "Scroll"

    var icon: String {
        switch self {
        case .cursor: return "cursorarrow"
        case .click: return "cursorarrow.click"
        case .hold: return "hand.tap"
        case .double: return "plus.magnifyingglass"
        case .right: return "arrow.clockwise"
        case .scroll: return "square.stack.3d.up"
        }
    }
}

enum JeffreyRemoteSpeechLanguage: String, CaseIterable, Identifiable {
    case auto
    case englishUK = "en-GB"
    case englishUS = "en-US"
    case spanish = "es-ES"
    case catalan = "ca-ES"
    case french = "fr-FR"
    case german = "de-DE"
    case italian = "it-IT"
    case portuguese = "pt-PT"
    case japanese = "ja-JP"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .englishUK: return "English UK"
        case .englishUS: return "English US"
        case .spanish: return "Spanish"
        case .catalan: return "Catalan"
        case .french: return "French"
        case .german: return "German"
        case .italian: return "Italian"
        case .portuguese: return "Portuguese"
        case .japanese: return "Japanese"
        }
    }
}

struct ToastBannerState: Equatable {
    let icon: String
    let title: String
    let subtitle: String
}

enum JeffreyRemoteConnectionMode: String, CaseIterable, Identifiable {
    case wifi
    case hotspot
    case tailscale

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .hotspot: return "Hotspot"
        case .tailscale: return "Tailscale"
        }
    }

    var subtitle: String {
        switch self {
        case .wifi: return "Nearby Bonjour bridge"
        case .hotspot: return "Mac joined to your iPhone"
        case .tailscale: return "Always-on direct host"
        }
    }

    var icon: String {
        switch self {
        case .wifi: return "wifi"
        case .hotspot: return "iphone.radiowaves.left.and.right"
        case .tailscale: return "network.badge.shield.half.filled"
        }
    }
}

@MainActor
final class WelcomeSpeechCoordinator {
    static let shared = WelcomeSpeechCoordinator()

    private let synthesizer = AVSpeechSynthesizer()
    private var hasSpoken = false

    func speakIfNeeded() {
        guard !hasSpoken, !synthesizer.isSpeaking else { return }
        hasSpoken = true

        let utterance = AVSpeechUtterance(string: "Welcome back Mr. Bosk.")
        utterance.rate = 0.46
        utterance.pitchMultiplier = 0.95
        utterance.volume = 1.0
        if let voice = AVSpeechSynthesisVoice(language: "en-GB") ?? AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }
        synthesizer.speak(utterance)
    }
}

@MainActor
final class JeffreyRemotePrototypeState: ObservableObject {
    private enum DefaultsKey {
        static let host = "JeffreyRemote.connectionHost"
        static let preferredServiceID = "JeffreyRemote.preferredServiceID"
        static let connectionMode = "JeffreyRemote.connectionMode"
    }

    static let defaultTailscaleHost = "100.64.0.1"

    @Published var selectedTab: JeffreyRemoteTab = .remote
    @Published var toast: ToastBannerState?
    @Published var cursor = CGPoint(x: 0.69, y: 0.60)
    @Published var captureLabel = "Tap camera"
    @Published var statusLine = "Tap CONNECTED to pair Jeffrey Remote with your Mac."

    @Published var activeSource = JeffreyRemoteFixtures.mediaSources.first ?? "Spotify"
    @Published var mediaTitle = "Spinning up media controls"
    @Published var mediaSubtitle = "Playback controls are ready on the Mac"
    @Published var mediaContext = "Media"
    @Published var mediaArtworkURL: URL?
    @Published var isPlaying = false
    @Published var playbackProgress = 0.0
    @Published var mediaCurrentTime: Double = 0
    @Published var mediaDuration: Double = 0
    @Published var volume = 0.5
    @Published var screenBrightness = 0.5
    @Published var keyboardBrightness = 0.5
    @Published var litButtons: Set<String> = []

    @Published var connectionHost: String
    @Published var connectionLabel: String
    @Published var connectionMode: JeffreyRemoteConnectionMode
    @Published var isConnected = false
    @Published var isReconnecting = false
    @Published var showingConnectionSheet = false
    @Published var discoveredMacs: [JeffreyRemoteDiscoveredMac] = []
    @Published var showingKeyboardSheet = false
    @Published var showingKeepAwakeSheet = false
    @Published var showingCaptureViewer = false
    @Published var keyboardDraft = ""
    @Published var customControlCommand = ""
    @Published var appQuery = ""
    @Published var speechBroadcastDraft = ""
    @Published var speechBroadcastStatus = "Type a line and Jeffrey will say it out loud almost immediately."
    @Published var speechLanguage: JeffreyRemoteSpeechLanguage = .auto
    @Published var availableApps: [String] = []
    @Published var latestCaptureImage: UIImage?
    @Published var scrollModeEnabled = false
    @Published var holdModeEnabled = false
    @Published var keepAwakeUntil: Date?
    @Published var macBatteryLevel: Int?
    @Published var keepAwakeHours = 2
    @Published var keepAwakeMinutes = 0

    private let bridgeClient = JeffreyRemoteBridgeClient()
    private let discoveryService = JeffreyRemoteDiscoveryService()
    private var pendingDismiss: DispatchWorkItem?
    private var pendingButtonReset: [String: DispatchWorkItem] = [:]
    private var pendingCursorRequest: DispatchWorkItem?
    private var pendingScrollRequest: DispatchWorkItem?
    private var pendingLevelRequests: [String: DispatchWorkItem] = [:]
    private var pendingSpeechBroadcast: DispatchWorkItem?
    private var scrollAccumulator: CGSize = .zero
    private var connectedEndpoint: NWEndpoint?
    private var preferredServiceID: String?
    private var lastBroadcastSpeech = ""
    private var healthMonitorTask: Task<Void, Never>?

    init() {
        let savedHost = UserDefaults.standard.string(forKey: DefaultsKey.host) ?? ""
        let savedMode = JeffreyRemoteConnectionMode(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.connectionMode) ?? "") ?? .tailscale
        let resolvedHost = savedHost.isEmpty && savedMode == .tailscale ? Self.defaultTailscaleHost : savedHost
        self.preferredServiceID = UserDefaults.standard.string(forKey: DefaultsKey.preferredServiceID)
        self.connectionMode = savedMode
        self.connectionHost = resolvedHost
        self.connectionLabel = resolvedHost.isEmpty ? "Tap to connect" : resolvedHost
        discoveryService.onResultsChanged = { [weak self] results in
            guard let self else { return }
            self.discoveredMacs = results
            if self.connectionMode != .tailscale,
               let preferredID = self.preferredServiceID,
               let matching = results.first(where: { $0.id == preferredID }),
               self.connectionHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.connectedEndpoint = matching.endpoint
                self.connectionLabel = matching.name
            }
        }
    }

    var remoteModeLabel: String {
        if holdModeEnabled { return "DRAG HOLD" }
        if scrollModeEnabled { return "SCROLL MODE" }
        return "CURSOR MODE"
    }

    var keepAwakeStatusTitle: String {
        guard let keepAwakeUntil else { return "Mac can sleep normally" }
        return "Awake until \(keepAwakeUntil.formatted(date: .omitted, time: .shortened))"
    }

    var keepAwakeBadgeText: String {
        keepAwakeUntil == nil ? "OFF" : "ACTIVE"
    }

    var macBatteryText: String {
        guard let macBatteryLevel else { return "--%" }
        return "\(macBatteryLevel)%"
    }

    var macBatterySymbol: String {
        guard let macBatteryLevel else { return "battery.50" }
        switch macBatteryLevel {
        case ..<20: return "battery.25"
        case ..<45: return "battery.50"
        case ..<75: return "battery.75"
        default: return "battery.100"
        }
    }

    func setConnectionMode(_ mode: JeffreyRemoteConnectionMode) {
        connectionMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: DefaultsKey.connectionMode)
        if mode == .tailscale, connectionHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            connectionHost = Self.defaultTailscaleHost
            UserDefaults.standard.set(connectionHost, forKey: DefaultsKey.host)
            connectionLabel = connectionHost
        }
    }

    func bootstrapConnection() async {
        discoveryService.start(forceRestart: true)
        startHealthMonitorIfNeeded()
        guard hasConnectionTarget else { return }
        _ = await recoverConnection(showToast: false, aggressive: false)
        if isConnected {
            await refreshAvailableApps(query: "")
        }
    }

    func openConnectionSettings() {
        discoveryService.start(forceRestart: true)
        showingConnectionSheet = true
    }

    func connectToTailscale(host: String) async {
        setConnectionMode(.tailscale)
        await connect(to: host)
    }

    func connect(to host: String) async {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showToast(icon: "wifi.slash", title: "Missing host", subtitle: "Enter the Mac IP or local hostname.")
            return
        }

        connectedEndpoint = nil
        connectionHost = trimmed
        UserDefaults.standard.set(trimmed, forKey: DefaultsKey.host)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.preferredServiceID)
        preferredServiceID = nil
        connectionLabel = trimmed
        await ping(showFailure: true)
        if isConnected {
            startHealthMonitorIfNeeded()
            await refreshAvailableApps(query: "")
        }
    }

    func connect(to discoveredMac: JeffreyRemoteDiscoveredMac, mode: JeffreyRemoteConnectionMode) async {
        setConnectionMode(mode)
        connectedEndpoint = discoveredMac.endpoint
        connectionHost = ""
        connectionLabel = discoveredMac.name
        UserDefaults.standard.removeObject(forKey: DefaultsKey.host)
        UserDefaults.standard.set(discoveredMac.id, forKey: DefaultsKey.preferredServiceID)
        UserDefaults.standard.set(mode.rawValue, forKey: DefaultsKey.connectionMode)
        preferredServiceID = discoveredMac.id
        await ping(showFailure: true)
        if isConnected {
            startHealthMonitorIfNeeded()
            await refreshAvailableApps(query: "")
        }
    }

    func disconnect() {
        isConnected = false
        isReconnecting = false
        connectedEndpoint = nil
        connectionLabel = connectionHost.isEmpty ? "Tap to connect" : connectionHost
        statusLine = "Disconnected from Jeffrey on the Mac."
        showToast(icon: "wifi.slash", title: "Disconnected", subtitle: "Jeffrey Remote is back in offline preview mode.")
    }

    func handleScenePhaseChange(_ phase: ScenePhase) async {
        guard phase == .active else { return }
        discoveryService.start(forceRestart: true)
        startHealthMonitorIfNeeded()
        guard hasConnectionTarget else { return }
        _ = await recoverConnection(showToast: false, aggressive: true)
    }

    func reconnectNow() {
        light("connection:reconnect", duration: 0.9)
        Task {
            let recovered = await recoverConnection(showToast: true, aggressive: true)
            if !recovered {
                showToast(icon: "wifi.slash", title: "Reconnect failed", subtitle: "Jeffrey could not reconnect just yet. Check Tailscale and keep the Mac awake.")
            }
        }
    }

    func presentKeepAwakeConfigurator() {
        if let keepAwakeUntil {
            let remainingMinutes = max(Int(keepAwakeUntil.timeIntervalSinceNow / 60.0), 15)
            keepAwakeHours = min(8, remainingMinutes / 60)
            keepAwakeMinutes = min(55, ((remainingMinutes % 60) / 5) * 5)
        } else {
            keepAwakeHours = 2
            keepAwakeMinutes = 0
        }
        showingKeepAwakeSheet = true
    }

    func confirmKeepAwakeSelection() {
        let totalMinutes = max(15, keepAwakeHours * 60 + keepAwakeMinutes)
        showingKeepAwakeSheet = false
        triggerKeepAwake(minutes: totalMinutes)
    }

    func triggerKeepAwake(minutes: Int = 120) {
        light("power:keepawake", duration: 1.0)
        Task {
            guard let response = await perform(
                JeffreyRemoteBridgeRequest(action: "keep_awake", value: Double(minutes), source: activeSource),
                failureTitle: "Keep awake failed",
                toastOnSuccess: false
            ) else { return }
            statusLine = response.message
            showToast(icon: "bolt.badge.clock.fill", title: "Keep Awake enabled", subtitle: response.message)
        }
    }

    func triggerWakeMac() {
        light("power:wakemac", duration: 1.0)
        Task {
            guard let response = await perform(
                JeffreyRemoteBridgeRequest(action: "wake_mac", source: activeSource),
                failureTitle: "Wake failed",
                toastOnSuccess: false
            ) else { return }
            statusLine = response.message
            showToast(icon: "display", title: "Wake attempt sent", subtitle: response.message)
        }
    }

    func triggerGoodMorning() {
        light("wake:goodmorning")
        Task {
            guard let response = await perform(
                JeffreyRemoteBridgeRequest(action: "command", command: "good morning", source: activeSource),
                failureTitle: "Wake failed",
                toastOnSuccess: false
            ) else { return }
            statusLine = response.message
            showToast(icon: "sun.horizon.fill", title: "Good morning", subtitle: response.message)
        }
    }

    func scheduleSpeechBroadcast() {
        let trimmed = speechBroadcastDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingSpeechBroadcast?.cancel()

        guard !trimmed.isEmpty else {
            speechBroadcastStatus = "Type a line and Jeffrey will say it out loud almost immediately."
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.sendSpeechBroadcast(trimmed)
            }
        }

        pendingSpeechBroadcast = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    func sendSpeechBroadcastNow() {
        let trimmed = speechBroadcastDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingSpeechBroadcast?.cancel()
        guard !trimmed.isEmpty else { return }
        Task { @MainActor in
            await sendSpeechBroadcast(trimmed)
        }
    }

    func showToast(icon: String, title: String, subtitle: String) {
        pendingDismiss?.cancel()
        toast = ToastBannerState(icon: icon, title: title, subtitle: subtitle)
        let workItem = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.18)) {
                self?.toast = nil
            }
        }
        pendingDismiss = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: workItem)
    }

    private func sendSpeechBroadcast(_ text: String) async {
        guard text != lastBroadcastSpeech else { return }
        light("speech:broadcast")
        guard let response = await perform(
            JeffreyRemoteBridgeRequest(
                action: "speak_text",
                command: text,
                source: speechLanguage == .auto ? nil : speechLanguage.rawValue
            ),
            failureTitle: "Voice relay failed",
            toastOnSuccess: false
        ) else { return }

        lastBroadcastSpeech = text
        speechBroadcastStatus = response.message
        showToast(icon: "waveform", title: "Jeffrey speaking", subtitle: response.message)
    }

    func triggerCapture() {
        light("capture")
        Task {
            guard let response = await perform(
                JeffreyRemoteBridgeRequest(action: "screenshot", source: activeSource),
                failureTitle: "Capture failed"
            ) else { return }
            captureLabel = "Just now"
            statusLine = response.message
            showToast(icon: "camera.fill", title: "Capture synced", subtitle: response.message)
        }
    }

    func openCaptureViewer() {
        light("capture:viewer")
        if latestCaptureImage != nil {
            showingCaptureViewer = true
            return
        }

        Task {
            guard let response = await perform(
                JeffreyRemoteBridgeRequest(action: "screenshot", source: activeSource),
                failureTitle: "Capture failed",
                toastOnSuccess: false
            ) else { return }
            captureLabel = "Just now"
            statusLine = response.message
            showingCaptureViewer = latestCaptureImage != nil
            showToast(icon: "viewfinder.circle.fill", title: "Expanded preview", subtitle: "The live screenshot is ready to position the cursor.")
        }
    }

    func chooseRemoteMode(_ mode: RemoteMode) {
        light("remote:\(mode.rawValue)")
        switch mode {
        case .cursor:
            endScrollMode()
            endHoldMode()
            statusLine = "Cursor mode armed."
            showToast(icon: mode.icon, title: "Cursor mode", subtitle: "The pad now moves the real Mac cursor.")
        default:
            statusLine = "\(mode.rawValue) mode armed."
            showToast(icon: mode.icon, title: "\(mode.rawValue) selected", subtitle: "Jeffrey Remote is ready.")
        }
    }

    func triggerRemoteAction(_ action: RemoteMode) {
        light("remote:\(action.rawValue)")

        switch action {
        case .click:
            Task { await performMouseAction("click", title: "Click sent", subtitle: "Jeffrey clicked at the current cursor position.") }
        case .double:
            Task { await performMouseAction("double", title: "Double click sent", subtitle: "Jeffrey double-clicked the current cursor position.") }
        case .right:
            Task { await performMouseAction("right", title: "Right click sent", subtitle: "Jeffrey sent a contextual click.") }
        case .hold:
            beginHoldMode()
        case .scroll:
            beginScrollMode()
        case .cursor:
            chooseRemoteMode(.cursor)
        }
    }

    func beginHoldMode() {
        guard !holdModeEnabled else { return }
        if scrollModeEnabled {
            endScrollMode()
        }
        holdModeEnabled = true
        statusLine = "Hold active. Keep dragging on the pad to select or move items."
        Task {
            _ = await perform(
                JeffreyRemoteBridgeRequest(action: "mouse_action", mouseAction: "down", source: activeSource),
                failureTitle: "Hold failed",
                toastOnSuccess: false
            )
        }
    }

    func endHoldMode() {
        guard holdModeEnabled else { return }
        holdModeEnabled = false
        statusLine = "Hold released."
        Task {
            _ = await perform(
                JeffreyRemoteBridgeRequest(action: "mouse_action", mouseAction: "up", source: activeSource),
                failureTitle: "Hold release failed",
                toastOnSuccess: false
            )
        }
    }

    func beginScrollMode() {
        guard !scrollModeEnabled else { return }
        if holdModeEnabled {
            endHoldMode()
        }
        scrollModeEnabled = true
        scrollAccumulator = .zero
        statusLine = "Scroll active. Drag on the pad to scroll without moving the cursor."
    }

    func endScrollMode() {
        guard scrollModeEnabled else { return }
        scrollModeEnabled = false
        scrollAccumulator = .zero
        statusLine = "Scroll released."
    }

    func triggerKeyboard() {
        light("keyboard")
        showingKeyboardSheet = true
        statusLine = "Keyboard deck opened."
    }

    func triggerArrow(_ direction: String) {
        light("arrow:\(direction)")
        Task {
            guard let response = await perform(
                JeffreyRemoteBridgeRequest(action: "key", command: direction, source: activeSource),
                failureTitle: "Directional key failed"
            ) else { return }
            statusLine = response.message
            showToast(icon: "arrowshape.turn.up.right.fill", title: "Directional key sent", subtitle: response.message)
        }
    }

    func triggerCommand(_ command: QuickCommand) {
        light("command:\(command.command)")
        Task {
            guard let response = await perform(
                JeffreyRemoteBridgeRequest(action: "command", command: command.command, source: activeSource),
                failureTitle: command.title
            ) else { return }
            statusLine = response.message
            showToast(icon: command.icon, title: command.title, subtitle: response.message)
        }
    }

    func triggerCustomControlCommand() {
        let command = customControlCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            showToast(icon: "text.magnifyingglass", title: "No command yet", subtitle: "Type any Jeffrey command in Controls and we'll run it straight away.")
            return
        }
        light("command:custom")
        Task {
            guard let response = await perform(
                JeffreyRemoteBridgeRequest(action: "command", command: command, source: activeSource),
                failureTitle: "Command failed"
            ) else { return }
            statusLine = response.message
            showToast(icon: "bolt.fill", title: "Command sent", subtitle: response.message)
        }
    }

    func triggerApp(_ app: QuickCommand) {
        light("app:\(app.command)")
        Task {
            guard let response = await perform(
                JeffreyRemoteBridgeRequest(action: "command", command: app.command, source: activeSource),
                failureTitle: app.title
            ) else { return }
            statusLine = response.message
            showToast(icon: app.icon, title: app.title, subtitle: response.message)
        }
    }

    func triggerCustomAppCommand() {
        let command = normalizedAppCommand(appQuery)
        guard !command.isEmpty else {
            showToast(icon: "app.badge", title: "No app command yet", subtitle: "Type an app name or a full command like open safari d3.")
            return
        }
        light("app:custom")
        Task {
            guard let response = await perform(
                JeffreyRemoteBridgeRequest(action: "command", command: command, source: activeSource),
                failureTitle: "App command failed"
            ) else { return }
            statusLine = response.message
            showToast(icon: "app.fill", title: "App command sent", subtitle: response.message)
            await refreshAvailableApps(query: appQuery)
        }
    }

    func triggerOpenInstalledApp(named appName: String) {
        appQuery = appName
        light("app:\(appName)")
        Task {
            guard let response = await perform(
                JeffreyRemoteBridgeRequest(action: "command", command: "open \(appName)", source: activeSource),
                failureTitle: "Open app failed"
            ) else { return }
            statusLine = response.message
            showToast(icon: "app.badge.fill", title: "Opening \(appName)", subtitle: response.message)
        }
    }

    func chooseSource(_ source: String) {
        activeSource = source
        light("source:\(source)")
        Task {
            if let response = await perform(
                JeffreyRemoteBridgeRequest(action: "media_state", source: source),
                failureTitle: "Media sync failed",
                toastOnSuccess: false
            ) {
                statusLine = response.message
            }
        }
    }

    func togglePlayback() {
        light("media:playpause")
        let previousState = isPlaying
        isPlaying.toggle()
        Task {
            guard let response = await perform(
                JeffreyRemoteBridgeRequest(action: "toggle_media", source: activeSource),
                failureTitle: "Playback failed",
                toastOnSuccess: false
            ) else {
                isPlaying = previousState
                return
            }
            statusLine = response.message
            let resumed = isPlaying
            showToast(icon: resumed ? "play.fill" : "pause.fill", title: resumed ? "Playback resumed" : "Playback paused", subtitle: response.message)
        }
    }

    func seekRelative(seconds: Double) {
        let directionKey = seconds >= 0 ? "forward15" : "backward15"
        light("media:\(directionKey)")
        if mediaDuration > 0 {
            mediaCurrentTime = min(max(mediaCurrentTime + seconds, 0), mediaDuration)
            playbackProgress = min(max(mediaCurrentTime / mediaDuration, 0.0), 1.0)
        }
        Task {
            guard let response = await perform(
                JeffreyRemoteBridgeRequest(action: "seek_media", command: String(Int(seconds)), source: activeSource),
                failureTitle: "Media seek failed",
                toastOnSuccess: false
            ) else { return }
            statusLine = response.message
            let title = seconds >= 0 ? "Skipped ahead 15s" : "Went back 15s"
            let icon = seconds >= 0 ? "goforward.15" : "gobackward.15"
            showToast(icon: icon, title: title, subtitle: response.message)
        }
    }

    func scrubPlayback() {
        light("media:scrub")
        let normalized = min(max(playbackProgress, 0), 1)
        Task {
            guard let response = await perform(
                JeffreyRemoteBridgeRequest(action: "seek_media", value: normalized, source: activeSource),
                failureTitle: "Scrub failed",
                toastOnSuccess: false
            ) else { return }
            statusLine = response.message
            showToast(icon: "play.rectangle.fill", title: "Playback moved", subtitle: response.message)
        }
    }

    private func sliderAction(for title: String) -> (action: String, failureTitle: String)? {
        let action: String
        let failureTitle: String
        switch title {
        case "Volume":
            action = "set_volume"
            failureTitle = "Volume failed"
        case "Screen Brightness":
            action = "set_screen_brightness"
            failureTitle = "Screen brightness failed"
        case "Keyboard Brightness":
            action = "set_keyboard_brightness"
            failureTitle = "Keyboard brightness failed"
        default:
            return nil
        }
        return (action, failureTitle)
    }

    func sliderValueChanged(title: String, value: Double) {
        guard let mapping = sliderAction(for: title) else { return }
        pendingLevelRequests[title]?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task {
                _ = await self.perform(
                    JeffreyRemoteBridgeRequest(action: mapping.action, value: value, source: self.activeSource),
                    failureTitle: nil,
                    toastOnSuccess: false
                )
            }
        }
        pendingLevelRequests[title] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: workItem)
    }

    func sliderDidCommit(title: String, icon: String, value: Double) {
        light("slider:\(title)")
        guard let mapping = sliderAction(for: title) else {
            showToast(icon: icon, title: title, subtitle: "This slider is still visual in the prototype.")
            return
        }
        pendingLevelRequests[title]?.cancel()
        Task {
            guard let response = await perform(
                JeffreyRemoteBridgeRequest(action: mapping.action, value: value, source: activeSource),
                failureTitle: mapping.failureTitle,
                toastOnSuccess: false
            ) else { return }
            statusLine = response.message
            showToast(icon: icon, title: title, subtitle: response.message)
        }
    }

    func queueCursorMove(to point: CGPoint) {
        cursor = CGPoint(x: min(max(point.x, 0.001), 0.999), y: min(max(point.y, 0.001), 0.999))
        pendingCursorRequest?.cancel()
        let queuedPoint = cursor
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task {
                _ = await self.perform(
                    JeffreyRemoteBridgeRequest(
                        action: self.holdModeEnabled ? "drag_cursor" : "set_cursor",
                        x: Double(queuedPoint.x),
                        y: Double(queuedPoint.y),
                        source: self.activeSource
                    ),
                    failureTitle: "Cursor move failed",
                    toastOnSuccess: false
                )
            }
        }
        pendingCursorRequest = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: workItem)
    }

    func queueScroll(delta: CGSize) {
        scrollAccumulator.height += delta.height
        pendingScrollRequest?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let deltaX = 0.0
            let deltaY = -self.scrollAccumulator.height * 6.0
            self.scrollAccumulator = .zero
            Task {
                _ = await self.perform(
                    JeffreyRemoteBridgeRequest(action: "scroll", deltaX: Double(deltaX), deltaY: Double(deltaY), source: self.activeSource),
                    failureTitle: "Scroll failed",
                    toastOnSuccess: false
                )
            }
        }
        pendingScrollRequest = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: workItem)
    }

    func endRemoteGesture() {
        scrollAccumulator = .zero
    }

    func moveCursorFromCaptureViewer(location: CGPoint, size: CGSize) {
        guard let image = latestCaptureImage, image.size.width > 0, image.size.height > 0 else { return }

        let imageAspect = image.size.width / image.size.height
        let containerAspect = size.width / max(size.height, 1)
        let frame: CGRect

        if imageAspect > containerAspect {
            let width = size.width
            let height = width / imageAspect
            frame = CGRect(x: 0, y: (size.height - height) / 2.0, width: width, height: height)
        } else {
            let height = size.height
            let width = height * imageAspect
            frame = CGRect(x: (size.width - width) / 2.0, y: 0, width: width, height: height)
        }

        guard frame.width > 0, frame.height > 0 else { return }
        let adjustedLocation = CGPoint(
            x: min(max(location.x + max(frame.width * 0.18, 56), frame.minX), frame.maxX),
            y: min(max(location.y, frame.minY), frame.maxY)
        )
        let x = (adjustedLocation.x - frame.minX) / frame.width
        let y = (adjustedLocation.y - frame.minY) / frame.height
        let normalized = CGPoint(
            x: min(max(x, 0.001), 0.999),
            y: min(max(y, 0.001), 0.999)
        )
        queueCursorMove(to: normalized)
    }

    func moveCursorFromRotatedCaptureViewer(location: CGPoint, size: CGSize) {
        guard let image = latestCaptureImage, image.size.width > 0, image.size.height > 0 else { return }

        let frame = rotatedCaptureDisplayFrame(for: image.size, in: size)
        guard frame.width > 0, frame.height > 0 else { return }

        let adjustedLocation = CGPoint(
            x: min(max(location.x + max(frame.width * 0.18, 60), frame.minX), frame.maxX),
            y: min(max(location.y, frame.minY), frame.maxY)
        )

        let rotatedX = min(max((adjustedLocation.x - frame.minX) / frame.width, 0.001), 0.999)
        let rotatedY = min(max((adjustedLocation.y - frame.minY) / frame.height, 0.001), 0.999)

        let normalized = CGPoint(
            x: rotatedY,
            y: 1 - rotatedX
        )
        queueCursorMove(to: normalized)
    }

    func sendTypedText() {
        let text = keyboardDraft
        guard !text.isEmpty else {
            showToast(icon: "keyboard", title: "Nothing to send", subtitle: "Type something first, then send it to the Mac.")
            return
        }
        light("keyboard:send")
        Task {
            guard let response = await perform(
                JeffreyRemoteBridgeRequest(action: "type_text", command: text, source: activeSource),
                failureTitle: "Typing failed",
                toastOnSuccess: false
            ) else { return }
            statusLine = response.message
            keyboardDraft = ""
            showToast(icon: "keyboard.fill", title: "Typed remotely", subtitle: response.message)
        }
    }

    func sendSpecialKey(_ key: String) {
        light("keyboard:\(key)")
        Task {
            guard let response = await perform(
                JeffreyRemoteBridgeRequest(action: "key", command: key, source: activeSource),
                failureTitle: "Key send failed",
                toastOnSuccess: false
            ) else { return }
            statusLine = response.message
            showToast(icon: "return", title: "Sent \(key)", subtitle: response.message)
        }
    }

    func refreshAvailableApps(query: String? = nil) async {
        let queryText = (query ?? appQuery).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !connectionHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let response = await perform(
            JeffreyRemoteBridgeRequest(action: "list_apps", command: queryText, source: activeSource),
            failureTitle: nil,
            toastOnSuccess: false
        ) else { return }
        if let names = response.appNames {
            availableApps = names
        }
    }

    func isLit(_ key: String) -> Bool {
        litButtons.contains(key)
    }

    var filteredCommandSuggestions: [String] {
        let library = (
            JeffreyRemoteFixtures.workspaceDeck.map(\.command) +
            JeffreyRemoteFixtures.desktopDeck.map(\.command) +
            JeffreyRemoteFixtures.powerDeck.map(\.command) +
            JeffreyRemoteFixtures.appLaunchers.map(\.command) +
            [
                "gm",
                "good morning",
                "gm sh",
                "good morning sh",
                "sleep",
                "sleep all",
                "sleep mac",
                "lock mac",
                "go to d1",
                "go to d2",
                "go to d3",
                "open safari d2",
                "open spotify d3",
                "open whatsapp d3",
                "open notes d3",
                "close safari",
                "close spotify",
                "close notes"
            ]
        )
        let unique = Array(Set(library)).sorted()
        let query = customControlCommand.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return Array(unique.prefix(10)) }
        return unique.filter { $0.localizedCaseInsensitiveContains(query) }.prefix(12).map { $0 }
    }

    var filteredApps: [String] {
        let query = appQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        return availableApps.filter { $0.localizedCaseInsensitiveContains(query) }.prefix(24).map { $0 }
    }

    private func performMouseAction(_ action: String, title: String, subtitle: String) async {
        pendingCursorRequest?.cancel()
        pendingCursorRequest = nil

        if action == "click" || action == "double" || action == "right" {
            let _ = await perform(
                JeffreyRemoteBridgeRequest(
                    action: "set_cursor",
                    x: Double(cursor.x),
                    y: Double(cursor.y),
                    source: activeSource
                ),
                failureTitle: nil,
                toastOnSuccess: false
            )
        }

        guard let response = await perform(
            JeffreyRemoteBridgeRequest(action: "mouse_action", mouseAction: action, source: activeSource),
            failureTitle: title,
            toastOnSuccess: false
        ) else { return }
        statusLine = response.message
        showToast(icon: "cursorarrow.click.2", title: title, subtitle: subtitle)
    }

    private func ping(showFailure: Bool) async {
        guard let response = await perform(
            JeffreyRemoteBridgeRequest(action: "ping", source: activeSource),
            failureTitle: showFailure ? "Connection failed" : nil,
            toastOnSuccess: false
        ) else { return }
        statusLine = response.message
        if showFailure || !isConnected {
            showToast(icon: "wifi", title: "Connected", subtitle: response.message)
        }
    }

    private func perform(
        _ request: JeffreyRemoteBridgeRequest,
        failureTitle: String?,
        toastOnSuccess: Bool = false
    ) async -> JeffreyRemoteBridgeResponse? {
        let host = connectionHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty || connectedEndpoint != nil else {
            showingConnectionSheet = true
            showToast(icon: "wifi.slash", title: "Connect first", subtitle: "Tap CONNECTED and choose your Mac or enter its host.")
            return nil
        }

        do {
            let response: JeffreyRemoteBridgeResponse
            if let connectedEndpoint {
                response = try await bridgeClient.send(request, endpoint: connectedEndpoint)
            } else {
                response = try await bridgeClient.send(request, host: host)
            }
            apply(response)
            if !response.ok, let failureTitle {
                showToast(icon: "exclamationmark.triangle.fill", title: failureTitle, subtitle: response.message)
            } else if toastOnSuccess {
                showToast(icon: "checkmark.circle.fill", title: "Done", subtitle: response.message)
            }
            return response
        } catch {
            isConnected = false
            connectionLabel = !host.isEmpty ? host : connectionLabel
            statusLine = error.localizedDescription

            let recovered = await recoverConnection(showToast: false, aggressive: false)
            if recovered, request.isSafeToRetryAfterReconnect {
                do {
                    let retryResponse: JeffreyRemoteBridgeResponse
                    let retryHost = connectionHost.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let connectedEndpoint {
                        retryResponse = try await bridgeClient.send(request, endpoint: connectedEndpoint)
                    } else {
                        retryResponse = try await bridgeClient.send(request, host: retryHost)
                    }
                    apply(retryResponse)
                    if !retryResponse.ok, let failureTitle {
                        showToast(icon: "exclamationmark.triangle.fill", title: failureTitle, subtitle: retryResponse.message)
                    } else if toastOnSuccess {
                        showToast(icon: "checkmark.circle.fill", title: "Done", subtitle: retryResponse.message)
                    }
                    return retryResponse
                } catch {
                    statusLine = error.localizedDescription
                }
            }

            if let failureTitle {
                let subtitle = recovered
                    ? "Jeffrey reconnected, but this action needs one more try."
                    : error.localizedDescription
                showToast(icon: "wifi.slash", title: failureTitle, subtitle: subtitle)
            }
            return nil
        }
    }

    private func apply(_ response: JeffreyRemoteBridgeResponse) {
        isConnected = response.ok || response.hostName != nil
        if let hostName = response.hostName, !hostName.isEmpty {
            connectionLabel = hostName
        } else if !connectionHost.isEmpty {
            connectionLabel = connectionHost
        }

        if let x = response.cursorX, let y = response.cursorY {
            cursor = CGPoint(x: x, y: y)
        }

        if let media = response.media {
            if let matchingSource = JeffreyRemoteFixtures.mediaSources.first(where: {
                media.source.localizedCaseInsensitiveContains($0)
            }) {
                activeSource = matchingSource
            }
            mediaTitle = media.title
            mediaSubtitle = media.subtitle
            mediaContext = media.source
            isPlaying = media.isPlaying
            volume = media.volume
            mediaArtworkURL = media.artworkURL.flatMap(URL.init(string:))
            mediaDuration = max(media.duration ?? 0, 0)
            mediaCurrentTime = min(max(media.currentTime ?? 0, 0), mediaDuration > 0 ? mediaDuration : .greatestFiniteMagnitude)
            playbackProgress = mediaDuration > 0 ? min(max(mediaCurrentTime / mediaDuration, 0.0), 1.0) : 0.0
        }

        if let screenBrightness = response.screenBrightness {
            self.screenBrightness = screenBrightness
        }

        if let keyboardBrightness = response.keyboardBrightness {
            self.keyboardBrightness = keyboardBrightness
        }

        if let keepAwakeUntil = response.keepAwakeUntil, keepAwakeUntil > 0 {
            self.keepAwakeUntil = Date(timeIntervalSince1970: keepAwakeUntil)
        } else {
            self.keepAwakeUntil = nil
        }

        if let batteryLevel = response.batteryLevel {
            self.macBatteryLevel = batteryLevel
        }

        if let screenshotBase64 = response.screenshotBase64,
           let data = Data(base64Encoded: screenshotBase64),
           let image = UIImage(data: data) {
            latestCaptureImage = image
        }

        if let appNames = response.appNames, !appNames.isEmpty {
            availableApps = appNames
        }
    }

    private func light(_ key: String, duration: TimeInterval = 0.65) {
        pendingButtonReset[key]?.cancel()
        _ = withAnimation(.easeOut(duration: 0.18)) {
            litButtons.insert(key)
        }
        let workItem = DispatchWorkItem { [weak self] in
            _ = withAnimation(interactionFadeAnimation) {
                self?.litButtons.remove(key)
            }
            self?.pendingButtonReset[key] = nil
        }
        pendingButtonReset[key] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func normalizedAppCommand(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let lower = trimmed.lowercased()
        let explicitPrefixes = ["open ", "close ", "quit ", "sleep "]
        if explicitPrefixes.contains(where: { lower.hasPrefix($0) }) {
            return trimmed
        }

        return "open \(trimmed)"
    }

    private var hasConnectionTarget: Bool {
        !connectionHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || connectedEndpoint != nil || preferredServiceID != nil
    }

    private func startHealthMonitorIfNeeded() {
        guard healthMonitorTask == nil else { return }
        healthMonitorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                guard self.hasConnectionTarget else { continue }
                _ = await self.recoverConnection(showToast: false, aggressive: false)
            }
        }
    }

    private func recoverConnection(showToast showReconnectToast: Bool, aggressive: Bool) async -> Bool {
        guard !isReconnecting else { return false }
        isReconnecting = true
        defer { isReconnecting = false }

        if connectionMode == .tailscale {
            connectedEndpoint = nil
        } else {
            discoveryService.start(forceRestart: aggressive)
        }

        if connectionMode != .tailscale,
           let preferredServiceID,
           let refreshedMatch = discoveredMacs.first(where: { $0.id == preferredServiceID }) {
            connectedEndpoint = refreshedMatch.endpoint
            connectionLabel = refreshedMatch.name
        }

        let attempts = aggressive ? 6 : 3

        for attempt in 0..<attempts {
            if let response = await attemptPingViaCurrentTarget() {
                apply(response)
                if showReconnectToast {
                    showToast(icon: "wifi", title: "Reconnected", subtitle: response.message)
                }
                return true
            }

            if attempt < attempts - 1 {
                try? await Task.sleep(for: .milliseconds((aggressive ? 500 : 700) * (attempt + 1)))
                if connectionMode != .tailscale {
                    discoveryService.start(forceRestart: aggressive)
                }
                if connectionMode != .tailscale,
                   let preferredServiceID,
                   let refreshedMatch = discoveredMacs.first(where: { $0.id == preferredServiceID }) {
                    connectedEndpoint = refreshedMatch.endpoint
                    connectionLabel = refreshedMatch.name
                }
            }
        }

        return false
    }

    private func attemptPingViaCurrentTarget() async -> JeffreyRemoteBridgeResponse? {
        let request = JeffreyRemoteBridgeRequest(action: "ping", source: activeSource)
        let trimmedHost = connectionHost.trimmingCharacters(in: .whitespacesAndNewlines)

        if connectionMode == .tailscale {
            guard !trimmedHost.isEmpty else { return nil }
            return try? await bridgeClient.send(request, host: trimmedHost)
        }

        if let connectedEndpoint,
           let response = try? await bridgeClient.send(request, endpoint: connectedEndpoint) {
            return response
        }

        if !trimmedHost.isEmpty,
           let response = try? await bridgeClient.send(request, host: trimmedHost) {
            return response
        }

        return nil
    }
}

private extension JeffreyRemoteBridgeRequest {
    var isSafeToRetryAfterReconnect: Bool {
        switch action {
        case "ping", "screenshot", "media_state", "list_apps", "set_cursor", "drag_cursor", "scroll", "set_volume", "set_screen_brightness", "set_keyboard_brightness", "keep_awake", "wake_mac":
            return true
        default:
            return false
        }
    }
}

private let interactionFadeAnimation = Animation.easeOut(duration: 0.85)

private enum JeffreyPalette {
    static let backgroundTop = Color(red: 0.015, green: 0.02, blue: 0.05)
    static let backgroundBottom = Color(red: 0.04, green: 0.035, blue: 0.10)
    static let panel = Color(red: 0.08, green: 0.085, blue: 0.13)
    static let panelRaised = Color(red: 0.10, green: 0.10, blue: 0.16)
    static let surfaceStart = Color(red: 0.12, green: 0.15, blue: 0.38)
    static let surfaceMid = Color(red: 0.18, green: 0.13, blue: 0.36)
    static let surfaceEnd = Color(red: 0.08, green: 0.11, blue: 0.23)
    static let cyan = Color(red: 0.15, green: 0.86, blue: 0.97)
    static let cyanSoft = Color(red: 0.22, green: 0.77, blue: 0.95)
    static let stroke = Color.white.opacity(0.08)
    static let strokeStrong = Color.white.opacity(0.14)
    static let textSecondary = Color.white.opacity(0.62)
    static let textMuted = Color.white.opacity(0.42)
}

struct ContentView: View {
    @StateObject private var state = JeffreyRemotePrototypeState()
    @State private var showWelcomeOverlay = true
    @State private var animateWelcomeHeart = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack(alignment: .bottom) {
            appBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Group {
                    switch state.selectedTab {
                    case .remote:
                        RemoteTabView(state: state)
                    case .controls:
                        ControlsTabView(state: state)
                    case .media:
                        MediaTabView(state: state)
                    case .apps:
                        AppsTabView(state: state)
                    case .voice:
                        VoiceTabView(state: state)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                BottomTabBar(selectedTab: $state.selectedTab)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
            }

            if let toast = state.toast {
                ToastBanner(toast: toast)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 92)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showWelcomeOverlay {
                WelcomeOverlay(isAnimating: animateWelcomeHeart)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await state.bootstrapConnection()
        }
        .onAppear {
            animateWelcomeHeart = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) {
                withAnimation(.easeOut(duration: 0.45)) {
                    showWelcomeOverlay = false
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            Task {
                await state.handleScenePhaseChange(phase)
            }
        }
        .sheet(isPresented: $state.showingConnectionSheet) {
            ConnectionSheet(state: state)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .sheet(isPresented: $state.showingKeyboardSheet) {
            RemoteKeyboardSheet(state: state)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .sheet(isPresented: $state.showingKeepAwakeSheet) {
            KeepAwakeSheet(state: state)
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .fullScreenCover(isPresented: $state.showingCaptureViewer) {
            CaptureViewer(state: state)
        }
    }

    private var appBackground: some View {
        ZStack {
            LinearGradient(
                colors: [JeffreyPalette.backgroundTop, JeffreyPalette.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [JeffreyPalette.cyan.opacity(0.14), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 420
            )
            .blur(radius: 12)

            RadialGradient(
                colors: [Color(red: 0.22, green: 0.16, blue: 0.58).opacity(0.22), .clear],
                center: .center,
                startRadius: 20,
                endRadius: 360
            )
            .blendMode(.screen)
        }
    }
}

private struct RemoteTabView: View {
    @ObservedObject var state: JeffreyRemotePrototypeState
    private let surfaceAspectRatio: CGFloat = 1512.0 / 982.0
    @State private var lastScrollTranslation: CGSize = .zero

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                header
                statusCards
                remoteSurfaceCard
                controlGrid
                keyboardAndPadRow
                footerSignature
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    Text(Date(), style: .time)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                    HStack(spacing: 5) {
                        Image(systemName: state.macBatterySymbol)
                            .font(.system(size: 12, weight: .bold))
                        Text(state.macBatteryText)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(JeffreyPalette.cyan)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(JeffreyPalette.panelRaised.opacity(0.94)))
                    .overlay(Capsule().stroke(JeffreyPalette.cyan.opacity(0.22), lineWidth: 1))
                }
                Spacer()
                if state.isReconnecting {
                    HStack(spacing: 6) {
                        ProgressView()
                            .tint(.orange)
                            .scaleEffect(0.7)
                        Text("RECONNECTING")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.orange.opacity(0.95))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(JeffreyPalette.panelRaised.opacity(0.96)))
                    .overlay(Capsule().stroke(Color.orange.opacity(0.28), lineWidth: 1))
                }
                HStack(spacing: 6) {
                    Circle()
                        .fill(JeffreyPalette.cyan)
                        .frame(width: 7, height: 7)
                        .shadow(color: JeffreyPalette.cyan.opacity(0.82), radius: 8)
                    Text("LIVE")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(JeffreyPalette.cyan)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(JeffreyPalette.panelRaised.opacity(0.94)))
                .overlay(Capsule().stroke(JeffreyPalette.cyan.opacity(0.26), lineWidth: 1))

                headerIconButton(
                    icon: "arrow.clockwise",
                    key: "connection:reconnect",
                    colors: [Color.orange, JeffreyPalette.cyan],
                    action: state.reconnectNow
                )
                headerIconButton(
                    icon: "bolt.fill",
                    key: "power:keepawake",
                    colors: [Color(red: 0.99, green: 0.76, blue: 0.28), Color(red: 0.55, green: 0.38, blue: 1.0)],
                    persistentlyActive: state.keepAwakeUntil != nil,
                    action: state.presentKeepAwakeConfigurator
                )
                headerIconButton(
                    icon: "display",
                    key: "power:wakemac",
                    colors: [Color(red: 1.0, green: 0.70, blue: 0.31), Color(red: 1.0, green: 0.47, blue: 0.33)],
                    action: state.triggerWakeMac
                )
                headerIconButton(
                    icon: "figure.wave",
                    key: "wake:goodmorning",
                    colors: [JeffreyPalette.cyan, Color(red: 0.63, green: 0.44, blue: 1.0)],
                    action: state.triggerGoodMorning
                )
            }

            HStack(spacing: 5) {
                Text("Jeffrey")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Remote")
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .foregroundStyle(JeffreyPalette.cyanSoft)
            }
        }
    }

    private func headerIconButton(icon: String, key: String, colors: [Color], persistentlyActive: Bool = false, action: @escaping () -> Void) -> some View {
        let isActive = persistentlyActive || state.isLit(key)
        return Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isActive ? .black : .white)
                .frame(width: 32, height: 32)
                .background(
                    Capsule()
                        .fill(
                            isActive
                            ? LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [JeffreyPalette.panelRaised.opacity(0.94), JeffreyPalette.panel.opacity(0.96)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .overlay(
                            Capsule()
                                .stroke(isActive ? colors.first?.opacity(0.75) ?? JeffreyPalette.cyan.opacity(0.75) : JeffreyPalette.strokeStrong, lineWidth: 1)
                        )
                )
                .shadow(color: colors.first?.opacity(isActive ? 0.30 : 0.10) ?? JeffreyPalette.cyan.opacity(0.1), radius: 10)
        }
        .buttonStyle(PressableScaleButtonStyle(scale: 0.96))
        .animation(interactionFadeAnimation, value: isActive)
    }

    private var statusCards: some View {
        HStack(spacing: 10) {
            statusCard(
                eyebrow: "CONNECTED",
                icon: state.isConnected ? "circle.fill" : "wifi.slash",
                iconTint: state.isConnected ? JeffreyPalette.cyan : .orange,
                value: state.connectionLabel,
                action: state.openConnectionSettings
            )
            statusCard(eyebrow: "CAPTURE", icon: "camera.aperture", iconTint: JeffreyPalette.textMuted, value: state.captureLabel)
        }
    }

    private var awakeGuardCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AWAKE GUARD")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.7)
                        .foregroundStyle(JeffreyPalette.textSecondary)
                    Text(state.keepAwakeStatusTitle)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer()
                Text(state.keepAwakeBadgeText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(state.keepAwakeUntil != nil ? JeffreyPalette.cyan : JeffreyPalette.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.white.opacity(0.05)))
                    .overlay(Capsule().stroke((state.keepAwakeUntil != nil ? JeffreyPalette.cyan.opacity(0.26) : JeffreyPalette.strokeStrong), lineWidth: 1))
            }

            Text("Use Keep Awake before heading out. If the screen still goes dark, Wake Mac gives it a direct nudge.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(JeffreyPalette.textSecondary)

            HStack(spacing: 10) {
                compactPowerButton(
                    title: state.keepAwakeUntil != nil ? "Extend 2h" : "Keep Awake 2h",
                    icon: "bolt.badge.clock.fill",
                    active: state.isLit("power:keepawake"),
                    colors: [Color(red: 0.16, green: 0.86, blue: 0.97), Color(red: 0.53, green: 0.45, blue: 1.0)],
                    action: { state.triggerKeepAwake() }
                )
                compactPowerButton(
                    title: "Wake Mac",
                    icon: "display",
                    active: state.isLit("power:wakemac"),
                    colors: [Color(red: 1.0, green: 0.71, blue: 0.28), Color(red: 1.0, green: 0.45, blue: 0.33)],
                    action: state.triggerWakeMac
                )
            }
        }
        .padding(14)
        .background(panelCard(corner: 18))
    }

    private func statusCard(
        eyebrow: String,
        icon: String,
        iconTint: Color,
        value: String,
        action: (() -> Void)? = nil
    ) -> some View {
        Group {
            if let action {
                Button(action: action) {
                    statusCardBody(eyebrow: eyebrow, icon: icon, iconTint: iconTint, value: value)
                }
                .buttonStyle(PressableScaleButtonStyle(scale: 0.985))
            } else {
                statusCardBody(eyebrow: eyebrow, icon: icon, iconTint: iconTint, value: value)
            }
        }
    }

    private func statusCardBody(eyebrow: String, icon: String, iconTint: Color, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(iconTint)
                Text(eyebrow)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.05)
                    .foregroundStyle(JeffreyPalette.textSecondary)
                if eyebrow == "CONNECTED" {
                    Spacer(minLength: 0)
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(JeffreyPalette.textMuted)
                }
            }
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(1)
            if eyebrow == "CONNECTED" {
                HStack(spacing: 4) {
                    Image(systemName: state.connectionMode.icon)
                        .font(.system(size: 9, weight: .bold))
                    Text(state.connectionMode.title.uppercased())
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                }
                .foregroundStyle(state.isConnected ? JeffreyPalette.cyan.opacity(0.68) : JeffreyPalette.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(panelCard(corner: 16))
    }

    private var remoteSurfaceCard: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 8, height: 8)
                    Circle().fill(Color(red: 1.0, green: 0.79, blue: 0.27)).frame(width: 8, height: 8)
                    Circle().fill(Color(red: 0.14, green: 0.85, blue: 0.45)).frame(width: 8, height: 8)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                GeometryReader { proxy in
                    let frame = remoteDisplayFrame(in: proxy.size)
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [JeffreyPalette.surfaceStart, JeffreyPalette.surfaceMid, JeffreyPalette.surfaceEnd],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        if let image = state.latestCaptureImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: frame.width, height: frame.height)
                                .clipped()
                                .opacity(0.58)
                                .position(x: frame.midX, y: frame.midY)
                        }

                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.black.opacity(0.02), Color.black.opacity(0.18)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(JeffreyPalette.cyan.opacity(0.09), lineWidth: 1)
                            )

                        SurfaceLineCluster()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(.top, 20)
                            .padding(.leading, 14)

                        if state.latestCaptureImage == nil {
                            VStack(spacing: 10) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.system(size: 30, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.64))
                                Text("Tap the camera to sync a real screenshot from your Mac.")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.62))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 36)
                            }
                        }

                        CursorIndicator(cursor: state.cursor, frame: frame)
                            .mask(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                            )
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let normalizedPoint = normalizedCursorPoint(
                                    from: value.location,
                                    in: proxy.size
                                )
                                if state.scrollModeEnabled {
                                    let delta = CGSize(
                                        width: 0,
                                        height: value.translation.height - lastScrollTranslation.height
                                    )
                                    lastScrollTranslation = value.translation
                                    state.queueScroll(delta: delta)
                                } else {
                                    state.queueCursorMove(to: normalizedPoint)
                                }
                            }
                            .onEnded { _ in
                                lastScrollTranslation = .zero
                                state.endRemoteGesture()
                            }
                    )
                }
                .aspectRatio(surfaceAspectRatio, contentMode: .fit)
                .padding(.horizontal, 6)
                .padding(.bottom, 10)

                HStack {
                    Text(state.remoteModeLabel)
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1.45)
                        .foregroundStyle(JeffreyPalette.cyan.opacity(0.76))
                    Spacer()
                    Text("LIVE PREVIEW")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1.3)
                        .foregroundStyle(JeffreyPalette.cyan.opacity(0.76))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(JeffreyPalette.panelRaised.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(JeffreyPalette.cyan.opacity(0.12), lineWidth: 1)
                    )
            )

            HStack(spacing: 8) {
                Button(action: state.openCaptureViewer) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(state.isLit("capture:viewer") ? .black : .white)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(state.isLit("capture:viewer") ? LinearGradient(colors: [Color(red: 0.66, green: 0.44, blue: 1.0), JeffreyPalette.cyan], startPoint: .topLeading, endPoint: .bottomTrailing) : LinearGradient(colors: [JeffreyPalette.panel], startPoint: .top, endPoint: .bottom))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(state.isLit("capture:viewer") ? JeffreyPalette.cyan.opacity(0.9) : JeffreyPalette.strokeStrong, lineWidth: 1)
                                )
                        )
                        .shadow(color: JeffreyPalette.cyan.opacity(state.isLit("capture:viewer") ? 0.72 : 0.24), radius: 14)
                }
                .buttonStyle(PressableScaleButtonStyle())
                .animation(interactionFadeAnimation, value: state.isLit("capture:viewer"))

                Button(action: state.triggerCapture) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(state.isLit("capture") ? .black : .white)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(state.isLit("capture") ? LinearGradient(colors: [JeffreyPalette.cyan, .white], startPoint: .topLeading, endPoint: .bottomTrailing) : LinearGradient(colors: [JeffreyPalette.panel], startPoint: .top, endPoint: .bottom))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(state.isLit("capture") ? JeffreyPalette.cyan.opacity(0.9) : JeffreyPalette.cyan.opacity(0.7), lineWidth: 1)
                                )
                        )
                        .shadow(color: JeffreyPalette.cyan.opacity(state.isLit("capture") ? 0.72 : 0.34), radius: 14)
                }
                .buttonStyle(PressableScaleButtonStyle())
                .animation(interactionFadeAnimation, value: state.isLit("capture"))
            }
            .padding(14)
        }
    }

    private var controlGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                controlButton(.cursor)
                actionButton(.click)
                actionButton(.hold)
            }
            HStack(spacing: 10) {
                actionButton(.double)
                actionButton(.right)
                actionButton(.scroll)
            }
        }
    }

    private func controlButton(_ mode: RemoteMode) -> some View {
        RemoteControlButton(
            title: mode.rawValue,
            icon: mode.icon,
            active: state.isLit("remote:\(mode.rawValue)"),
            action: { state.chooseRemoteMode(mode) }
        )
    }

    private func actionButton(_ action: RemoteMode) -> some View {
        switch action {
        case .hold:
            return AnyView(
                RemoteMomentaryControlButton(
                    title: action.rawValue,
                    icon: action.icon,
                    active: state.holdModeEnabled,
                    onPressBegan: { state.beginHoldMode() },
                    onPressEnded: { state.endHoldMode() }
                )
            )
        case .scroll:
            return AnyView(
                RemoteMomentaryControlButton(
                    title: action.rawValue,
                    icon: action.icon,
                    active: state.scrollModeEnabled,
                    onPressBegan: { state.beginScrollMode() },
                    onPressEnded: { state.endScrollMode() }
                )
            )
        default:
            return AnyView(
                RemoteControlButton(
                    title: action.rawValue,
                    icon: action.icon,
                    active: state.isLit("remote:\(action.rawValue)"),
                    action: { state.triggerRemoteAction(action) }
                )
            )
        }
    }

    private var keyboardAndPadRow: some View {
        HStack(spacing: 10) {
            Button(action: state.triggerKeyboard) {
                HStack(spacing: 8) {
                    Image(systemName: "textformat")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Keyboard")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(state.isLit("keyboard") ? .black : .white.opacity(0.65))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(state.isLit("keyboard") ? LinearGradient(colors: [Color(red: 0.64, green: 0.38, blue: 1.0), JeffreyPalette.cyan], startPoint: .topLeading, endPoint: .bottomTrailing) : LinearGradient(colors: [JeffreyPalette.panel.opacity(0.92)], startPoint: .top, endPoint: .bottom))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(state.isLit("keyboard") ? JeffreyPalette.cyan.opacity(0.85) : JeffreyPalette.strokeStrong, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(PressableScaleButtonStyle())
            .animation(interactionFadeAnimation, value: state.isLit("keyboard"))

            VStack(spacing: 6) {
                arrowButton(symbol: "chevron.up", label: "up")
                HStack(spacing: 6) {
                    arrowButton(symbol: "chevron.left", label: "left")
                    arrowButton(symbol: "chevron.down", label: "down")
                    arrowButton(symbol: "chevron.right", label: "right")
                }
            }
        }
    }

    private var footerSignature: some View {
        Text("Jeffrey created by mr bosch.")
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(JeffreyPalette.textSecondary.opacity(0.86))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 6)
    }

    private func arrowButton(symbol: String, label: String) -> some View {
        Button(action: { state.triggerArrow(label) }) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(state.isLit("arrow:\(label)") ? .black : .white.opacity(0.76))
                .frame(width: 34, height: 23)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(state.isLit("arrow:\(label)") ? LinearGradient(colors: [JeffreyPalette.cyan, .white], startPoint: .topLeading, endPoint: .bottomTrailing) : LinearGradient(colors: [JeffreyPalette.panel.opacity(0.92)], startPoint: .top, endPoint: .bottom))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(state.isLit("arrow:\(label)") ? JeffreyPalette.cyan.opacity(0.85) : JeffreyPalette.strokeStrong, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(PressableScaleButtonStyle(scale: 0.94))
        .animation(interactionFadeAnimation, value: state.isLit("arrow:\(label)"))
    }

    private func compactPowerButton(
        title: String,
        icon: String,
        active: Bool,
        colors: [Color],
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(active ? .black : .white.opacity(0.88))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(active ? LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) : LinearGradient(colors: [JeffreyPalette.panel.opacity(0.92)], startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(active ? colors.first?.opacity(0.72) ?? JeffreyPalette.cyan.opacity(0.72) : JeffreyPalette.strokeStrong, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PressableScaleButtonStyle(scale: 0.97))
        .animation(interactionFadeAnimation, value: active)
    }

    private var sysVitalsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("SYS VITALS")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(JeffreyPalette.textSecondary)
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(JeffreyPalette.cyan).frame(width: 5, height: 5)
                    Text("NOMINAL")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1.3)
                        .foregroundStyle(JeffreyPalette.cyan)
                }
            }

            HStack(spacing: 10) {
                vitalChip(title: "Latency", value: "14ms", tint: .cyan)
                vitalChip(title: "Apps", value: "6", tint: .purple)
                vitalChip(title: "Mic", value: "Idle", tint: .mint)
            }

            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(JeffreyPalette.cyan)
                Text(state.statusLine)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(panelCard(corner: 18))
    }

    private func vitalChip(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.13))
                    .frame(width: 34, height: 34)
                Circle()
                    .stroke(tint.opacity(0.45), lineWidth: 1)
                    .frame(width: 28, height: 28)
            }
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(JeffreyPalette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }

    private func panelCard(corner: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(JeffreyPalette.panel.opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(JeffreyPalette.stroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 12, y: 4)
    }

    private func remoteDisplayFrame(in size: CGSize) -> CGRect {
        let imageAspect = state.latestCaptureImage.map { $0.size.width / max($0.size.height, 1) } ?? surfaceAspectRatio
        let containerAspect = size.width / max(size.height, 1)

        if imageAspect > containerAspect {
            let width = size.width
            let height = width / imageAspect
            return CGRect(x: 0, y: (size.height - height) / 2.0, width: width, height: height)
        } else {
            let height = size.height
            let width = height * imageAspect
            return CGRect(x: (size.width - width) / 2.0, y: 0, width: width, height: height)
        }
    }

    private func normalizedCursorPoint(from location: CGPoint, in size: CGSize) -> CGPoint {
        let frame = remoteDisplayFrame(in: size)
        let adjustedLocation = pointWithCursorReach(
            from: location,
            in: frame,
            xOffset: max(frame.width * 0.18, 56),
            yOffset: 0
        )
        return normalizedPoint(from: adjustedLocation, in: frame)
    }

    private func pointWithCursorReach(from location: CGPoint, in frame: CGRect, xOffset: CGFloat, yOffset: CGFloat) -> CGPoint {
        CGPoint(
            x: min(max(location.x + xOffset, frame.minX), frame.maxX),
            y: min(max(location.y + yOffset, frame.minY), frame.maxY)
        )
    }

    private func normalizedPoint(from location: CGPoint, in frame: CGRect) -> CGPoint {
        guard frame.width > 0, frame.height > 0 else {
            return CGPoint(x: 0.5, y: 0.5)
        }

        let x = (location.x - frame.minX) / frame.width
        let y = (location.y - frame.minY) / frame.height
        return CGPoint(
            x: min(max(x, 0.001), 0.999),
            y: min(max(y, 0.001), 0.999)
        )
    }
}

private struct ControlsTabView: View {
    @ObservedObject var state: JeffreyRemotePrototypeState
    private let grid = [GridItem(.flexible())]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                TopSectionHeader(title: "Control Deck", subtitle: "Wake, route desktops, launch apps and control power.")

                customCommandPanel

                CommandDeckSection(title: "Wake & Workspace", caption: "The first things you reach for.") {
                    LazyVGrid(columns: grid, spacing: 10) {
                        ForEach(JeffreyRemoteFixtures.workspaceDeck) { command in
                            TacticalCommandCard(command: command, isActive: state.isLit("command:\(command.command)")) {
                                state.triggerCommand(command)
                            }
                        }
                    }
                }

                CommandDeckSection(title: "Desktop Routing", caption: "Quick jumps between Jeffrey spaces.") {
                    LazyVGrid(columns: grid, spacing: 10) {
                        ForEach(JeffreyRemoteFixtures.desktopDeck) { command in
                            TacticalCommandCard(command: command, isActive: state.isLit("command:\(command.command)")) {
                                state.triggerCommand(command)
                            }
                        }
                    }
                }

                CommandDeckSection(title: "Power & Shutdown", caption: "Lock, sleep or close the workspace with intention.") {
                    LazyVGrid(columns: grid, spacing: 10) {
                        ForEach(JeffreyRemoteFixtures.powerDeck) { command in
                            TacticalCommandCard(command: command, isActive: state.isLit("command:\(command.command)")) {
                                state.triggerCommand(command)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
    }

    private var customCommandPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Any Jeffrey Command")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(JeffreyPalette.textSecondary)
                    TextField("Type any Jeffrey command, e.g. open safari d3", text: $state.customControlCommand)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .foregroundStyle(.white)
                        .onSubmit {
                            state.triggerCustomControlCommand()
                        }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(sectionPanel)

                Button(action: state.triggerCustomControlCommand) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 54, height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(LinearGradient(colors: [JeffreyPalette.cyan, Color(red: 0.43, green: 0.63, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                }
                .buttonStyle(PressableScaleButtonStyle())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(state.filteredCommandSuggestions, id: \.self) { command in
                        Button {
                            state.customControlCommand = command
                            state.triggerCustomControlCommand()
                        } label: {
                            Text(command)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(JeffreyPalette.panelRaised.opacity(0.96))
                                        .overlay(
                                            Capsule()
                                                .stroke(JeffreyPalette.strokeStrong, lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(PressableScaleButtonStyle(scale: 0.97))
                    }
                }
            }
        }
    }
}

private struct MediaTabView: View {
    @ObservedObject var state: JeffreyRemotePrototypeState

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                TopSectionHeader(title: "Media Control", subtitle: "Transport, volume and brightness — all from here.")

                sourcePicker
                nowPlayingCard
                transportRow
                levelsPanel
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .task {
            state.chooseSource(state.activeSource)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.4))
                state.chooseSource(state.activeSource)
            }
        }
    }

    private var sourcePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(JeffreyRemoteFixtures.mediaSources, id: \.self) { source in
                    Button(action: { state.chooseSource(source) }) {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(state.activeSource == source ? JeffreyPalette.cyan : Color.white.opacity(0.18))
                                .frame(width: 7, height: 7)
                            Text(source)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(state.isLit("source:\(source)") ? LinearGradient(colors: [JeffreyPalette.cyan.opacity(0.95), Color(red: 0.35, green: 0.45, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing) : LinearGradient(colors: [state.activeSource == source ? JeffreyPalette.cyan.opacity(0.12) : JeffreyPalette.panel.opacity(0.92)], startPoint: .top, endPoint: .bottom))
                                .overlay(
                                    Capsule()
                                        .stroke(state.isLit("source:\(source)") ? JeffreyPalette.cyan.opacity(0.85) : (state.activeSource == source ? JeffreyPalette.cyan.opacity(0.7) : JeffreyPalette.strokeStrong), lineWidth: 1)
                                )
                        )
                        .foregroundStyle(state.isLit("source:\(source)") ? .black : (state.activeSource == source ? JeffreyPalette.cyan : .white.opacity(0.78)))
                    }
                    .buttonStyle(PressableScaleButtonStyle(scale: 0.97))
                    .animation(interactionFadeAnimation, value: state.isLit("source:\(source)"))
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var nowPlayingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                artworkTile

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(state.isPlaying ? "PLAYING" : "READY")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .tracking(1.5)
                            .foregroundStyle(state.isPlaying ? JeffreyPalette.cyan : JeffreyPalette.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(state.isPlaying ? JeffreyPalette.cyan.opacity(0.14) : Color.white.opacity(0.05))
                                    .overlay(
                                        Capsule()
                                            .stroke(state.isPlaying ? JeffreyPalette.cyan.opacity(0.32) : JeffreyPalette.stroke, lineWidth: 1)
                                    )
                            )
                        Spacer()
                    }
                    Text(state.mediaTitle)
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(state.mediaSubtitle)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(JeffreyPalette.textSecondary)
                    Text(state.mediaContext)
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(0.9)
                        .foregroundStyle(JeffreyPalette.cyan)
                }
                Spacer()
            }

            InteractiveSlider(value: $state.playbackProgress, tint: JeffreyPalette.cyan, isEnabled: state.mediaDuration > 0) {
            } onEditingEnded: {
                state.scrubPlayback()
            }

            HStack {
                Text(timeLabel(for: state.mediaCurrentTime))
                Spacer()
                Text(timeLabel(for: state.mediaDuration))
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(JeffreyPalette.textSecondary)
        }
        .padding(16)
        .background(
            sectionPanel
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [JeffreyPalette.cyan.opacity(0.08), Color.clear, Color(red: 0.48, green: 0.32, blue: 1.0).opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        )
    }

    private var transportRow: some View {
        HStack(spacing: 10) {
            Button { state.seekRelative(seconds: -15) } label: {
                let isActive = state.isLit("media:backward15")
                VStack(spacing: 5) {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 20, weight: .bold))
                    Text("−15s")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                .foregroundStyle(isActive ? .black : .white.opacity(0.88))
                .frame(maxWidth: .infinity)
                .frame(height: 72)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isActive ? LinearGradient(colors: [JeffreyPalette.cyan, .white.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing) : LinearGradient(colors: [JeffreyPalette.panel.opacity(0.93)], startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(isActive ? JeffreyPalette.cyan.opacity(0.8) : JeffreyPalette.strokeStrong, lineWidth: 1))
                )
            }
            .buttonStyle(PressableScaleButtonStyle())
            .animation(interactionFadeAnimation, value: state.isLit("media:backward15"))

            Button(action: state.togglePlayback) {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(LinearGradient(colors: [JeffreyPalette.cyan, Color(red: 0.32, green: 0.62, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(JeffreyPalette.cyan.opacity(0.5), lineWidth: 1))
                            .shadow(color: JeffreyPalette.cyan.opacity(state.isPlaying ? 0.45 : 0.22), radius: 14, y: 4)
                    )
            }
            .buttonStyle(PressableScaleButtonStyle())
            .animation(interactionFadeAnimation, value: state.isLit("media:playpause"))

            Button { state.seekRelative(seconds: 15) } label: {
                let isActive = state.isLit("media:forward15")
                VStack(spacing: 5) {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 20, weight: .bold))
                    Text("+15s")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                .foregroundStyle(isActive ? .black : .white.opacity(0.88))
                .frame(maxWidth: .infinity)
                .frame(height: 72)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isActive ? LinearGradient(colors: [JeffreyPalette.cyan, .white.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing) : LinearGradient(colors: [JeffreyPalette.panel.opacity(0.93)], startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(isActive ? JeffreyPalette.cyan.opacity(0.8) : JeffreyPalette.strokeStrong, lineWidth: 1))
                )
            }
            .buttonStyle(PressableScaleButtonStyle())
            .animation(interactionFadeAnimation, value: state.isLit("media:forward15"))
        }
    }

    private var artworkTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.green, JeffreyPalette.cyan, Color.indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 96, height: 96)

            if let artworkURL = state.mediaArtworkURL {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        SpinningRecordArtwork(isPlaying: state.isPlaying)
                    }
                }
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                SpinningRecordArtwork(isPlaying: state.isPlaying)
            }
        }
    }

    private func mediaButton(icon: String, emphasized: Bool = false, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle((emphasized || isActive) ? .black : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill((emphasized || isActive) ? LinearGradient(colors: [JeffreyPalette.cyan, Color.white.opacity(0.88)], startPoint: .topLeading, endPoint: .bottomTrailing) : LinearGradient(colors: [JeffreyPalette.panel.opacity(0.92)], startPoint: .top, endPoint: .bottom))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke((emphasized || isActive) ? JeffreyPalette.cyan.opacity(0.82) : JeffreyPalette.strokeStrong, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(PressableScaleButtonStyle())
        .animation(interactionFadeAnimation, value: isActive)
    }

    private var levelsPanel: some View {
        VStack(spacing: 0) {
            sliderBlock(title: "Volume", icon: "speaker.wave.3.fill", value: $state.volume)
            Divider().background(JeffreyPalette.stroke).padding(.vertical, 4)
            sliderBlock(title: "Screen Brightness", icon: "sun.max.fill", value: $state.screenBrightness)
            Divider().background(JeffreyPalette.stroke).padding(.vertical, 4)
            sliderBlock(title: "Keyboard Brightness", icon: "keyboard.fill", value: $state.keyboardBrightness)
        }
        .padding(16)
        .background(sectionPanel)
    }

    private func sliderTint(for title: String) -> Color {
        switch title {
        case "Volume": return Color(red: 0.20, green: 0.86, blue: 0.54)
        case "Screen Brightness": return Color(red: 1.0, green: 0.76, blue: 0.26)
        default: return Color(red: 0.50, green: 0.52, blue: 1.0)
        }
    }

    private func sliderBlock(title: String, icon: String, value: Binding<Double>) -> some View {
        let tint = sliderTint(for: title)
        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(Int(value.wrappedValue * 100))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(tint.opacity(0.82))
                }
                InteractiveSlider(value: value, tint: tint, isEnabled: true) {
                    state.sliderValueChanged(title: title, value: value.wrappedValue)
                } onEditingEnded: {
                    state.sliderDidCommit(title: title, icon: icon, value: value.wrappedValue)
                }
            }
        }
        .padding(.vertical, 10)
    }

    private func timeLabel(for seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "--:--" }
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct VoiceTabView: View {
    @ObservedObject var state: JeffreyRemotePrototypeState

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                TopSectionHeader(
                    title: "Voice Relay",
                    subtitle: "Type a line and Jeffrey on the Mac will say it out loud almost immediately."
                )

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Jeffrey Voice")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer()
                        Picker("Language", selection: $state.speechLanguage) {
                            ForEach(JeffreyRemoteSpeechLanguage.allCases) { language in
                                Text(language.title).tag(language)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    TextEditor(text: $state.speechBroadcastDraft)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .scrollContentBackground(.hidden)
                        .padding(14)
                        .frame(minHeight: 220)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(JeffreyPalette.panelRaised.opacity(0.98))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .stroke(JeffreyPalette.strokeStrong, lineWidth: 1)
                                )
                        )
                        .onChange(of: state.speechBroadcastDraft) { _, _ in
                            state.scheduleSpeechBroadcast()
                        }

                    HStack(spacing: 10) {
                        Label(state.speechLanguage.title, systemImage: "waveform")
                        Spacer()
                        Button {
                            state.sendSpeechBroadcastNow()
                        } label: {
                            Text("Speak Again")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)
                                .background(
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [JeffreyPalette.cyan, Color(red: 0.43, green: 0.63, blue: 1.0)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                )
                        }
                        .buttonStyle(PressableScaleButtonStyle(scale: 0.97))
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(JeffreyPalette.textSecondary)

                    Text(state.speechBroadcastStatus)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(JeffreyPalette.cyanSoft)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(sectionPanel)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
    }
}

private struct AppsTabView: View {
    @ObservedObject var state: JeffreyRemotePrototypeState
    private let grid = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                TopSectionHeader(title: "Launch Board", subtitle: "Every favorite app tile is clickable and gives visual feedback immediately.")

                appSearchPanel

                if !state.filteredApps.isEmpty {
                    installedAppsPanel
                } else if state.appQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchHintPanel
                }

                LazyVGrid(columns: grid, spacing: 10) {
                    ForEach(JeffreyRemoteFixtures.appLaunchers) { app in
                        LauncherTile(app: app, isActive: state.isLit("app:\(app.command)")) {
                            state.triggerApp(app)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .task(id: state.appQuery) {
            await state.refreshAvailableApps()
        }
    }

    private var appSearchPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Any App on Your Mac")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "app.badge")
                        .foregroundStyle(JeffreyPalette.textSecondary)
                    TextField("Type Safari, or full command like open safari d3", text: $state.appQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .foregroundStyle(.white)
                        .onSubmit {
                            state.triggerCustomAppCommand()
                        }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(sectionPanel)

                Button(action: state.triggerCustomAppCommand) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 54, height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(LinearGradient(colors: [JeffreyPalette.cyan, Color(red: 0.43, green: 0.63, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                }
                .buttonStyle(PressableScaleButtonStyle())
            }
        }
    }

    private var searchHintPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Search only when you need it")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("I’m hiding the full installed-app list now. Type an app name or a full command like `open safari d3`, and I’ll surface only the matches you actually need.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(JeffreyPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(sectionPanel)
    }

    private var installedAppsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Installed Apps")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            LazyVGrid(columns: grid, spacing: 10) {
                ForEach(state.filteredApps, id: \.self) { appName in
                    Button {
                        state.triggerOpenInstalledApp(named: appName)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "app.fill")
                                .foregroundStyle(JeffreyPalette.cyan)
                            Text(appName)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.92))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .background(sectionPanel)
                    }
                    .buttonStyle(PressableScaleButtonStyle())
                }
            }
        }
    }
}

private struct SurfaceLineCluster: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<7, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(index == 0 ? JeffreyPalette.cyan.opacity(0.55) : Color.white.opacity(0.13))
                    .frame(width: CGFloat(46 + (index % 3) * 46), height: 4)
            }
        }
    }
}

private struct CursorIndicator: View {
    let cursor: CGPoint
    let frame: CGRect

    var body: some View {
        ZStack {
            Circle()
                .stroke(JeffreyPalette.cyan.opacity(0.34), lineWidth: 1.6)
                .frame(width: 16, height: 16)
            Circle()
                .fill(JeffreyPalette.cyan)
                .frame(width: 3.4, height: 3.4)
                .shadow(color: JeffreyPalette.cyan.opacity(0.95), radius: 7)
        }
        .position(
            x: frame.minX + (cursor.x * frame.width),
            y: frame.minY + (cursor.y * frame.height)
        )
    }
}

private struct RemoteControlButton: View {
    let title: String
    let icon: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(active ? LinearGradient(colors: activeColors, startPoint: .topLeading, endPoint: .bottomTrailing) : LinearGradient(colors: [JeffreyPalette.panel.opacity(0.92)], startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(active ? JeffreyPalette.cyan.opacity(0.78) : JeffreyPalette.strokeStrong, lineWidth: 1)
                    )
            )
            .foregroundStyle(active ? .black : .white.opacity(0.84))
        }
        .buttonStyle(PressableScaleButtonStyle())
        .animation(interactionFadeAnimation, value: active)
    }

    private var activeColors: [Color] {
        switch title {
        case "Cursor":
            return [JeffreyPalette.cyan, Color(red: 0.45, green: 0.78, blue: 1.0)]
        case "Click":
            return [Color(red: 0.54, green: 0.51, blue: 1.0), JeffreyPalette.cyan]
        case "Hold":
            return [Color(red: 1.0, green: 0.63, blue: 0.44), Color(red: 1.0, green: 0.86, blue: 0.46)]
        case "Double":
            return [Color(red: 1.0, green: 0.58, blue: 0.73), Color(red: 0.73, green: 0.41, blue: 1.0)]
        case "Right":
            return [Color(red: 0.40, green: 0.62, blue: 1.0), Color(red: 0.20, green: 0.90, blue: 0.94)]
        case "Scroll":
            return [Color(red: 0.49, green: 0.95, blue: 0.74), Color(red: 0.16, green: 0.78, blue: 0.62)]
        default:
            return [JeffreyPalette.cyan, .white]
        }
    }
}

private struct RemoteMomentaryControlButton: View {
    let title: String
    let icon: String
    let active: Bool
    let onPressBegan: () -> Void
    let onPressEnded: () -> Void

    @State private var isPressing = false

    var body: some View {
        remoteButtonBody
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressing else { return }
                        isPressing = true
                        onPressBegan()
                    }
                    .onEnded { _ in
                        if isPressing {
                            isPressing = false
                            onPressEnded()
                        }
                    }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0)
                    .onEnded { _ in }
            )
            .animation(interactionFadeAnimation, value: active)
    }

    private var remoteButtonBody: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(active ? LinearGradient(colors: activeColors, startPoint: .topLeading, endPoint: .bottomTrailing) : LinearGradient(colors: [JeffreyPalette.panel.opacity(0.92)], startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(active ? JeffreyPalette.cyan.opacity(0.78) : JeffreyPalette.strokeStrong, lineWidth: 1)
                )
        )
        .foregroundStyle(active ? .black : .white.opacity(0.84))
        .scaleEffect(isPressing ? 0.97 : 1)
    }

    private var activeColors: [Color] {
        switch title {
        case "Hold":
            return [Color(red: 1.0, green: 0.63, blue: 0.44), Color(red: 1.0, green: 0.86, blue: 0.46)]
        case "Scroll":
            return [Color(red: 0.49, green: 0.95, blue: 0.74), Color(red: 0.16, green: 0.78, blue: 0.62)]
        default:
            return [JeffreyPalette.cyan, .white]
        }
    }
}

private struct TopSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image("JeffreyMark")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(JeffreyPalette.textSecondary)
                }
                Spacer()
            }
        }
    }
}

private struct CommandDeckSection<Content: View>: View {
    let title: String
    let caption: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(caption)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(JeffreyPalette.textSecondary)
            }
            content
        }
    }
}

private struct TacticalCommandCard: View {
    let command: QuickCommand
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(isActive ? Color.black.opacity(0.14) : command.tint.opacity(0.16))
                        .frame(width: 46, height: 46)
                    Image(systemName: command.icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(isActive ? .black : command.tint)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(command.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(isActive ? .black : .white)
                    Text(command.subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(isActive ? Color.black.opacity(0.62) : JeffreyPalette.textSecondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isActive ? Color.black.opacity(0.38) : JeffreyPalette.textMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isActive ? LinearGradient(colors: [command.tint, command.tintSecondary], startPoint: .leading, endPoint: .trailing) : LinearGradient(colors: [JeffreyPalette.panel.opacity(0.93)], startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isActive ? command.tint.opacity(0.72) : command.tint.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
            )
        }
        .buttonStyle(PressableScaleButtonStyle())
        .animation(interactionFadeAnimation, value: isActive)
    }
}

private struct LauncherTile: View {
    let app: QuickCommand
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(app.tint.opacity(0.14))
                        .frame(width: 48, height: 48)
                    Image(systemName: app.icon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(isActive ? .black : .white)
                }

                Text(app.title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(isActive ? .black : .white)
                Text(app.subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(isActive ? Color.black.opacity(0.72) : JeffreyPalette.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isActive ? LinearGradient(colors: [app.tint, app.tintSecondary], startPoint: .topLeading, endPoint: .bottomTrailing) : LinearGradient(colors: [JeffreyPalette.panel.opacity(0.92)], startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(isActive ? app.tint.opacity(0.8) : JeffreyPalette.stroke, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
            )
            .foregroundStyle(isActive ? .black : .white)
        }
        .buttonStyle(PressableScaleButtonStyle())
        .animation(interactionFadeAnimation, value: isActive)
    }
}

private struct InteractiveSlider: View {
    @Binding var value: Double
    let tint: Color
    let isEnabled: Bool
    let onValueChanged: () -> Void
    let onEditingEnded: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 10)

                Capsule()
                    .fill(isEnabled ? tint : Color.white.opacity(0.18))
                    .frame(width: max(12, width * value), height: 10)

                Circle()
                    .fill(isEnabled ? .white : Color.white.opacity(0.52))
                    .frame(width: 22, height: 22)
                    .shadow(color: tint.opacity(isEnabled ? 0.45 : 0.15), radius: 10)
                    .overlay(Circle().stroke((isEnabled ? tint : Color.white.opacity(0.26)).opacity(0.75), lineWidth: 4))
                    .offset(x: max(0, width * value - 11))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard isEnabled else { return }
                        let ratio = min(max(gesture.location.x / width, 0), 1)
                        value = ratio
                        onValueChanged()
                    }
                    .onEnded { _ in
                        guard isEnabled else { return }
                        onEditingEnded()
                    }
            )
        }
        .frame(height: 28)
    }
}

private struct SpinningRecordArtwork: View {
    let isPlaying: Bool
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.28, green: 0.30, blue: 0.42), Color(red: 0.07, green: 0.08, blue: 0.12)],
                        center: .center,
                        startRadius: 2,
                        endRadius: 58
                    )
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

            ForEach(0..<4, id: \.self) { ring in
                Circle()
                    .stroke(Color.white.opacity(0.06 + Double(ring) * 0.02), lineWidth: 1.2)
                    .padding(CGFloat(10 + ring * 12))
            }

            Rectangle()
                .fill(JeffreyPalette.cyan.opacity(0.78))
                .frame(width: 6, height: 34)
                .blur(radius: 0.2)
                .offset(y: -14)
                .blendMode(.screen)

            Circle()
                .fill(Color.white.opacity(0.96))
                .frame(width: 18, height: 18)
            Circle()
                .fill(Color.black.opacity(0.68))
                .frame(width: 6, height: 6)
        }
        .frame(width: 96, height: 96)
        .rotationEffect(.degrees(rotation))
        .onAppear {
            if isPlaying {
                withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
        }
        .onChange(of: isPlaying) { _, playing in
            if playing {
                rotation = 0
                withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            } else {
                withAnimation(.easeOut(duration: 0.35)) {
                    rotation = rotation.truncatingRemainder(dividingBy: 360)
                }
            }
        }
    }
}

private struct WelcomeOverlay: View {
    let isAnimating: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.88)
                .ignoresSafeArea()

            RadialGradient(
                colors: [Color(red: 0.12, green: 0.72, blue: 0.95).opacity(0.22), Color.clear],
                center: .center,
                startRadius: 80,
                endRadius: 340
            )
            .ignoresSafeArea()
            .blur(radius: 18)

            VStack(spacing: 36) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.16, green: 0.88, blue: 1.0).opacity(0.11))
                        .frame(width: isAnimating ? 180 : 148, height: isAnimating ? 180 : 148)
                        .blur(radius: 18)
                    Circle()
                        .fill(Color(red: 0.55, green: 0.36, blue: 1.0).opacity(0.09))
                        .frame(width: isAnimating ? 138 : 114, height: isAnimating ? 138 : 114)
                        .blur(radius: 10)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.09, green: 0.10, blue: 0.18), Color(red: 0.05, green: 0.06, blue: 0.13)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 88, height: 88)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [Color(red: 0.21, green: 0.91, blue: 1.0).opacity(0.60), Color(red: 0.62, green: 0.43, blue: 1.0).opacity(0.38)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(color: Color(red: 0.18, green: 0.89, blue: 1.0).opacity(0.32), radius: 24)

                    Text("J")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 0.21, green: 0.91, blue: 1.0), Color(red: 0.62, green: 0.43, blue: 1.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .scaleEffect(isAnimating ? 1.0 : 0.90)
                }
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isAnimating)

                VStack(spacing: 10) {
                    Text("JEFFREY REMOTE")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(3.0)
                        .foregroundStyle(JeffreyPalette.cyan.opacity(0.68))
                    Text("Welcome, Mr. Bosch.")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

private struct CaptureViewer: View {
    @ObservedObject var state: JeffreyRemotePrototypeState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()

                if let image = state.latestCaptureImage {
                    let frame = rotatedCaptureDisplayFrame(for: image.size, in: size)

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: frame.height, height: frame.width)
                        .rotationEffect(.degrees(90))
                        .position(x: frame.midX, y: frame.midY)

                    RotatedCursorIndicator(cursor: state.cursor, frame: frame)
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(JeffreyPalette.cyan)
                        Text("Fetching a real screenshot from your Mac…")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.84))
                    }
                }

                Button {
                    state.showingCaptureViewer = false
                    dismiss()
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 48, height: 48)
                        .background(
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [JeffreyPalette.cyan, Color(red: 0.64, green: 0.38, blue: 1.0)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .shadow(color: JeffreyPalette.cyan.opacity(0.42), radius: 16)
                }
                .padding(18)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        state.moveCursorFromRotatedCaptureViewer(location: value.location, size: size)
                    }
            )
            .onAppear {
                if state.latestCaptureImage == nil {
                    state.triggerCapture()
                }
            }
        }
        .statusBar(hidden: true)
    }
}

private struct RotatedCursorIndicator: View {
    let cursor: CGPoint
    let frame: CGRect

    var body: some View {
        let displayedX = frame.minX + frame.width * (1 - cursor.y)
        let displayedY = frame.minY + frame.height * cursor.x

        ZStack {
            Circle()
                .fill(JeffreyPalette.cyan.opacity(0.18))
                .frame(width: 22, height: 22)
                .blur(radius: 8)
            Circle()
                .fill(.white)
                .frame(width: 7, height: 7)
                .overlay(
                    Circle()
                        .stroke(JeffreyPalette.cyan, lineWidth: 2.8)
                )
                .shadow(color: JeffreyPalette.cyan.opacity(0.5), radius: 9)
        }
        .position(x: displayedX, y: displayedY)
        .allowsHitTesting(false)
    }
}

private func rotatedCaptureDisplayFrame(for imageSize: CGSize, in containerSize: CGSize) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
        return CGRect(origin: .zero, size: containerSize)
    }

    let scale = min(containerSize.width / imageSize.height, containerSize.height / imageSize.width) * 0.985
    let width = imageSize.height * scale
    let height = imageSize.width * scale

    return CGRect(
        x: (containerSize.width - width) / 2.0,
        y: (containerSize.height - height) / 2.0,
        width: width,
        height: height
    )
}

private struct KeepAwakeSheet: View {
    @ObservedObject var state: JeffreyRemotePrototypeState
    @Environment(\.dismiss) private var dismiss

    private let hourRange = Array(0...8)
    private let minuteRange = stride(from: 0, through: 55, by: 5).map { $0 }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text("Keep Awake")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Choose how long Jeffrey should keep the Mac awake before you head out.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(JeffreyPalette.textSecondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 0) {
                Picker("Hours", selection: $state.keepAwakeHours) {
                    ForEach(hourRange, id: \.self) { hour in
                        Text("\(hour) h").tag(hour)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)

                Picker("Minutes", selection: $state.keepAwakeMinutes) {
                    ForEach(minuteRange, id: \.self) { minute in
                        Text("\(minute) min").tag(minute)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
            }
            .frame(height: 150)
            .clipped()

            HStack(spacing: 10) {
                Button {
                    state.showingKeepAwakeSheet = false
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(JeffreyPalette.panelRaised.opacity(0.92))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(JeffreyPalette.strokeStrong, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(PressableScaleButtonStyle(scale: 0.98))

                Button {
                    state.confirmKeepAwakeSelection()
                    dismiss()
                } label: {
                    Text("Extend")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.99, green: 0.76, blue: 0.28), Color(red: 0.55, green: 0.38, blue: 1.0)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                }
                .buttonStyle(PressableScaleButtonStyle(scale: 0.98))
                .disabled(state.keepAwakeHours == 0 && state.keepAwakeMinutes == 0)
                .opacity(state.keepAwakeHours == 0 && state.keepAwakeMinutes == 0 ? 0.55 : 1)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [JeffreyPalette.backgroundTop, JeffreyPalette.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

private struct BottomTabBar: View {
    @Binding var selectedTab: JeffreyRemoteTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(JeffreyRemoteTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 17, weight: selectedTab == tab ? .semibold : .regular))
                        Text(tab.title)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                        Circle()
                            .fill(selectedTab == tab ? JeffreyPalette.cyan : Color.clear)
                            .frame(width: 4, height: 4)
                    }
                    .foregroundStyle(selectedTab == tab ? JeffreyPalette.cyan : JeffreyPalette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(JeffreyPalette.panel.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(JeffreyPalette.stroke, lineWidth: 1)
                )
        )
    }
}

private struct ConnectionSheet: View {
    @ObservedObject var state: JeffreyRemotePrototypeState
    @Environment(\.dismiss) private var dismiss
    @State private var draftHost = ""

    private var nearbyTitle: String {
        switch state.connectionMode {
        case .wifi: return "NEARBY WI-FI MACS"
        case .hotspot: return "HOTSPOT MACS"
        case .tailscale: return "TAILSCALE MAC"
        }
    }

    private var modeDescription: String {
        switch state.connectionMode {
        case .wifi:
            return "Use Bonjour on the same Wi-Fi network. Best when your iPhone and Mac share the same local network."
        case .hotspot:
            return "Use Bonjour while the Mac is joined to your iPhone Personal Hotspot. Great when you are away from Wi-Fi."
        case .tailscale:
            return "Use your Mac's Tailscale IP or MagicDNS name. This is the preferred always-on path for Jeffrey Remote."
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connect Jeffrey Remote")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Choose exactly how Jeffrey Remote should reach your Mac. Tailscale is the most reliable option if you want the laptop to stay reachable at all times.")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(JeffreyPalette.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("CONNECTION MODE")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .tracking(1.6)
                            .foregroundStyle(JeffreyPalette.textSecondary)

                        HStack(spacing: 10) {
                            ForEach(JeffreyRemoteConnectionMode.allCases) { mode in
                                Button {
                                    state.setConnectionMode(mode)
                                    if mode == .tailscale {
                                        draftHost = state.connectionHost.isEmpty ? JeffreyRemotePrototypeState.defaultTailscaleHost : state.connectionHost
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Image(systemName: mode.icon)
                                                .font(.system(size: 18, weight: .bold))
                                            Spacer()
                                            if mode == .tailscale {
                                                bestBadge(selected: state.connectionMode == mode)
                                            }
                                        }
                                        Text(mode.title)
                                            .font(.system(size: 15, weight: .bold, design: .rounded))
                                        Text(mode.subtitle)
                                            .font(.system(size: 11, weight: .medium, design: .rounded))
                                            .foregroundStyle(state.connectionMode == mode ? Color.black.opacity(0.72) : JeffreyPalette.textSecondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(
                                                state.connectionMode == mode
                                                ? LinearGradient(colors: [JeffreyPalette.cyan, Color(red: 0.43, green: 0.63, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                                : LinearGradient(colors: [JeffreyPalette.panelRaised.opacity(0.96), JeffreyPalette.panel.opacity(0.94)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                    .stroke(state.connectionMode == mode ? Color.white.opacity(0.18) : JeffreyPalette.strokeStrong, lineWidth: 1)
                                            )
                                    )
                                    .foregroundStyle(state.connectionMode == mode ? .black : .white)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Text(modeDescription)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(JeffreyPalette.textSecondary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(JeffreyPalette.panelRaised.opacity(0.92))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(JeffreyPalette.stroke, lineWidth: 1)
                                )
                        )

                    if state.connectionMode == .tailscale {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(nearbyTitle)
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .tracking(1.6)
                                .foregroundStyle(JeffreyPalette.textSecondary)

                            TextField("e.g. 100.x.y.z or your-mac.tailnet.ts.net", text: $draftHost)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(JeffreyPalette.panelRaised.opacity(0.96))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .stroke(JeffreyPalette.strokeStrong, lineWidth: 1)
                                        )
                                )

                            Button {
                                state.setConnectionMode(.tailscale)
                                draftHost = JeffreyRemotePrototypeState.defaultTailscaleHost
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "network.badge.shield.half.filled")
                                        .font(.system(size: 15, weight: .bold))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Use My Tailscale Mac")
                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                        Text(JeffreyRemotePrototypeState.defaultTailscaleHost)
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(JeffreyPalette.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.system(size: 18, weight: .bold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(LinearGradient(colors: [JeffreyPalette.panelRaised.opacity(0.96), JeffreyPalette.panel.opacity(0.94)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .stroke(JeffreyPalette.cyan.opacity(0.45), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(nearbyTitle)
                                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                                    .tracking(1.6)
                                    .foregroundStyle(JeffreyPalette.textSecondary)
                                Spacer()
                                if state.discoveredMacs.isEmpty {
                                    Text("Scanning…")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(JeffreyPalette.cyan)
                                }
                            }

                            if state.discoveredMacs.isEmpty {
                                Text(state.connectionMode == .wifi
                                     ? "No nearby Mac yet. Make sure JeffreyHotkey is running and both devices are on the same Wi-Fi."
                                     : "No nearby Mac yet. Make sure the Mac is connected to your iPhone Personal Hotspot and JeffreyHotkey is running.")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(JeffreyPalette.textSecondary)
                                    .padding(16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(JeffreyPalette.panelRaised.opacity(0.92))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                    .stroke(JeffreyPalette.stroke, lineWidth: 1)
                                            )
                                    )
                            } else {
                                VStack(spacing: 10) {
                                    ForEach(state.discoveredMacs) { mac in
                                        Button {
                                            Task {
                                                await state.connect(to: mac, mode: state.connectionMode)
                                                if state.isConnected {
                                                    dismiss()
                                                }
                                            }
                                        } label: {
                                            HStack(spacing: 12) {
                                                Image(systemName: state.connectionMode == .hotspot ? "iphone.radiowaves.left.and.right" : "desktopcomputer")
                                                    .font(.system(size: 16, weight: .bold))
                                                    .foregroundStyle(.black)
                                                    .frame(width: 34, height: 34)
                                                    .background(
                                                        Circle()
                                                            .fill(
                                                                LinearGradient(
                                                                    colors: [JeffreyPalette.cyan, Color(red: 0.48, green: 0.68, blue: 1.0)],
                                                                    startPoint: .topLeading,
                                                                    endPoint: .bottomTrailing
                                                                )
                                                            )
                                                    )
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(mac.name)
                                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                                        .foregroundStyle(.white)
                                                    Text(mac.detail)
                                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                                        .foregroundStyle(JeffreyPalette.textSecondary)
                                                }
                                                Spacer()
                                                Image(systemName: "arrow.up.right.circle.fill")
                                                    .font(.system(size: 18, weight: .bold))
                                                    .foregroundStyle(JeffreyPalette.cyan)
                                            }
                                            .padding(16)
                                            .background(
                                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                    .fill(JeffreyPalette.panelRaised.opacity(0.96))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                            .stroke(JeffreyPalette.strokeStrong, lineWidth: 1)
                                                    )
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Wi-Fi mode uses nearby Bonjour discovery.", systemImage: "wifi")
                        Label("Hotspot mode also uses nearby Bonjour, but with the Mac joined to your iPhone hotspot.", systemImage: "iphone.radiowaves.left.and.right")
                        Label("Tailscale mode keeps Jeffrey Remote pointed at your Mac's direct Tailscale host.", systemImage: "network.badge.shield.half.filled")
                        Label("If macOS asks, allow incoming connections for JeffreyHotkey.", systemImage: "lock.shield")
                    }
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(JeffreyPalette.textSecondary)

                    HStack(spacing: 10) {
                        Button {
                            state.disconnect()
                            dismiss()
                        } label: {
                            Text("Disconnect")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ConnectionActionStyle(fill: [Color.white.opacity(0.08), Color.white.opacity(0.06)], foreground: .white))

                        Button {
                            Task {
                                if state.connectionMode == .tailscale {
                                    await state.connectToTailscale(host: draftHost)
                                    if state.isConnected {
                                        dismiss()
                                    }
                                } else {
                                    state.openConnectionSettings()
                                }
                            }
                        } label: {
                            Text(state.connectionMode == .tailscale ? "Connect Tailscale" : "Refresh Nearby")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ConnectionActionStyle(fill: [JeffreyPalette.cyan, Color(red: 0.43, green: 0.63, blue: 1.0)], foreground: .black))
                    }
                }
                .padding(22)
            }
            .background(
                LinearGradient(
                    colors: [JeffreyPalette.backgroundTop, JeffreyPalette.backgroundBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(JeffreyPalette.cyan)
                }
            }
        }
        .onAppear {
            draftHost = state.connectionHost.isEmpty ? JeffreyRemotePrototypeState.defaultTailscaleHost : state.connectionHost
        }
        .onChange(of: state.connectionMode) { _, newMode in
            if newMode == .tailscale, draftHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draftHost = state.connectionHost.isEmpty ? JeffreyRemotePrototypeState.defaultTailscaleHost : state.connectionHost
            }
        }
    }

    private func bestBadge(selected: Bool) -> some View {
        let fg: Color = selected ? Color.black.opacity(0.68) : JeffreyPalette.cyan.opacity(0.88)
        let bg: Color = selected ? Color.black.opacity(0.18) : JeffreyPalette.cyan.opacity(0.18)
        return Text("BEST")
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(fg)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(bg))
    }
}

private struct ConnectionActionStyle: ButtonStyle {
    let fill: [Color]
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(foreground)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: fill, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct RemoteKeyboardSheet: View {
    @ObservedObject var state: JeffreyRemotePrototypeState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Remote Keyboard")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Type here and Jeffrey will send it straight to your Mac. Quick keys underneath handle enter, tab and escape.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(JeffreyPalette.textSecondary)
                }

                TextEditor(text: $state.keyboardDraft)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(14)
                    .frame(minHeight: 180)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(JeffreyPalette.panelRaised.opacity(0.96))
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(JeffreyPalette.strokeStrong, lineWidth: 1)
                            )
                    )

                HStack(spacing: 10) {
                    keyboardKey("Enter", key: "enter")
                    keyboardKey("Tab", key: "tab")
                    keyboardKey("Esc", key: "escape")
                }

                HStack(spacing: 10) {
                    Button {
                        state.keyboardDraft = ""
                    } label: {
                        Text("Clear")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ConnectionActionStyle(fill: [Color.white.opacity(0.08), Color.white.opacity(0.06)], foreground: .white))

                    Button {
                        state.sendTypedText()
                    } label: {
                        Text("Send to Mac")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ConnectionActionStyle(fill: [JeffreyPalette.cyan, Color(red: 0.43, green: 0.63, blue: 1.0)], foreground: .black))
                }

                }
                .padding(22)
            }
            .background(
                LinearGradient(
                    colors: [JeffreyPalette.backgroundTop, JeffreyPalette.backgroundBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(JeffreyPalette.cyan)
                }
            }
        }
    }

    private func keyboardKey(_ label: String, key: String) -> some View {
        Button {
            state.sendSpecialKey(key)
        } label: {
            Text(label)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ConnectionActionStyle(fill: [JeffreyPalette.panelRaised, JeffreyPalette.panel], foreground: .white))
    }
}

private struct ToastBanner: View {
    let toast: ToastBannerState

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(JeffreyPalette.cyan.opacity(0.16))
                    .frame(width: 34, height: 34)
                Image(systemName: toast.icon)
                    .foregroundStyle(JeffreyPalette.cyan)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(toast.subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(JeffreyPalette.textSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(JeffreyPalette.strokeStrong, lineWidth: 1)
                )
        )
    }
}

private struct PressableScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private var sectionPanel: some View {
    RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill(JeffreyPalette.panel.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(JeffreyPalette.stroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
}

#Preview("Jeffrey Remote · Interactive") {
    ContentView()
}
