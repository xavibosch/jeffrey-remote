@preconcurrency import Foundation
import Network
import SwiftUI

struct JeffreyRemoteDiscoveredMac: Identifiable {
    let id: String
    let name: String
    let detail: String
    let endpoint: NWEndpoint
}

struct QuickCommand: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let tintSecondary: Color
    let command: String
}

struct MediaState {
    let source: String
    let title: String
    let subtitle: String
    let progress: Double
}

enum JeffreyRemoteFixtures {
    static let workspaceDeck: [QuickCommand] = [
        .init(title: "good morning", subtitle: "Wake with voice", icon: "waveform.and.mic", tint: .cyan, tintSecondary: .blue, command: "good morning"),
        .init(title: "good morning sh", subtitle: "Wake silently", icon: "moon.stars.fill", tint: .indigo, tintSecondary: .purple, command: "gm sh"),
        .init(title: "open safari d2", subtitle: "Web workspace", icon: "safari.fill", tint: .blue, tintSecondary: .cyan, command: "open safari d2"),
        .init(title: "open spotify d3", subtitle: "Music deck", icon: "music.note", tint: .green, tintSecondary: .mint, command: "open spotify d3")
    ]

    static let desktopDeck: [QuickCommand] = [
        .init(title: "go to d1", subtitle: "Jeffrey desk", icon: "1.square.fill", tint: .teal, tintSecondary: .cyan, command: "go to d1"),
        .init(title: "go to d2", subtitle: "Browser desk", icon: "2.square.fill", tint: .cyan, tintSecondary: .blue, command: "go to d2"),
        .init(title: "go to d3", subtitle: "Media desk", icon: "3.square.fill", tint: .indigo, tintSecondary: .purple, command: "go to d3"),
        .init(title: "go to d4", subtitle: "Extra desk", icon: "4.square.fill", tint: .purple, tintSecondary: .pink, command: "go to d4")
    ]

    static let powerDeck: [QuickCommand] = [
        .init(title: "sleep", subtitle: "Sleep Jeffrey only", icon: "power.circle.fill", tint: .orange, tintSecondary: .yellow, command: "sleep"),
        .init(title: "sleep all", subtitle: "Close workspace", icon: "bolt.slash.circle.fill", tint: .red, tintSecondary: .orange, command: "sleep all"),
        .init(title: "lock mac", subtitle: "Lock instantly", icon: "lock.fill", tint: .mint, tintSecondary: .teal, command: "lock mac"),
        .init(title: "sleep mac", subtitle: "Sleep the Mac", icon: "bed.double.fill", tint: .pink, tintSecondary: .purple, command: "sleep mac")
    ]

    static let appLaunchers: [QuickCommand] = [
        .init(title: "Safari", subtitle: "Research and login flows", icon: "safari.fill", tint: .blue, tintSecondary: .cyan, command: "open safari"),
        .init(title: "Codex", subtitle: "Coding workspace", icon: "chevron.left.forwardslash.chevron.right", tint: .purple, tintSecondary: .indigo, command: "open codex"),
        .init(title: "Spotify", subtitle: "Music and audio", icon: "music.note", tint: .green, tintSecondary: .mint, command: "open spotify"),
        .init(title: "WhatsApp", subtitle: "Messaging", icon: "message.fill", tint: .mint, tintSecondary: .green, command: "open whatsapp"),
        .init(title: "Notes", subtitle: "Capture ideas", icon: "note.text", tint: .yellow, tintSecondary: .orange, command: "open notes"),
        .init(title: "ChatGPT", subtitle: "Assistant", icon: "bubble.left.and.bubble.right.fill", tint: .cyan, tintSecondary: .teal, command: "open chatgpt")
    ]

    static let mediaSources: [String] = ["Spotify", "Safari", "Netflix", "YouTube"]

    static let media = MediaState(
        source: "Spotify on Desktop 3",
        title: "Jeffrey Control Theme",
        subtitle: "Now playing across your Mac workspace",
        progress: 0.37
    )
}

struct JeffreyRemoteBridgeRequest: Codable {
    let id: String
    let action: String
    let command: String?
    let x: Double?
    let y: Double?
    let deltaX: Double?
    let deltaY: Double?
    let mouseAction: String?
    let value: Double?
    let source: String?

    init(
        id: String = UUID().uuidString,
        action: String,
        command: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        deltaX: Double? = nil,
        deltaY: Double? = nil,
        mouseAction: String? = nil,
        value: Double? = nil,
        source: String? = nil
    ) {
        self.id = id
        self.action = action
        self.command = command
        self.x = x
        self.y = y
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.mouseAction = mouseAction
        self.value = value
        self.source = source
    }
}

struct JeffreyRemoteBridgeMediaSnapshot: Codable {
    let source: String
    let title: String
    let subtitle: String
    let isPlaying: Bool
    let volume: Double
    let artworkURL: String?
    let duration: Double?
    let currentTime: Double?
}

struct JeffreyRemoteBridgeResponse: Codable {
    let id: String
    let ok: Bool
    let message: String
    let hostName: String?
    let workspaceActive: Bool
    let cursorX: Double?
    let cursorY: Double?
    let screenshotBase64: String?
    let media: JeffreyRemoteBridgeMediaSnapshot?
    let appNames: [String]?
    let batteryLevel: Int?
    let screenBrightness: Double?
    let keyboardBrightness: Double?
    let keepAwakeUntil: Double?
}

