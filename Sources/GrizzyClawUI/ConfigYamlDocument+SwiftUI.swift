import GrizzyClawCore
import SwiftUI

@MainActor
extension ConfigYamlDocument {
    func bindingString(_ key: String, default d: String = "") -> Binding<String> {
        Binding(
            get: { self.string(key, default: d) },
            set: { self.set(key, value: $0) }
        )
    }

    func bindingOptionalStringNull(_ key: String) -> Binding<String> {
        Binding(
            get: { self.optionalString(key) },
            set: { self.setOptionalString(key, $0) }
        )
    }

    func bindingInt(_ key: String, default d: Int) -> Binding<Int> {
        Binding(
            get: { self.int(key, default: d) },
            set: { self.set(key, value: $0) }
        )
    }

    func bindingBool(_ key: String, default d: Bool) -> Binding<Bool> {
        Binding(
            get: { self.bool(key, default: d) },
            set: { self.set(key, value: $0) }
        )
    }

    func bindingDouble(_ key: String, default d: Double) -> Binding<Double> {
        Binding(
            get: { self.double(key, default: d) },
            set: { self.set(key, value: $0) }
        )
    }

    func bindingStringArray(_ key: String) -> Binding<[String]> {
        Binding(
            get: { self.stringArray(key) },
            set: { self.setStringArray(key, $0) }
        )
    }
}
