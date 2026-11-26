import Combine
import Foundation
import XCTest
@testable import TraceServiceFixes

final class RecordingGateRegressionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testDisabledGateNeverCallsWriter() {
        let gate = CaptureRecordingState(enabled: false)
        let result = gate.withRecording(startedAt: start) { XCTFail("Disabled writer ran"); return true }
        XCTAssertNil(result)
        XCTAssertFalse(gate.isRecording)
    }

    func testRecordingIncludesItsBoundaryButNotOlderRequests() {
        let gate = CaptureRecordingState(enabled: true, startedAt: start)
        XCTAssertFalse(gate.allows(startedAt: start.addingTimeInterval(-0.001)))
        XCTAssertTrue(gate.allows(startedAt: start))
        XCTAssertEqual(gate.withRecording(startedAt: start) { 42 }, 42)
    }

    func testStopRejectsQueuedWrites() {
        let gate = CaptureRecordingState(enabled: true, startedAt: start)
        gate.setRecording(false)
        XCTAssertNil(gate.withRecording(startedAt: start.addingTimeInterval(2)) { true })
    }

    func testResumeRejectsPreviousAndPausedIntervals() {
        let gate = CaptureRecordingState(enabled: true, startedAt: start)
        gate.setRecording(false)
        gate.setRecording(true, startedAt: start.addingTimeInterval(10))
        XCTAssertFalse(gate.allows(startedAt: start.addingTimeInterval(1)))
        XCTAssertFalse(gate.allows(startedAt: start.addingTimeInterval(9)))
        XCTAssertTrue(gate.allows(startedAt: start.addingTimeInterval(10)))
    }

    func testServiceEndCannotBeUndoneByAnOldQueuedToggle() {
        let gate = CaptureRecordingState(enabled: true, startedAt: start)
        gate.endService()
        gate.setRecording(true, startedAt: start.addingTimeInterval(10))
        XCTAssertFalse(gate.isRecording)
    }

    func testNewServiceStartsPausedUntilExplicitRecording() {
        let gate = CaptureRecordingState(enabled: true, startedAt: start)
        gate.endService()
        gate.beginService()
        XCTAssertFalse(gate.isRecording)
        gate.setRecording(true, startedAt: start.addingTimeInterval(10))
        XCTAssertTrue(gate.isRecording)
    }

    func testThrowingWriterReleasesBarrier() {
        enum WriteError: Error { case failed }
        let gate = CaptureRecordingState(enabled: true, startedAt: start)
        XCTAssertThrowsError(try gate.withRecording(startedAt: start) { throw WriteError.failed })
        gate.setRecording(false)
        XCTAssertFalse(gate.isRecording)
    }

    func testStopWaitsForAnInflightDatabaseWrite() {
        let gate = CaptureRecordingState(enabled: true, startedAt: start)
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let stopFinished = DispatchSemaphore(value: 0)
        let timestamp = start
        DispatchQueue.global().async {
            gate.withRecording(startedAt: timestamp) {
                entered.signal()
                _ = release.wait(timeout: .now() + 5)
            }
            finished.signal()
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        DispatchQueue.global().async { gate.setRecording(false); stopFinished.signal() }
        XCTAssertEqual(stopFinished.wait(timeout: .now() + 0.03), .timedOut)
        release.signal()
        XCTAssertEqual(finished.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(stopFinished.wait(timeout: .now() + 2), .success)
        XCTAssertFalse(gate.isRecording)
    }
}

private actor TransitionProbe {
    private var active = 0
    private var maximum = 0
    private var completed = 0
    func begin() { active += 1; maximum = max(maximum, active) }
    func end() { active -= 1; completed += 1 }
    func result() -> (Int, Int) { (maximum, completed) }
}

final class RecordingTransitionRegressionTests: XCTestCase {
    func testWholeTransitionsRemainSerialAcrossAwaits() async {
        let queue = RecordingTransitionQueue()
        let probe = TransitionProbe()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<30 {
                group.addTask {
                    await queue.perform {
                        await probe.begin()
                        try? await Task.sleep(nanoseconds: 1_000_000)
                        await Task.yield()
                        await probe.end()
                    }
                }
            }
        }
        let result = await probe.result()
        XCTAssertEqual(result.0, 1)
        XCTAssertEqual(result.1, 30)
    }

    func testCancellingCallerDoesNotSkipAnAlreadyAcceptedStop() async {
        let queue = RecordingTransitionQueue()
        let gate = CaptureRecordingState(enabled: true)
        let caller = Task { await queue.perform { gate.setRecording(false) } }
        caller.cancel()
        await caller.value
        XCTAssertFalse(gate.isRecording)
    }
}

