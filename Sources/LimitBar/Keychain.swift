import Foundation

enum Keychain {
    /// Reads a generic password item by service name and returns its data as a UTF-8 string.
    ///
    /// We shell out to `/usr/bin/security` rather than calling `SecItemCopyMatching` in-process.
    /// Why: the "Claude Code-credentials" item is owned and continuously rewritten by Claude Code
    /// (every OAuth token refresh — daily, and on each launch). Each rewrite resets the item's ACL
    /// *partition list* to `apple-tool:` only, evicting any "Always Allow" grant we earned. An
    /// in-process read is gated by that partition list, so the OS re-prompts for the login password
    /// every day. Apple's `security` tool, however, is permanently allowed under the `apple-tool:`
    /// partition, so this read never prompts and survives Claude Code's refreshes.
    static func readGenericPassword(service: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = ["find-generic-password", "-w", "-s", service]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
