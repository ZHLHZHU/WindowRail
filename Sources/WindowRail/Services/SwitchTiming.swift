import Foundation
import OSLog

enum SwitchTiming {
    private static let enabled = CommandLine.arguments.contains("--switch-trace")
    private static let log = Logger(subsystem: "local.windowrail.app", category: "switchTrace")

    static func record(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let text = message()
        log.notice("\(text, privacy: .public)")
    }

    static func milliseconds(since timestamp: UInt64) -> UInt64 {
        let now = DispatchTime.now().uptimeNanoseconds
        return now >= timestamp ? (now - timestamp) / 1_000_000 : 0
    }
}
