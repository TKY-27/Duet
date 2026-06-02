import Foundation

@MainActor
final class HubClient {
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var currentRequest: URLRequest?
    private var shouldReconnect = false
    private var reconnectAttempt = 0
    private var isOpen = false
    private let decoder: JSONDecoder
    private let encoder = JSONEncoder()
    private let onEvent: (ControlEvent) -> Void
    private let onStateChange: (ConnectionState) -> Void

    init(
        onEvent: @escaping (ControlEvent) -> Void,
        onStateChange: @escaping (ConnectionState) -> Void
    ) {
        self.onEvent = onEvent
        self.onStateChange = onStateChange
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    func connect(url: URL, controlToken: String? = nil) {
        var request = URLRequest(url: url)
        if let controlToken {
            request.setValue(controlToken, forHTTPHeaderField: "X-Duet-Control-Token")
        }
        shouldReconnect = true
        reconnectAttempt = 0
        currentRequest = request
        openSocket(with: request, state: .connecting)
    }

    func disconnect() {
        shouldReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        currentRequest = nil
        closeCurrentTask()
        onStateChange(.disconnected)
    }

    func send<T: Encodable>(_ command: T) async throws {
        guard let task, isOpen else { throw HubClientError.notConnected }
        let data = try encoder.encode(command)
        guard let text = String(data: data, encoding: .utf8) else {
            throw HubClientError.encodingFailed
        }
        try await task.send(.string(text))
    }

    private func openSocket(with request: URLRequest, state: ConnectionState) {
        reconnectTask?.cancel()
        reconnectTask = nil
        closeCurrentTask()
        isOpen = false
        onStateChange(state)
        let nextTask = URLSession.shared.webSocketTask(with: request)
        task = nextTask
        nextTask.resume()
        receiveTask = Task { [weak self, nextTask] in
            await self?.receiveLoop(task: nextTask)
        }
    }

    private func closeCurrentTask() {
        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isOpen = false
    }

    private func receiveLoop(task: URLSessionWebSocketTask) async {
        while !Task.isCancelled && task === self.task {
            do {
                let message = try await task.receive()
                if !isOpen {
                    isOpen = true
                    reconnectAttempt = 0
                    onStateChange(.connected)
                }
                handle(message)
            } catch {
                if !Task.isCancelled {
                    isOpen = false
                    let message = DuetErrorRedactor.redact(error.localizedDescription)
                    onStateChange(.failed(message))
                    scheduleReconnect()
                }
                return
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        do {
            let data: Data
            switch message {
            case .data(let payload):
                data = payload
            case .string(let text):
                data = Data(text.utf8)
            @unknown default:
                return
            }
            let envelope = try decoder.decode(ControlEventEnvelope.self, from: data)
            let event = try envelope.event()
            onEvent(event)
        } catch {
            onEvent(.error(error.localizedDescription))
        }
    }

    private func scheduleReconnect() {
        guard shouldReconnect, currentRequest != nil else { return }
        reconnectAttempt += 1
        let attempt = reconnectAttempt
        let delayMilliseconds = reconnectDelayMilliseconds(for: attempt)
        onStateChange(.reconnecting(attempt: attempt))
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(delayMilliseconds))
            } catch {
                return
            }
            self?.reconnectIfNeeded()
        }
    }

    private func reconnectIfNeeded() {
        guard shouldReconnect, let request = currentRequest else { return }
        openSocket(with: request, state: .reconnecting(attempt: reconnectAttempt))
    }

    private func reconnectDelayMilliseconds(for attempt: Int) -> Int {
        let boundedAttempt = min(max(attempt, 1), 6)
        return min(250 * (1 << (boundedAttempt - 1)), 8_000)
    }
}

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case reconnecting(attempt: Int)
    case connected
    case failed(String)

    var label: String {
        label(language: .english)
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .disconnected:
            switch language {
            case .japanese: "オフライン"
            case .english: "offline"
            }
        case .connecting:
            switch language {
            case .japanese: "接続中"
            case .english: "connecting"
            }
        case .reconnecting:
            switch language {
            case .japanese: "再接続中"
            case .english: "reconnecting"
            }
        case .connected:
            switch language {
            case .japanese: "接続済み"
            case .english: "connected"
            }
        case .failed:
            switch language {
            case .japanese: "エラー"
            case .english: "error"
            }
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var accessibilityLabel: String {
        accessibilityLabel(language: .english)
    }

    func accessibilityLabel(language: AppLanguage) -> String {
        switch self {
        case .disconnected:
            switch language {
            case .japanese: "Hub オフライン"
            case .english: "Hub offline"
            }
        case .connecting:
            switch language {
            case .japanese: "Hub 接続中"
            case .english: "Hub connecting"
            }
        case .reconnecting(let attempt):
            switch language {
            case .japanese: "Hub 再接続中、試行 \(attempt)"
            case .english: "Hub reconnecting, attempt \(attempt)"
            }
        case .connected:
            switch language {
            case .japanese: "Hub 接続済み"
            case .english: "Hub connected"
            }
        case .failed(let message):
            switch language {
            case .japanese: "Hub エラー: \(message)"
            case .english: "Hub error: \(message)"
            }
        }
    }

    var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

enum HubClientError: LocalizedError {
    case notConnected
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .notConnected: "Hub WebSocket is not connected."
        case .encodingFailed: "Could not encode control command."
        }
    }
}
