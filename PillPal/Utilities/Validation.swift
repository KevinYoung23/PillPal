import Foundation

enum Validation {
    static func isValidTimeString(_ value: String) -> Bool {
        DateTimeUtils.parseTimeComponents(value) != nil
    }

    static func areCourseDatesValid(start: Date?, end: Date?) -> Bool {
        guard let start, let end else { return false }
        return end >= start
    }

    static func hasValidTimes(_ times: [String]) -> Bool {
        !times.isEmpty && times.allSatisfy { isValidTimeString($0) }
    }
}
