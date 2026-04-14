import Foundation

/// Races an async operation against a wall-clock timeout without using `withThrowingTaskGroup`,
/// which can block until **both** child tasks finish — problematic when one path ignores cancellation
/// (e.g. `Process.waitUntilExit()` in a detached task).
public enum GrizzyAsyncTimeout {
    /// Runs `operation` and completes with its result, or throws `timeoutError` after `seconds`,
    /// cancelling the operation task. Does not wait for the operation to finish after timeout.
    public static func run<T: Sendable>(
        seconds: TimeInterval,
        timeoutError: Error,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let gate = ContinuationGate()
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
            let pair = WorkTimerPair()
            // Timer first so `pair.work` is always visible when the timeout fires.
            pair.timer = Task {
                do {
                    try await Task.sleep(nanoseconds: UInt64(max(0.05, seconds) * 1_000_000_000))
                } catch {
                    return
                }
                pair.work?.cancel()
                gate.resume(continuation: cont, result: .failure(timeoutError))
            }
            pair.work = Task {
                do {
                    let v = try await operation()
                    pair.timer?.cancel()
                    gate.resume(continuation: cont, result: .success(v))
                } catch is CancellationError {
                    // Timeout path usually resumes first; avoid double-resume.
                } catch {
                    pair.timer?.cancel()
                    gate.resume(continuation: cont, result: .failure(error))
                }
            }
        }
    }
}

private final class ContinuationGate: @unchecked Sendable {
    private var hasResumed = false
    private let lock = NSLock()

    /// `nonisolated` so success/failure values are not treated as task-isolated when resuming.
    nonisolated func resume<T: Sendable>(continuation: CheckedContinuation<T, Error>, result: Result<T, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return }
        hasResumed = true
        switch result {
        case .success(let v):
            continuation.resume(returning: v)
        case .failure(let e):
            continuation.resume(throwing: e)
        }
    }
}

private final class WorkTimerPair: @unchecked Sendable {
    var work: Task<Void, Never>?
    var timer: Task<Void, Never>?
}
