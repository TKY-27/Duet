import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published var connectionState: ConnectionState = .disconnected
    @Published var running = false
    @Published var repoPath = ""
    @Published var roles = Roles(
        claude: RoleAssignment(role: "implementer", task: "Implement the requested change and ask Codex for review."),
        codex: RoleAssignment(role: "reviewer", task: "Read changed files from disk and review the implementation.")
    )
    @Published var transcript: [BusMessage] = []
    @Published var queues = QueueDepth(claude: 0, codex: 0)
    @Published var holdSec = 50
    @Published var noProgressHoldSec = 25
    @Published var progressIntervalSec = 20
    @Published var stallThresholdSec = 120
    @Published var stalls = AgentStalls.normal
    @Published var theme: DuetTheme = .dark
    @Published var lastError: String?
    @Published private(set) var hubOutput = HubProcessOutput.empty

    let projectRoot = ProjectLocator.projectRoot()
    private let port = 8765
    private let processManager = HubProcessManager()
    private var controlToken: String?
    private var healthTask: Task<Void, Never>?
    private let healthBackoffMilliseconds = [0, 100, 200, 400, 800, 1_200, 2_000]
    private lazy var client = HubClient(
        onEvent: { [weak self] event in self?.apply(event) },
        onStateChange: { [weak self] state in
            self?.connectionState = state
            if let failureMessage = state.failureMessage {
                self?.lastError = self?.redact(failureMessage)
            }
        }
    )

    init() {
        processManager.outputHandler = { [weak self] output in
            guard let self else { return }
            hubOutput = output.redacted(projectRoot: projectRoot)
        }
        processManager.terminationHandler = { [weak self] termination in
            self?.handleHubTermination(termination)
        }
    }

    var branchLabel: String {
        "local"
    }

    func start() {
        do {
            let token = try processManager.start(projectRoot: projectRoot, port: port)
            controlToken = token
            running = true
            connect()
        } catch {
            recordError(error, updateConnectionState: true)
        }
    }

    func stop() {
        Task {
            if await sendCommand(SimpleCommand(type: "stop")) {
                running = false
            }
        }
    }

    func resume() {
        Task {
            if await sendCommand(SimpleCommand(type: "start")) {
                running = true
            }
        }
    }

    func shutdown() async {
        healthTask?.cancel()
        healthTask = nil
        client.disconnect()
        do {
            try await processManager.stop()
        } catch {
            recordError(error, updateConnectionState: true)
        }
        controlToken = nil
        running = false
        stalls = .normal
    }

    func connect() {
        guard controlToken != nil else {
            lastError = "Hub control token is unavailable. Start the Hub before reconnecting."
            connectionState = .failed("Hub control token is unavailable.")
            return
        }
        healthTask?.cancel()
        healthTask = Task { [weak self] in
            await self?.connectWhenHealthy()
        }
    }

    @discardableResult
    func setRoles(_ roles: Roles) async -> Bool {
        let issues = RoleValidator.issues(for: roles)
        guard issues.isEmpty else {
            lastError = issues.map(\.message).joined(separator: " ")
            return false
        }

        guard await sendCommand(SetRolesCommand(roles: roles)) else { return false }
        self.roles = roles
        return true
    }

    @discardableResult
    func inject(message: String, to recipient: Recipient) async -> Bool {
        await sendCommand(InjectHumanCommand(to: recipient, message: message))
    }

    private func connectWhenHealthy() async {
        do {
            try await waitForHubHealth()
            guard let controlToken else { throw AppStoreError.missingControlToken }
            guard let url = controlURL() else { throw AppStoreError.invalidControlURL }
            client.connect(url: url, controlToken: controlToken)
        } catch is CancellationError {
            return
        } catch {
            recordError(error, updateConnectionState: true)
        }
    }

    private func waitForHubHealth() async throws {
        guard let url = healthURL() else { throw AppStoreError.invalidHealthURL }
        var lastFailure: String?

        for delayMilliseconds in healthBackoffMilliseconds {
            try Task.checkCancellation()
            if delayMilliseconds > 0 {
                try await Task.sleep(for: .milliseconds(delayMilliseconds))
            }

            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 1.0
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AppStoreError.invalidHealthResponse("missing HTTP response")
                }
                guard httpResponse.statusCode == 200 else {
                    throw AppStoreError.invalidHealthResponse("HTTP \(httpResponse.statusCode)")
                }
                let health = try JSONDecoder().decode(HubHealth.self, from: data)
                if health.ok {
                    return
                }
                lastFailure = "health returned ok=false"
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastFailure = error.localizedDescription
            }
        }

        throw AppStoreError.healthCheckTimedOut(lastFailure)
    }

    private func controlURL() -> URL? {
        var components = URLComponents()
        components.scheme = "ws"
        components.host = "127.0.0.1"
        components.port = port
        components.path = "/control"
        return components.url
    }

    private func healthURL() -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = port
        components.path = "/health"
        return components.url
    }

    private func sendCommand<T: Encodable>(_ command: T) async -> Bool {
        do {
            try await client.send(command)
            lastError = nil
            return true
        } catch {
            recordError(error)
            return false
        }
    }

    private func apply(_ event: ControlEvent) {
        connectionState = .connected
        switch event {
        case .snapshot(let snapshot):
            running = snapshot.running
            repoPath = snapshot.repoPath
            roles = snapshot.roles
            transcript = snapshot.transcript
            queues = snapshot.queues
            holdSec = snapshot.holdSec
            noProgressHoldSec = snapshot.noProgressHoldSec
            progressIntervalSec = snapshot.progressIntervalSec
            stallThresholdSec = snapshot.stallThresholdSec
            stalls = snapshot.stalls
            lastError = nil
        case .message(let message):
            transcript.append(message)
            if transcript.count > 300 {
                transcript.removeFirst(transcript.count - 300)
            }
        case .rolesUpdated(let roles):
            self.roles = roles
        case .status(let running):
            self.running = running
            if !running {
                stalls = .normal
            }
        case .stall(let agent, let stalled, let sinceMs):
            stalls[agent] = AgentStall(stalled: stalled, sinceMs: sinceMs)
        case .error(let message):
            lastError = redact(message)
        }
    }

    private func handleHubTermination(_ termination: HubProcessTermination) {
        hubOutput = termination.output.redacted(projectRoot: projectRoot)
        controlToken = nil
        running = false
        healthTask?.cancel()
        healthTask = nil
        client.disconnect()

        guard !termination.expected else { return }

        var message = "Hub exited unexpectedly with status \(termination.status) (\(termination.reason.rawValue))."
        if let latestStderr = hubOutput.latestStderr {
            message += " stderr: \(latestStderr)"
        }
        recordError(message, updateConnectionState: true)
    }

    private func recordError(_ error: Error, updateConnectionState: Bool = false) {
        recordError(error.localizedDescription, updateConnectionState: updateConnectionState)
    }

    private func recordError(_ message: String, updateConnectionState: Bool = false) {
        let redacted = redact(message)
        lastError = redacted
        if updateConnectionState {
            connectionState = .failed(redacted)
        }
    }

    private func redact(_ message: String) -> String {
        DuetErrorRedactor.redact(message, projectRoot: projectRoot)
    }
}

private struct HubHealth: Decodable {
    var ok: Bool
}

private enum AppStoreError: LocalizedError {
    case missingControlToken
    case invalidControlURL
    case invalidHealthURL
    case invalidHealthResponse(String)
    case healthCheckTimedOut(String?)

    var errorDescription: String? {
        switch self {
        case .missingControlToken:
            "Hub control token is unavailable."
        case .invalidControlURL:
            "Could not build Hub control WebSocket URL."
        case .invalidHealthURL:
            "Could not build Hub health URL."
        case .invalidHealthResponse(let reason):
            "Hub health check returned an invalid response: \(reason)."
        case .healthCheckTimedOut(let lastFailure):
            if let lastFailure {
                "Hub did not become healthy before connecting to control WebSocket. Last error: \(lastFailure)."
            } else {
                "Hub did not become healthy before connecting to control WebSocket."
            }
        }
    }
}
