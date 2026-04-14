import Foundation
import GrizzyClawCore

/// Appends enabled ClawHub skills to the system prompt so the model can use workspace capabilities as routing hints.
public enum SkillPromptAugmentor {
    public static func skillsSuffix(enabledSkillIDs: [String]) -> String {
        let normalized = deduplicatedSkillIDs(enabledSkillIDs)
        guard !normalized.isEmpty else { return "" }

        let builtinByID = Dictionary(
            uniqueKeysWithValues: BuiltinClawHubSkills.all.map { ($0.id.lowercased(), $0) }
        )

        var lines: [String] = []
        lines.append("## Enabled ClawHub skills")
        lines.append(
            "These are workspace-level capabilities and preferences. Use them as guidance for tool choice, planning, and behavior."
        )

        for id in normalized {
            if let builtin = builtinByID[id.lowercased()] {
                lines.append("- \(builtin.id): \(builtin.name) — \(builtin.description)")
                if builtin.id.lowercased() == "scheduler" {
                    lines.append(
                        "  When the user asks for reminders or recurring jobs, prefer grizzyclaw.create_scheduled_task instead of generating standalone code or calendar events."
                    )
                    lines.append(
                        "  Scheduler is for background recurring tasks and reminders, not calendar events."
                    )
                }
                if builtin.id.lowercased() == "calendar" {
                    lines.append(
                        "  Calendar is for user calendar events and scheduling on a calendar, not background scheduler jobs."
                    )
                }
            } else {
                lines.append("- \(id): Custom installed skill enabled for this workspace.")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func deduplicatedSkillIDs(_ enabledSkillIDs: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in enabledSkillIDs {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            out.append(trimmed)
        }
        return out
    }
}
