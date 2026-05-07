import Foundation

enum DateTimeUtils {
    static let calendar = Calendar.current
    static func startOfMonth(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()

    static let uiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let uiTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    static func parseDay(_ text: String) -> Date? {
        guard text != "unknown" else { return nil }
        return dayFormatter.date(from: text)
    }

    static func formatDay(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    static func parseTimeComponents(_ time: String) -> DateComponents? {
        let parts = time.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute)
        else {
            return nil
        }
        return DateComponents(hour: hour, minute: minute)
    }

    static func dateAndTime(day: Date, time: String) -> Date? {
        guard let timeComponents = parseTimeComponents(time) else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = 0
        return calendar.date(from: components)
    }

    static func formatDisplayDate(_ date: Date) -> String {
        uiDateFormatter.string(from: date)
    }

    static func formatDisplayTime(_ date: Date) -> String {
        uiTimeFormatter.string(from: date)
    }

    static func defaultTimes(for frequency: MedicationFrequency) -> [String] {
        switch frequency.type {
        case .timesPerDay:
            switch frequency.value {
            case 1: return ["08:00"]
            case 2: return ["08:00", "20:00"]
            case 3: return ["08:00", "13:00", "20:00"]
            case 4: return ["08:00", "12:00", "16:00", "20:00"]
            default: return []
            }
        case .specificTimes:
            return []
        case .intervalHours:
            return []
        case .unknown:
            return []
        }
    }

    static func defaultBedtime() -> String {
        "22:30"
    }

    static func defaultMorningNoonEvening() -> [String] {
        ["08:00", "13:00", "20:00"]
    }

    static func makeNotificationIdentifier(planId: UUID, medicationId: UUID, day: Date, time: String) -> String {
        "\(planId.uuidString)_\(medicationId.uuidString)_\(formatDay(day))_\(time.replacingOccurrences(of: ":", with: "-"))"
    }
}