final class ProviderReplyRegressionTests: XCTestCase {
    func testOnlyFirstReplyResumesContinuation() async throws {
        let expected = Data("confirmed".utf8)
        let actual: Data? = try await withCheckedThrowingContinuation { continuation in
            let reply = VPNMessageReply(continuation)
            reply.finish(.success(expected))
            reply.finish(.success(nil))
            reply.finish(.failure(VPNMessageReply.ReplyError.unconfirmed))
        }
        XCTAssertEqual(actual, expected)
    }

    func testTimeoutWinsOverLateSuccessWithoutResumingTwice() async {
        do {
            let _: Data? = try await withCheckedThrowingContinuation { continuation in
                let reply = VPNMessageReply(continuation)
                reply.finish(.failure(VPNMessageReply.ReplyError.unconfirmed))
                reply.finish(.success(Data("late".utf8)))
            }
            XCTFail("Unknown result was treated as success")
        } catch {
            XCTAssertTrue(error is VPNMessageReply.ReplyError)
        }
    }
}

final class RecordingConfigurationRegressionTests: XCTestCase {
    func testOldConfigurationRetainsLegacyRecordingDefault() throws {
        let decoded = try JSONDecoder().decode(CaptureConfiguration.self, from: Data("{}".utf8))
        XCTAssertTrue(decoded.isRecordingEnabled)
    }

    func testServiceOnlySettingSurvivesEncodingAndDecoding() throws {
        var value = CaptureConfiguration.default
        value.isRecordingEnabled = false
        let decoded = try JSONDecoder().decode(CaptureConfiguration.self, from: JSONEncoder().encode(value))
        XCTAssertFalse(decoded.isRecordingEnabled)
        XCTAssertEqual(decoded.captureMode, value.captureMode)
        XCTAssertEqual(decoded.maxBodySize, value.maxBodySize)
    }

    func testRecordingFieldIsSeparateFromRequestCapturePolicy() throws {
        var value = CaptureConfiguration.default
        value.isEnabled = true
        value.isRecordingEnabled = false
        XCTAssertTrue(value.isEnabled)
        XCTAssertFalse(value.isRecordingEnabled)
    }
}

@MainActor
private final class ConfigurationBox {
    var value = CaptureConfiguration.default
    var failSave = false
    init() { value.isRecordingEnabled = false }
}

@MainActor
private final class SessionSpy: CaptureSessionCoordinating {
    var began = 0
    var ended = 0
    var aborted = 0
    var currentID: UUID?
    var failBegin = false
    func beginCaptureSession() throws -> UUID? {
        if failBegin { throw NetworkCaptureService.ServiceError.sessionUnavailable }
        if currentID != nil { return nil }
        let id = UUID()
        currentID = id
        began += 1
        return id
    }
    func endCaptureSession(reason: SessionEndReason) {
        if currentID != nil { ended += 1; currentID = nil }
    }
    func abortCaptureSession(_ newlyCreatedID: UUID) {
        XCTAssertEqual(currentID, newlyCreatedID)
        aborted += 1
        currentID = nil
    }
}

@MainActor
private final class MemoryVPN: VPNManaging {
    enum Failure: Error { case start, save, prepare, stop }
    let subject = CurrentValueSubject<Bool, Never>(false)
    var isConnected: Bool { get { subject.value } set { subject.send(newValue) } }
    var isConnectedPublisher: AnyPublisher<Bool, Never> { subject.eraseToAnyPublisher() }
    var transitioning = false
    var isDefinitelyStopped: Bool { !isConnected && !transitioning }
    var starts = 0
    var stops = 0
    var messages = 0
    var queries = 0
    var failStart = false
    var failPrepare = false
    var failStop = false
    var missingReply = false
    var missingQueryReply = false
    var oppositeReply = false
    var actualRecording = false
    var recording: () -> Bool = { false }
    var prepareHook: (() async -> Void)?
    func prepareForControl() async throws {
        if failPrepare { throw Failure.prepare }
        if let prepareHook { await prepareHook() }
        if transitioning { throw Failure.prepare }
    }
    func start() async throws {
        starts += 1
        if failStart { throw Failure.start }
        isConnected = true
    }
    func stop() { stops += 1; isConnected = false; actualRecording = false }
    func stopAndWait() async throws {
        if failStop { throw Failure.stop }
        stop()
    }
    func sendMessage(_ message: [String: Any]) async throws -> Data? {
        let command = message["command"] as? String
        if command == "getRecordingState" {
            queries += 1
            if missingQueryReply { return nil }
        } else {
            XCTAssertEqual(command, "setRecordingState")
            messages += 1
            actualRecording = oppositeReply ? !recording() : recording()
            if missingReply { return nil }
        }
        return try JSONSerialization.data(withJSONObject: ["recording": actualRecording])
    }
}

