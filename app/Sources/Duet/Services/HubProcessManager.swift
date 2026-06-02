import Foundation
import Security
import Darwin

@MainActor
final class HubProcessManager {
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var stdoutRing = HubOutputRingBuffer<String>(limit: 80)
    private var stderrRing = HubOutputRingBuffer<String>(limit: 80)
    private var expectedTerminationPIDs = Set<Int32>()
    private var controlToken: String?

    var outputHandler: ((HubProcessOutput) -> Void)?
    var terminationHandler: ((HubProcessTermination) -> Void)?

    var isRunning: Bool {
        process?.isRunning == true
    }

    func start(projectRoot: URL, port: Int) throws -> String {
        if isRunning {
            guard let token = controlToken else { throw HubProcessError.missingControlToken }
            return token
        }
        if let staleProcess = process, !staleProcess.isRunning {
            cleanupProcessIfCurrent(pid: staleProcess.processIdentifier)
        }

        let serverScript = projectRoot.appendingPathComponent("hub/dist/server.js")
        guard FileManager.default.fileExists(atPath: serverScript.path) else {
            throw HubProcessError.serverNotBuilt(serverScript.path)
        }

        let configPath = resolveConfigPath(projectRoot: projectRoot)
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            throw HubProcessError.configNotFound(configPath.path)
        }

        let nodeExecutable = try resolveNodeExecutable()
        let token = try readOrGenerateControlToken()

        let nextProcess = Process()
        nextProcess.executableURL = nodeExecutable
        nextProcess.arguments = [serverScript.path, "--config", configPath.path, "--port", String(port)]
        nextProcess.currentDirectoryURL = projectRoot

        clearOutput()
        let nextOutputPipe = Pipe()
        let nextErrorPipe = Pipe()
        outputPipe = nextOutputPipe
        errorPipe = nextErrorPipe

        nextProcess.environment = minimalEnvironment(projectRoot: projectRoot, controlToken: token)
        nextProcess.standardOutput = nextOutputPipe
        nextProcess.standardError = nextErrorPipe
        nextOutputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor [weak self] in
                self?.appendOutput(text, stream: .stdout)
            }
        }
        nextErrorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor [weak self] in
                self?.appendOutput(text, stream: .stderr)
            }
        }
        nextProcess.terminationHandler = { [weak self] terminatedProcess in
            let pid = terminatedProcess.processIdentifier
            let status = terminatedProcess.terminationStatus
            let reason = HubProcessTerminationReason(processReason: terminatedProcess.terminationReason)
            Task { @MainActor [weak self] in
                self?.handleTermination(pid: pid, status: status, reason: reason)
            }
        }

        process = nextProcess
        controlToken = token
        do {
            try nextProcess.run()
        } catch {
            cleanupProcessIfCurrent(pid: nextProcess.processIdentifier)
            throw error
        }
        return token
    }

    func stop(gracefulTimeoutMilliseconds: Int = 2_000, killTimeoutMilliseconds: Int = 1_000) async throws {
        guard let process else { return }
        let pid = process.processIdentifier
        expectedTerminationPIDs.insert(pid)

        if process.isRunning {
            process.terminate()
            let exitedGracefully = await waitForExit(pid: pid, timeoutMilliseconds: gracefulTimeoutMilliseconds)
            if !exitedGracefully, process.isRunning {
                if Darwin.kill(pid, SIGKILL) != 0, errno != ESRCH {
                    throw HubProcessError.killFailed(pid: pid, errno: errno)
                }
                _ = await waitForExit(pid: pid, timeoutMilliseconds: killTimeoutMilliseconds)
            }
        }
        cleanupProcessIfCurrent(pid: pid)
    }

    var outputSnapshot: HubProcessOutput {
        HubProcessOutput(stdout: stdoutRing.values, stderr: stderrRing.values)
    }

    private func resolveNodeExecutable() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        let candidates = [
            environment["DUET_NODE_PATH"],
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
        ].compactMap { $0 }.filter { $0.hasPrefix("/") }

        for candidate in candidates {
            guard FileManager.default.isExecutableFile(atPath: candidate) else { continue }
            let executable = URL(fileURLWithPath: candidate)
            try validateNodeVersion(executable)
            return executable
        }

        throw HubProcessError.nodeNotFound
    }

    private func validateNodeVersion(_ executable: URL) throws {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = ["--version"]
        process.environment = minimalEnvironment(projectRoot: nil, controlToken: nil)
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw HubProcessError.unsupportedNodeVersion("unknown")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let major = parseNodeMajorVersion(version)
        guard let major, major >= 20 else {
            throw HubProcessError.unsupportedNodeVersion(version.isEmpty ? "unknown" : version)
        }
    }

    private func parseNodeMajorVersion(_ version: String) -> Int? {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        guard let major = withoutPrefix.split(separator: ".").first else { return nil }
        return Int(major)
    }

    private func minimalEnvironment(projectRoot: URL?, controlToken: String?) -> [String: String] {
        var environment: [String: String] = [:]
        let source = ProcessInfo.processInfo.environment
        for key in ["TMPDIR", "HOME", "LANG", "LC_CTYPE"] {
            if let value = source[key] {
                environment[key] = value
            }
        }
        if let projectRoot {
            environment["DUET_REPO_ROOT"] = projectRoot.path
        }
        if let controlToken {
            environment["DUET_CONTROL_TOKEN"] = controlToken
        }
        return environment
    }

    private func resolveConfigPath(projectRoot: URL) -> URL {
        if let explicit = ProcessInfo.processInfo.environment["DUET_CONFIG"], !explicit.isEmpty {
            return URL(fileURLWithPath: explicit)
        }
        return projectRoot.appendingPathComponent("config/duet.config.json")
    }

    private func readOrGenerateControlToken() throws -> String {
        if let explicit = ProcessInfo.processInfo.environment["DUET_CONTROL_TOKEN"], !explicit.isEmpty {
            guard isValidBase64URLToken(explicit) else {
                throw HubProcessError.invalidControlToken
            }
            return explicit
        }
        return try generateControlToken()
    }

    private func generateControlToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw HubProcessError.controlTokenGenerationFailed
        }
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func isValidBase64URLToken(_ token: String) -> Bool {
        guard token.count >= 43 else { return false }
        guard token.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return false }
        return Set(token).count >= 16
    }

    private func appendOutput(_ text: String, stream: HubOutputStream) {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        let entries = lines.isEmpty ? [text] : lines
        for entry in entries {
            switch stream {
            case .stdout:
                stdoutRing.append(entry)
            case .stderr:
                stderrRing.append(entry)
            }
        }
        outputHandler?(outputSnapshot)
    }

    private func clearOutput() {
        stdoutRing.removeAll()
        stderrRing.removeAll()
        outputHandler?(outputSnapshot)
    }

    private func handleTermination(pid: Int32, status: Int32, reason: HubProcessTerminationReason) {
        let expected = expectedTerminationPIDs.remove(pid) != nil
        if process?.processIdentifier == pid {
            cleanupProcessIfCurrent(pid: pid)
        }
        terminationHandler?(
            HubProcessTermination(
                pid: pid,
                status: status,
                reason: reason,
                expected: expected,
                output: outputSnapshot
            )
        )
    }

    private func cleanupProcessIfCurrent(pid: Int32) {
        guard process?.processIdentifier == pid else { return }
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        errorPipe = nil
        process = nil
        controlToken = nil
    }

    private func waitForExit(pid: Int32, timeoutMilliseconds: Int) async -> Bool {
        var waitedMilliseconds = 0
        let stepMilliseconds = 50

        while waitedMilliseconds < timeoutMilliseconds {
            guard process?.processIdentifier == pid else { return true }
            if process?.isRunning != true { return true }
            try? await Task.sleep(for: .milliseconds(stepMilliseconds))
            waitedMilliseconds += stepMilliseconds
        }

        return process?.processIdentifier != pid || process?.isRunning != true
    }
}