enum JeffreyRemoteBridgeError: LocalizedError {
    case invalidHost
    case timeout
    case disconnected
    case invalidResponse
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidHost:
            return "Enter a valid Mac host or IP address first."
        case .timeout:
            return "The Mac did not answer in time."
        case .disconnected:
            return "The connection to Jeffrey on the Mac closed unexpectedly."
        case .invalidResponse:
            return "Jeffrey returned a response I could not decode."
        case .transport(let message):
            return message
        }
    }
}

final class JeffreyRemoteBridgeClient {
    private let port: UInt16

    init(port: UInt16 = 45871) {
        self.port = port
    }

    func send(_ request: JeffreyRemoteBridgeRequest, host: String) async throws -> JeffreyRemoteBridgeResponse {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            throw JeffreyRemoteBridgeError.invalidHost
        }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw JeffreyRemoteBridgeError.transport("Invalid Jeffrey bridge port.")
        }
        return try await send(request, endpoint: .hostPort(host: NWEndpoint.Host(trimmedHost), port: nwPort))
    }

    func send(_ request: JeffreyRemoteBridgeRequest, endpoint: NWEndpoint) async throws -> JeffreyRemoteBridgeResponse {
        let payload = try JSONEncoder().encode(request) + Data([0x0A])
        let packet = try await sendPayload(
            payload,
            requestID: request.id,
            endpoint: endpoint,
            timeout: timeout(for: request)
        )
        do {
            return try JSONDecoder().decode(JeffreyRemoteBridgeResponse.self, from: packet)
        } catch {
            throw JeffreyRemoteBridgeError.invalidResponse
        }
    }

    private func timeout(for request: JeffreyRemoteBridgeRequest) -> TimeInterval {
        switch request.action {
        case "screenshot":
            return 16
        case "list_apps":
            return 10
        default:
            return 6
        }
    }

    private func sendPayload(_ payload: Data, requestID: String, endpoint: NWEndpoint, timeout: TimeInterval) async throws -> Data {
        let packet: Data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let connection = NWConnection(to: endpoint, using: .tcp)
            let queue = DispatchQueue(label: "com.servicebosch.jeffreyremote.client.\(requestID)")
            var didResume = false

            func finish(_ result: Result<Data, Error>) {
                guard !didResume else { return }
                didResume = true
                connection.cancel()
                continuation.resume(with: result)
            }

            func receive(buffer: Data = Data()) {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                    if let error {
                        finish(.failure(JeffreyRemoteBridgeError.transport(error.localizedDescription)))
                        return
                    }

                    var combined = buffer
                    if let data, !data.isEmpty {
                        combined.append(data)
                    }

                    if let newlineIndex = combined.firstIndex(of: 0x0A) {
                        finish(.success(Data(combined.prefix(upTo: newlineIndex))))
                        return
                    }

                    if isComplete {
                        finish(.failure(JeffreyRemoteBridgeError.disconnected))
                        return
                    }

                    receive(buffer: combined)
                }
            }

            let timeoutWorkItem = DispatchWorkItem {
                finish(.failure(JeffreyRemoteBridgeError.timeout))
            }
            queue.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: payload, completion: .contentProcessed { error in
                        if let error {
                            timeoutWorkItem.cancel()
                            finish(.failure(JeffreyRemoteBridgeError.transport(error.localizedDescription)))
                            return
                        }
                        receive()
                    })
                case .failed(let error):
                    timeoutWorkItem.cancel()
                    finish(.failure(JeffreyRemoteBridgeError.transport(error.localizedDescription)))
                case .cancelled:
                    timeoutWorkItem.cancel()
                default:
                    break
                }
            }

            connection.start(queue: queue)
        }
        return packet
    }
}

final class JeffreyRemoteDiscoveryService {
    private let queue = DispatchQueue(label: "com.servicebosch.jeffreyremote.discovery", qos: .userInitiated)
    private var browser: NWBrowser?
    var onResultsChanged: (([JeffreyRemoteDiscoveredMac]) -> Void)?

    func start(forceRestart: Bool = false) {
        if forceRestart {
            stop()
        }
        guard browser == nil else { return }
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_jeffreyremote._tcp", domain: nil), using: parameters)
        browser.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed, .cancelled:
                browser.cancel()
                self.browser = nil
                Task { @MainActor in
                    self.onResultsChanged?([])
                }
            default:
                break
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            let mapped = results.compactMap(Self.mapResult)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            Task { @MainActor in
                self.onResultsChanged?(mapped)
            }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        Task { @MainActor in
            self.onResultsChanged?([])
        }
    }

    nonisolated private static func mapResult(_ result: NWBrowser.Result) -> JeffreyRemoteDiscoveredMac? {
        let endpoint = result.endpoint
        switch endpoint {
        case .service(let name, let type, let domain, _):
            let detail = [type, domain].filter { !$0.isEmpty }.joined(separator: " • ")
            return JeffreyRemoteDiscoveredMac(
                id: "service:\(name):\(type):\(domain)",
                name: name,
                detail: detail.isEmpty ? "Nearby Jeffrey bridge" : detail,
                endpoint: endpoint
            )
        case .hostPort(let host, let port):
            let hostLabel = host.debugDescription.replacingOccurrences(of: "\"", with: "")
            return JeffreyRemoteDiscoveredMac(
                id: "host:\(hostLabel):\(port.rawValue)",
                name: hostLabel,
                detail: "Direct host • \(port.rawValue)",
                endpoint: endpoint
            )
        default:
            return nil
        }
    }
}