@MainActor
final class NetworkServiceControlRegressionTests: XCTestCase {
    private func make() -> (NetworkCaptureService, MemoryVPN, ConfigurationBox, SessionSpy) {
        let vpn = MemoryVPN()
        let box = ConfigurationBox()
        let sessions = SessionSpy()
        vpn.recording = { box.value.isRecordingEnabled }
        let service = NetworkCaptureService(vpnManager: vpn, sessionCoordinator: sessions,
            loadConfiguration: { box.value }, saveConfiguration: {
                if box.failSave { throw MemoryVPN.Failure.save }
                box.value = $0
            })
        return (service, vpn, box, sessions)
    }

    func testServiceOnlyStartCreatesNoCaptureSession() async throws {
        let (service, vpn, box, sessions) = make()
        try await service.startService()
        XCTAssertTrue(vpn.isConnected)
        XCTAssertFalse(service.isCapturing)
        XCTAssertFalse(box.value.isRecordingEnabled)
        XCTAssertEqual(sessions.began, 0)
    }

    func testStartRecordingOnRunningServiceDoesNotRestartVPN() async throws {
        let (service, vpn, _, sessions) = make()
        try await service.startService()
        try await service.startCapture()
        XCTAssertEqual(vpn.starts, 1)
        XCTAssertEqual(vpn.messages, 2)
        XCTAssertEqual(vpn.queries, 1)
        XCTAssertTrue(service.isCapturing)
        XCTAssertEqual(sessions.began, 1)
    }

    func testStoppingRecordingKeepsVPNAndEndsSession() async throws {
        let (service, vpn, _, sessions) = make()
        try await service.startCapture()
        try await service.stopCapture()
        XCTAssertTrue(vpn.isConnected)
        XCTAssertEqual(vpn.stops, 0)
        XCTAssertFalse(service.isCapturing)
        XCTAssertEqual(sessions.ended, 1)
    }

    func testResumeAfterConfirmedStopBeginsAnotherSession() async throws {
        let (service, vpn, _, sessions) = make()
        try await service.startCapture()
        try await service.stopCapture()
        try await service.startCapture()
        XCTAssertEqual(vpn.starts, 1)
        XCTAssertEqual(sessions.began, 2)
        XCTAssertEqual(sessions.ended, 1)
    }

    func testExplicitServiceStopActuallyStopsVPN() async throws {
        let (service, vpn, _, _) = make()
        try await service.startService()
        try await service.stopService()
        XCTAssertEqual(vpn.stops, 1)
        XCTAssertFalse(vpn.isConnected)
    }

    func testServiceStopStillStopsVPNWhenAcknowledgementIsMissing() async throws {
        let (service, vpn, _, _) = make()
        try await service.startService()
        vpn.missingReply = true
        try await service.stopService()
        XCTAssertEqual(vpn.stops, 1)
        XCTAssertFalse(vpn.isConnected)
        XCTAssertEqual(service.recordingState, .paused)
    }

    func testUnknownStartAcknowledgementDoesNotAbortPossiblyAdoptedSession() async throws {
        let (service, vpn, _, sessions) = make()
        try await service.startService()
        vpn.missingReply = true
        do { try await service.startCapture(); XCTFail("Unknown start was reported as success") }
        catch {
            XCTAssertEqual(sessions.began, 1)
            XCTAssertEqual(sessions.aborted, 0)
            XCTAssertEqual(vpn.messages, 2)
            XCTAssertTrue(vpn.isConnected)
            XCTAssertEqual(service.recordingState, .unknown)
            XCTAssertFalse(service.isCapturing)
        }
        let changes = vpn.messages
        try await service.refreshRecordingState()
        XCTAssertTrue(service.isCapturing)
        XCTAssertEqual(vpn.messages, changes)
        try await service.startCapture()
        XCTAssertEqual(sessions.began, 1)
        XCTAssertEqual(vpn.messages, changes)
    }

    func testUnknownStopAcknowledgementDoesNotPrematurelyCloseSession() async throws {
        let (service, vpn, _, sessions) = make()
        try await service.startCapture()
        vpn.missingReply = true
        do { try await service.stopCapture(); XCTFail("Unknown stop was reported as success") }
        catch {
            XCTAssertEqual(sessions.ended, 0)
            XCTAssertEqual(vpn.stops, 0)
            XCTAssertEqual(service.recordingState, .unknown)
        }
        let changes = vpn.messages
        try await service.refreshRecordingState()
        XCTAssertEqual(service.recordingState, .paused)
        XCTAssertEqual(vpn.messages, changes)
        XCTAssertTrue(vpn.isConnected)
    }

    func testOppositeStateAcknowledgementIsAnError() async throws {
        let (service, vpn, _, _) = make()
        try await service.startService()
        vpn.oppositeReply = true
        do { try await service.startCapture(); XCTFail("Mismatched state was accepted") }
        catch {
            XCTAssertEqual(vpn.messages, 2)
            XCTAssertEqual(service.recordingState, .unknown)
        }
    }