enum HubProcessError: LocalizedError {
    case serverNotBuilt(String)
    case configNotFound(String)
    case nodeNotFound
    case unsupportedNodeVersion(String)
    case controlTokenGenerationFailed
    case invalidControlToken
    case missingControlToken
    case killFailed(pid: Int32, errno: Int32)

    var errorDescription: String? {
        switch self {
        case .serverNotBuilt(let path):
            "Hub build artifact was not found at \(path). Run npm --prefix hub run build."
        case .configNotFound(let path):
            "Duet config was not found at \(path). Copy config/duet.config.example.json to config/duet.config.json and set repoPath before starting."
        case .nodeNotFound:
            "Node.js 20 or newer was not found at a known absolute path. Set DUET_NODE_PATH to an absolute node executable if needed."
        case .unsupportedNodeVersion(let version):
            "Duet Hub requires Node.js 20 or newer. Found \(version)."
        case .controlTokenGenerationFailed:
            "Could not generate a secure Hub control token."
        case .invalidControlToken:
            "DUET_CONTROL_TOKEN must be at least 32 bytes of base64url entropy."
        case .missingControlToken:
            "Hub is running but its control token is unavailable."
        case .killFailed(let pid, let errno):
            "Could not force quit Hub process \(pid) after graceful termination failed. errno=\(errno)."
        }
    }
}

struct HubProcessOutput: Equatable {
    var stdout: [String]
    var stderr: [String]

    static let empty = HubProcessOutput(stdout: [], stderr: [])

    var latestStderr: String? {
        stderr.last
    }
}

struct HubProcessTermination: Equatable {
    var pid: Int32
    var status: Int32
    var reason: HubProcessTerminationReason
    var expected: Bool
    var output: HubProcessOutput
}

enum HubProcessTerminationReason: String, Equatable {
    case exit
    case uncaughtSignal
    case unknown

    init(processReason: Process.TerminationReason) {
        switch processReason {
        case .exit:
            self = .exit
        case .uncaughtSignal:
            self = .uncaughtSignal
        @unknown default:
            self = .unknown
        }
    }
}

enum HubOutputStream {
    case stdout
    case stderr
}

struct HubOutputRingBuffer<Element: Equatable>: Equatable {
    private(set) var values: [Element] = []
    let limit: Int

    mutating func append(_ value: Element) {
        guard limit > 0 else { return }
        values.append(value)
        if values.count > limit {
            values.removeFirst(values.count - limit)
        }
    }

    mutating func removeAll() {
        values.removeAll(keepingCapacity: true)
    }
}
