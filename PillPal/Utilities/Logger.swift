import Foundation

enum Logger {
    static func info(_ message: String) {
#if DEBUG
        print("[PillPal] \(message)")
#endif
    }

    static func warning(_ message: String) {
#if DEBUG
        print("[PillPal][Warning] \(message)")
#endif
    }

    static func error(_ message: String) {
#if DEBUG
        print("[PillPal][Error] \(message)")
#endif
    }
}
