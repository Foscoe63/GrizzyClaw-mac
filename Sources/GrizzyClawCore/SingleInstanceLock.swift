import Darwin
import Foundation

/// Advisory lock on `grizzyclaw-mac.lock` so concurrent instances are visible; we **do not** exit the app if the lock is busy
/// (that previously caused “build succeeds but no window” when another copy, or `swift run`, held the lock — Release builds
/// also lacked a reliable `DEBUG` flag for SPM dependencies from Xcode).
public enum SingleInstanceLock {
    private nonisolated(unsafe) static var lockFD: Int32 = -1

    /// Call once at startup (after the first window is up is best — avoids racing SwiftUI’s window server).
    /// If another instance holds the lock, prints a warning to stderr and continues without exiting.
    public static func acquireAdvisoryLock() {
        _ = try? GrizzyClawPaths.ensureUserDataDirectoryExists()
        let path = GrizzyClawPaths.userDataDirectory.appendingPathComponent("grizzyclaw-mac.lock").path
        let fd = open(path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { return }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            fputs(
                """
                GrizzyClaw: could not lock ~/.grizzyclaw/grizzyclaw-mac.lock (another instance may be running, or a stale lock will clear when that process exits).
                Continuing — close the other GrizzyClaw if you see session file conflicts.

                """,
                stderr
            )
            close(fd)
            return
        }
        lockFD = fd
    }
}