    func testFailedVPNStartAbortsOnlyTheUnusedSession() async {
        let (service, vpn, box, sessions) = make()
        vpn.failStart = true
        do { try await service.startCapture(); XCTFail("Failed start was accepted") }
        catch {
            XCTAssertEqual(sessions.aborted, 1)
            XCTAssertFalse(box.value.isRecordingEnabled)
        }
    }

    func testFailedConfigurationSaveDoesNotStartVPN() async {
        let (service, vpn, box, sessions) = make()
        box.failSave = true
        do { try await service.startCapture(); XCTFail("Failed save was accepted") }
        catch { XCTAssertEqual(vpn.starts, 0); XCTAssertEqual(sessions.aborted, 1) }
    }

    func testFailureNeverAbortsAReusedSession() async {
        let (service, vpn, box, sessions) = make()
        let existingID = UUID()
        sessions.currentID = existingID
        box.failSave = true
        do { try await service.startCapture(); XCTFail("Failed save was accepted") }
        catch {
            XCTAssertEqual(sessions.aborted, 0)
            XCTAssertEqual(sessions.currentID, existingID)
            XCTAssertEqual(vpn.starts, 0)
        }
    }

    func testSessionCreationFailureDoesNotStartRecording() async {
        let (service, vpn, box, sessions) = make()
        sessions.failBegin = true
        do { try await service.startCapture(); XCTFail("Missing session was accepted") }
        catch {
            XCTAssertEqual(vpn.starts, 0)
            XCTAssertEqual(vpn.messages, 0)
            XCTAssertFalse(box.value.isRecordingEnabled)
        }
    }

    func testColdControlOfExistingServiceOnlyQueriesActualState() async throws {
        let (service, vpn, box, sessions) = make()
        vpn.isConnected = true
        vpn.actualRecording = true
        try await service.startService()
        XCTAssertTrue(service.isCapturing)
        XCTAssertFalse(box.value.isRecordingEnabled)
        XCTAssertEqual(vpn.starts, 0)
        XCTAssertEqual(vpn.messages, 0)
        XCTAssertEqual(vpn.queries, 1)
        XCTAssertEqual(sessions.began, 0)
    }

    func testFailedReadOnlyQueryDoesNotSendAChange() async throws {
        let (service, vpn, _, sessions) = make()
        try await service.startCapture()
        vpn.missingQueryReply = true
        let changes = vpn.messages
        do { try await service.startCapture(); XCTFail("Unknown query was ignored") }
        catch {
            XCTAssertEqual(service.recordingState, .unknown)
            XCTAssertEqual(vpn.messages, changes)
            XCTAssertEqual(sessions.began, 1)
        }
    }

    func testUnresolvedConnectionDoesNotCreateOrCloseASession() async {
        let (service, vpn, _, sessions) = make()
        sessions.currentID = UUID()
        vpn.transitioning = true
        do { try await service.startCapture(); XCTFail("Unresolved connection was accepted") }
        catch {
            XCTAssertEqual(service.recordingState, .unknown)
            XCTAssertEqual(sessions.began, 0)
            XCTAssertEqual(sessions.ended, 0)
            XCTAssertEqual(sessions.aborted, 0)
        }
    }

    func testFailedPreparationInvalidatesOldConfirmedState() async throws {
        let (service, vpn, _, _) = make()
        try await service.startCapture()
        vpn.failPrepare = true
        do { try await service.refreshRecordingState(); XCTFail("Preparation failure was hidden") }
        catch { XCTAssertEqual(service.recordingState, .unknown) }
    }

    func testUnconfirmedServiceShutdownIsNotReportedAsStopped() async throws {
        let (service, vpn, _, _) = make()
        try await service.startService()
        vpn.failStop = true
        do { try await service.stopService(); XCTFail("Shutdown failure was hidden") }
        catch {
            XCTAssertTrue(vpn.isConnected)
            XCTAssertEqual(service.recordingState, .unknown)
        }
    }

    func testConcurrentOppositeOperationFailsBusyRatherThanSilentlySucceeding() async throws {
        let (service, vpn, _, _) = make()
        let entered = expectation(description: "preparing")
        var release: CheckedContinuation<Void, Never>?
        vpn.prepareHook = {
            await withCheckedContinuation { continuation in
                release = continuation
                entered.fulfill()
            }
        }
        let pending = Task { try await service.startService() }
        await fulfillment(of: [entered], timeout: 2)
        do { try await service.stopCapture(); XCTFail("Concurrent operation silently succeeded") }
        catch NetworkCaptureService.ServiceError.busy { }
        catch { XCTFail("Expected busy, got \(error)") }
        release?.resume()
        try await pending.value
        XCTAssertTrue(vpn.isConnected)
        XCTAssertEqual(vpn.stops, 0)
    }
}
