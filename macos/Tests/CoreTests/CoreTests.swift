import Foundation
import Darwin
import XCTest
@testable import MultiShiftCore

final class InterfaceCopyTests: XCTestCase {
    func testLowercaseCopyPreservesUnicodeFileNamesAndPaths() {
        let name = "Документы ABC.PDF"
        let path = "/Users/Example/Downloads/\(name)"
        XCTAssertEqual(interfaceCopy("Не удалось открыть \(path). Файл: \(name)", preserving: [name, path, name]),
                       "не удалось открыть \(path). файл: \(name)")
    }

    func testDisplayTransformationDoesNotMutateUserValues() {
        let name = "My Export.PNG"
        let source = "Completed · \(name)"
        XCTAssertEqual(interfaceCopy(source, preserving: [name]), "completed · My Export.PNG")
        XCTAssertEqual(source, "Completed · My Export.PNG")
        XCTAssertEqual(name, "My Export.PNG")
    }
}

final class FileJobCoordinatorTests: XCTestCase {
    func testStagesDuplicateNamesSeparatelyAndPublishesWithoutOverwrite() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = [root.appendingPathComponent("a/source.png"), root.appendingPathComponent("b/source.png")]
        for source in sources {
            try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1]).write(to: source)
        }
        let coordinator = FileJobCoordinator(jobsURL: root.appendingPathComponent("jobs"))
        let job = try coordinator.stage(sources, id: UUID())
        XCTAssertNotEqual(job.inputs[0].stagedURL, job.inputs[1].stagedURL)
        let outputs = job.inputs.map { input -> String in
            let output = input.stagedURL.deletingLastPathComponent().appendingPathComponent("result.png")
            try! Data([2]).write(to: output)
            return output.path
        }
        let first = try coordinator.publish(outputs, from: job)
        XCTAssertEqual(first.count, 2)
        try Data([3]).write(to: first[0])
        let second = try coordinator.publish(outputs, from: job)
        XCTAssertTrue(second.contains { $0.lastPathComponent == "result (1).png" })
        XCTAssertEqual(try Data(contentsOf: first[0]), Data([3]))
        coordinator.remove(job)
    }

    func testCancelledOrMissingSelectionLeavesNoJobDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let jobs = root.appendingPathComponent("jobs")
        let coordinator = FileJobCoordinator(jobsURL: jobs)
        XCTAssertThrowsError(try coordinator.stage([root.appendingPathComponent("missing.pdf")], id: UUID()))
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: jobs.path))?.count ?? 0, 0)
        try? FileManager.default.removeItem(at: root)
    }

    func testAccessDenialIsSurfacedAsRecoverableSelectionFailure() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("private.pdf")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([1]).write(to: source)
        let coordinator = FileJobCoordinator(jobsURL: root.appendingPathComponent("jobs"), fileCopier: { _, _ in
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))
        })
        XCTAssertThrowsError(try coordinator.stage([source], id: UUID())) { error in
            guard case FileJobError.accessDenied(let index) = error else { return XCTFail("unexpected error: \(error)") }
            XCTAssertEqual(index, 0)
        }
    }

    func testPublishFailurePreservesEarlierOutputsAndListsRemaining() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.png")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([1]).write(to: source)
        let coordinator = FileJobCoordinator(jobsURL: root.appendingPathComponent("jobs"))
        let job = try coordinator.stage([source], id: UUID())
        let good = job.inputs[0].stagedURL.deletingLastPathComponent().appendingPathComponent("good.png")
        try Data([2]).write(to: good)
        let missing = good.deletingLastPathComponent().appendingPathComponent("missing.png")
        XCTAssertThrowsError(try coordinator.publish([good.path, missing.path], from: job)) { error in
            guard let failure = error as? FilePublishFailure else { return XCTFail("unexpected error: \(error)") }
            XCTAssertEqual(failure.published.count, 1)
            XCTAssertEqual(failure.remaining, [missing.path])
            XCTAssertTrue(FileManager.default.fileExists(atPath: failure.published[0].path))
        }
        coordinator.remove(job)
    }
}

