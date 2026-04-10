import GrizzyClawUI
import SwiftUI

@main
enum SwiftRunEntry {
    static func main() {
        // Delegate to the shared SwiftUI app type (single entry for SPM executable).
        GrizzyClawRootApp.main()
    }
}
