import Foundation

public enum EngineClientError: Error, LocalizedError {
    case launch(String)
    case invalidResponse(String)
    case mismatchedRequest
    case failedExit(Int32, String)

    public var errorDescription: String? {
        switch self {
        case .launch(let detail):
            return detail.isEmpty ? "The processing engine could not be started." : "The processing engine could not be started: \(detail)"
        case .invalidResponse(let detail):
            return detail.isEmpty ? "The processing engine returned an invalid response." : "The processing engine returned an invalid response: \(detail)"
        case .mismatchedRequest: return "The processing engine response did not match the request."
        case .failedExit(let status, let detail):
            return detail.isEmpty ? "The processing engine stopped unexpectedly (\(status))." : "The processing engine stopped unexpectedly (\(status)): \(detail)"
        }
    }
}

/// Runs the packaged worker while draining both pipes so a verbose failure cannot deadlock it.
public struct EngineClient {
    public static let protocolVersion = 1
    public var maximumOutputBytes = 4 * 1024 * 1024

    public init() {}

    public func execute(executable: URL, arguments: [String] = [], request: [String: Any]) throws -> [String: Any] {
        var payload = request
        let requestID = (payload["request_id"] as? String) ?? UUID().uuidString
        payload["request_id"] = requestID
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let readers = DispatchGroup()
        let stdout = DataBuffer()
        let stderr = DataBuffer()
        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stdout.set(Self.drain(output.fileHandleForReading, limit: self.maximumOutputBytes))
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            stderr.set(Self.drain(errors.fileHandleForReading, limit: 64 * 1024))
            readers.leave()
        }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.closeFile()
            errors.fileHandleForReading.closeFile()
            throw EngineClientError.launch(Self.safeDetail(error.localizedDescription))
        }
        do {
            try input.fileHandleForWriting.write(contentsOf: data)
            input.fileHandleForWriting.closeFile()
        } catch {
            input.fileHandleForWriting.closeFile()
        }
        process.waitUntilExit()
        readers.wait()

        let stdoutData = stdout.get(), stderrData = stderr.get()
        guard let response = try? JSONSerialization.jsonObject(with: stdoutData) as? [String: Any],
              let version = response["protocol_version"] as? Int,
              version == Self.protocolVersion else {
            if process.terminationReason == .uncaughtSignal {
                throw EngineClientError.failedExit(process.terminationStatus,
                                                    Self.safeDetail(String(data: stderrData, encoding: .utf8) ?? ""))
            }
            throw EngineClientError.invalidResponse(Self.safeDetail(String(data: stderrData, encoding: .utf8) ?? ""))
        }
        guard response["request_id"] as? String == requestID else {
            throw EngineClientError.mismatchedRequest
        }
        // A non-zero exit is expected for a structured partial result; only reject it when
        // the worker failed before it could return the result envelope.
        if process.terminationStatus != 0,
           (response["outputs"] as? [String] ?? []).isEmpty,
           (response["failures"] as? [[String: Any]] ?? []).isEmpty,
           response["error"] == nil {
            throw EngineClientError.failedExit(process.terminationStatus,
                                                Self.safeDetail(String(data: stderrData, encoding: .utf8) ?? ""))
        }
        return response
    }

    public static func safeDetail(_ value: String) -> String {
        var detail = value
        // Paths and request secrets should never enter operation history or diagnostic logs.
        detail = detail.replacingOccurrences(of: #"(?m)(/Users/|/private/|/Volumes/)[^\s:'\"]+"#, with: "[file]", options: .regularExpression)
        detail = detail.replacingOccurrences(of: #"(?i)(password|passwd|owner_pw|user_pw)\s*[:=]\s*[^\s,;]+"#, with: "$1=[redacted]", options: .regularExpression)
        if detail.count > 500 { detail = String(detail.prefix(500)) }
        return detail
    }

    private static func drain(_ handle: FileHandle, limit: Int) -> Data {
        var result = Data()
        while true {
            let chunk = handle.readData(ofLength: 16 * 1024)
            if chunk.isEmpty { break }
            if result.count < limit { result.append(chunk.prefix(limit - result.count)) }
        }
        return result
    }
}

private final class DataBuffer {
    private let lock = NSLock()
    private var value = Data()
    func set(_ data: Data) { lock.lock(); value = data; lock.unlock() }
    func get() -> Data { lock.lock(); defer { lock.unlock() }; return value }
}
