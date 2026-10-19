import Foundation

/// Copies bundled Osaurus `SKILL.md` trees from ``Bundle.module`` into ``GrizzyClawPaths/skillsDirectory``.
public enum OsaurusBundledSkillsInstaller {
    private static let markerFileName = ".osaurus_bundled_skills_revision"

    /// Idempotent: creates skills dir, upgrades bundled files when ``BuiltinOsaurusSkills.bundleRevision`` increases.
    public static func syncFromBundleIfNeeded() {
        do {
            try syncFromBundleIfNeededThrowing()
        } catch {
            GrizzyClawLog.error("Osaurus bundled skills sync failed: \(error.localizedDescription)")
        }
    }

    public static func syncFromBundleIfNeededThrowing() throws {
        let skillsRoot = try GrizzyClawPaths.ensureSkillsDirectoryExists()
        let markerURL = skillsRoot.appendingPathComponent(markerFileName, isDirectory: false)
        let current = (try? String(contentsOf: markerURL, encoding: .utf8))
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
        guard current < BuiltinOsaurusSkills.bundleRevision else { return }

        let fm = FileManager.default
        for def in BuiltinOsaurusSkills.all {
            guard
                let src = Bundle.module.url(
                    forResource: "SKILL",
                    withExtension: "md",
                    subdirectory: "BundledSkills/Osaurus/\(def.bundleFolderSlug)"
                )
            else {
                GrizzyClawLog.error(
                    "Missing bundled Osaurus skill resource: BundledSkills/Osaurus/\(def.bundleFolderSlug)/SKILL.md"
                )
                continue
            }
            let destDir = skillsRoot.appendingPathComponent(def.skillID, isDirectory: true)
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
            let destMd = destDir.appendingPathComponent("SKILL.md", isDirectory: false)
            if fm.fileExists(atPath: destMd.path) {
                try fm.removeItem(at: destMd)
            }
            try fm.copyItem(at: src, to: destMd)
        }

        try String(BuiltinOsaurusSkills.bundleRevision).write(to: markerURL, atomically: true, encoding: .utf8)
    }
}
