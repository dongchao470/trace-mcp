import Foundation
import XCTest
@testable import TraceServiceFixes

private actor RecordingQueryLatch {
    private var entered = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var release: CheckedContinuation<Void, Never>?

    func hold() async {
        entered = true
        let waiters = enteredWaiters
        enteredWaiters = []
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { release = $0 }
    }
    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }
    func open() { release?.resume(); release = nil }
}

final class RecordingQuerySnapshotRegressionTests: XCTestCase {
    func testIdleSnapshotIsImmediatelyAvailable() async {
        let queue = RecordingTransitionQueue()
        let value = await queue.readIfIdle { 42 }
        XCTAssertEqual(value, 42)
    }

    func testBusySnapshotDoesNotWaitForOrReadIntermediateRecordingState() async {
        let queue = RecordingTransitionQueue()
        let gate = CaptureRecordingState(enabled: false)
        let latch = RecordingQueryLatch()
        let transition = Task {
            await queue.perform {
                gate.setRecording(true)
                await latch.hold()
                gate.setRecording(false)
            }
        }
        await latch.waitUntilEntered()
        let started = Date()
        let snapshot = await queue.readIfIdle { gate.isRecording }
        XCTAssertNil(snapshot, "The intermediate true value must not be acknowledged")
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5,
                          "Read-only status must not queue behind reconfiguration")
        await latch.open()
        await transition.value
        let committed = await queue.readIfIdle { gate.isRecording }
        XCTAssertEqual(committed, false)
    }

    func testCancellationDoesNotExposeAStillRunningTransitionAsIdle() async {
        let queue = RecordingTransitionQueue()
        let latch = RecordingQueryLatch()
        let transition = Task { await queue.perform { await latch.hold() } }
        await latch.waitUntilEntered()
        transition.cancel()
        let snapshot = await queue.readIfIdle { "not committed" }
        XCTAssertNil(snapshot)
        await latch.open()
        await transition.value
        let completed = await queue.readIfIdle { "committed" }
        XCTAssertEqual(completed, "committed")
    }
}
