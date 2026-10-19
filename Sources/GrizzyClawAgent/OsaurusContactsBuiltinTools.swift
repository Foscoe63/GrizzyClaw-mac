import Contacts
import Foundation
import GrizzyClawCore

enum OsaurusContactsBuiltinTools {
    static func result(tool: String, arguments: [String: Any]) async -> String {
        let composite = "osaurus.contacts.\(tool)"
        let store = CNContactStore()
        do {
            let granted = try await store.requestAccess(for: .contacts)
            guard granted else {
                return ToolEnvelope.failure(
                    tool: composite,
                    kind: "permission_denied",
                    message: "Contacts access was denied for Grizzy.",
                    retryable: false
                )
            }
        } catch {
            return ToolEnvelope.fromError(error, tool: composite)
        }
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor,
        ]
        switch tool {
        case "find_contact_by_name":
            let q =
                OsaurusBuiltinToolArguments.string(from: arguments, keys: ["query", "name", "q"])
                ?? ""
            guard !q.isEmpty else {
                return ToolEnvelope.failure(
                    tool: composite,
                    kind: "invalid_args",
                    message: "Pass `name` or `query`.",
                    field: "query"
                )
            }
            let pred = CNContact.predicateForContacts(matchingName: q)
            return fetchContacts(
                store: store, predicate: pred, keys: keys, composite: composite, label: "matches")
        case "find_contact_by_phone", "find_number":
            let digits = normalizedPhone(
                OsaurusBuiltinToolArguments.string(from: arguments, keys: ["phone", "number", "q"])
                    ?? "")
            guard digits.count >= 7 else {
                return ToolEnvelope.failure(
                    tool: composite,
                    kind: "invalid_args",
                    message: "Pass a `phone` number to search.",
                    field: "phone"
                )
            }
            let pred = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: digits))
            return fetchContacts(
                store: store, predicate: pred, keys: keys, composite: composite, label: "matches")
        case "get_all_numbers":
            return allNumbers(store: store, keys: keys, composite: composite)
        default:
            return ToolEnvelope.failure(
                tool: composite,
                kind: "unknown_tool",
                message: "Unknown osaurus.contacts tool `\(tool)`."
            )
        }
    }

    private static func fetchContacts(
        store: CNContactStore,
        predicate: NSPredicate,
        keys: [CNKeyDescriptor],
        composite: String,
        label: String,
        limit: Int = 40
    ) -> String {
        do {
            let fetched = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
            let slice = Array(fetched.prefix(limit))
            let rows: [[String: Any]] = slice.map { c in
                let phones = c.phoneNumbers.map { $0.value.stringValue }
                let emails = c.emailAddresses.map { $0.value as String }
                return [
                    "id": c.identifier,
                    "given_name": c.givenName,
                    "family_name": c.familyName,
                    "phones": phones,
                    "emails": emails,
                ]
            }
            return ToolEnvelope.success(tool: composite, result: [label: rows, "count": rows.count])
        } catch {
            return ToolEnvelope.fromError(error, tool: composite)
        }
    }

    private static func allNumbers(
        store: CNContactStore,
        keys: [CNKeyDescriptor],
        composite: String
    ) -> String {
        do {
            let containers = try store.containers(matching: nil)
            guard !containers.isEmpty else {
                return ToolEnvelope.failure(
                    tool: composite,
                    kind: "empty_store",
                    message: "No contact containers available.",
                    retryable: false
                )
            }
            let pred = NSCompoundPredicate(
                orPredicateWithSubpredicates:
                    containers.map { CNContact.predicateForContactsInContainer(withIdentifier: $0.identifier) }
            )
            let fetched = try store.unifiedContacts(matching: pred, keysToFetch: keys)
            var rows: [[String: Any]] = []
            for c in fetched.prefix(250) {
                for p in c.phoneNumbers {
                    rows.append([
                        "contact_id": c.identifier,
                        "name": "\(c.givenName) \(c.familyName)".trimmingCharacters(in: .whitespaces),
                        "phone": p.value.stringValue,
                        "label": p.label ?? "",
                    ])
                }
            }
            return ToolEnvelope.success(
                tool: composite, result: ["numbers": rows, "count": rows.count])
        } catch {
            return ToolEnvelope.fromError(error, tool: composite)
        }
    }

    private static func normalizedPhone(_ raw: String) -> String {
        raw.filter(\.isNumber)
    }
}
