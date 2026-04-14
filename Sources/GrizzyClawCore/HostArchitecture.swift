import Foundation

/// Runtime host ABI for features that only exist on Apple silicon (e.g. bundled MLX).
public enum HostArchitecture {
    /// `true` when this process is built for arm64 (Apple silicon). Intel/Rosetta x86_64 builds return `false`.
    public static var isAppleSilicon: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }
}