final class EngineClientTests: XCTestCase {
    private func worker(_ body: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("worker-\(UUID().uuidString).sh")
        try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func testAcceptsStructuredPartialResultOnNonzeroExit() throws {
        let id = UUID().uuidString
        let script = try worker("cat >/dev/null; printf '%s' '{\"request_id\":\"\(id)\",\"protocol_version\":1,\"ok\":false,\"outputs\":[\"/tmp/out.png\"]}'; exit 1")
        defer { try? FileManager.default.removeItem(at: script) }
        let response = try EngineClient().execute(executable: script, request: ["request_id": id, "action": "x"])
        XCTAssertEqual(response["request_id"] as? String, id)
    }

    func testReturnsStructuredFailureWithoutOutputs() throws {
        let id = UUID().uuidString
        let script = try worker("cat >/dev/null; printf '%s' '{\"request_id\":\"\(id)\",\"protocol_version\":1,\"ok\":false,\"outputs\":[],\"failures\":[{\"input_index\":0,\"code\":\"invalid_pdf\"}]}'; exit 1")
        defer { try? FileManager.default.removeItem(at: script) }
        let response = try EngineClient().execute(executable: script, request: ["request_id": id])
        XCTAssertEqual((response["failures"] as? [[String: Any]])?.count, 1)
    }

    func testReportsMalformedJSONAndCrash() throws {
        let script = try worker("cat >/dev/null; echo not-json; echo secret-password=test >&2")
        defer { try? FileManager.default.removeItem(at: script) }
        XCTAssertThrowsError(try EngineClient().execute(executable: script, request: ["request_id": UUID().uuidString]))
    }

    func testReportsSignalExit() throws {
        let script = try worker("cat >/dev/null; kill -ABRT $$")
        defer { try? FileManager.default.removeItem(at: script) }
        XCTAssertThrowsError(try EngineClient().execute(executable: script, request: ["request_id": UUID().uuidString])) { error in
            guard case EngineClientError.failedExit = error else { return XCTFail("unexpected error: \(error)") }
        }
    }
}

private final class FakeNotificationGateway: NotificationGateway {
    var state: NotificationPermission
    var submitted = 0
    var submitError: String?
    var requestAllowed = true
    init(_ state: NotificationPermission) { self.state = state }
    func permission(_ completion: @escaping (NotificationPermission) -> Void) { completion(state) }
    func requestPermission(_ completion: @escaping (Bool, String?) -> Void) { state = requestAllowed ? .authorized : .denied; completion(requestAllowed, nil) }
    func submit(id: String, title: String, body: String, completion: @escaping (String?) -> Void) { submitted += 1; completion(submitError) }
}

final class NotificationDispatcherTests: XCTestCase {
    func testAuthorizedNotificationIsSubmitted() {
        let gateway = FakeNotificationGateway(.authorized)
        let done = expectation(description: "submitted")
        NotificationDispatcher(gateway: gateway).send(id: "1", title: "Done", body: "Saved") { result in
            XCTAssertEqual(result, .transmitted); done.fulfill()
        }
        wait(for: [done], timeout: 1)
        XCTAssertEqual(gateway.submitted, 1)
    }

    func testPermissionDenialAndSubmissionErrorAreReported() {
        let denied = FakeNotificationGateway(.notDetermined)
        denied.requestAllowed = false
        NotificationDispatcher(gateway: denied).send(id: "1", title: "", body: "") { XCTAssertEqual($0, .denied) }
        let failing = FakeNotificationGateway(.provisional)
        failing.submitError = "unavailable"
        NotificationDispatcher(gateway: failing).send(id: "2", title: "", body: "") { XCTAssertEqual($0, .failed("unavailable")) }
        XCTAssertEqual(failing.submitted, 1)
    }
}
