import Foundation
import UserNotifications

final class NotificationService {
    static let shared = NotificationService()

    static let categoryId = "PILLPAL_MEDICATION"
    static let actionTaken = "PILLPAL_ACTION_TAKEN"
    static let actionSnooze = "PILLPAL_ACTION_SNOOZE_10"

    private let center: UNUserNotificationCenter

    private init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func registerCategories() {
        let taken = UNNotificationAction(
            identifier: Self.actionTaken,
            title: "Taken",
            options: [.foreground]
        )
        let snooze = UNNotificationAction(
            identifier: Self.actionSnooze,
            title: "Snooze 10 min",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryId,
            actions: [taken, snooze],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            Logger.error("Notification authorization request failed.")
            return false
        }
    }

    func notificationsEnabled() async -> Bool {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                let enabled: Bool
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    enabled = true
                case .denied, .notDetermined:
                    enabled = false
                @unknown default:
                    enabled = false
                }
                continuation.resume(returning: enabled)
            }
        }
    }

    func scheduleNotifications(for plan: MedicationPlan) async throws -> Int {
        var count = 0

        for medication in plan.medications {
            var day = Calendar.current.startOfDay(for: medication.startDate)
            let endDay = Calendar.current.startOfDay(for: medication.endDate)

            while day <= endDay {
                for time in medication.times {
                    guard let components = DateTimeUtils.parseTimeComponents(time) else { continue }
                    let identifier = DateTimeUtils.makeNotificationIdentifier(
                        planId: plan.id,
                        medicationId: medication.id,
                        day: day,
                        time: time
                    )

                    var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: day)
                    dateComponents.hour = components.hour
                    dateComponents.minute = components.minute

                    let content = UNMutableNotificationContent()
                    content.title = "Time to take: \(medication.name)"
                    content.body = makeBody(for: medication)
                    content.sound = .default
                    content.categoryIdentifier = Self.categoryId
                    content.userInfo = [
                        "doseId": identifier,
                        "planId": plan.id.uuidString,
                        "medicationId": medication.id.uuidString,
                        "time": time,
                        "day": DateTimeUtils.formatDay(day)
                    ]

                    let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
                    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                    try await add(request)
                    count += 1
                }

                guard let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day) else {
                    break
                }
                day = nextDay
            }
        }

        return count
    }

    func cancelNotifications(for planId: UUID) {
        center.getPendingNotificationRequests { requests in
            let ids = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(planId.uuidString) }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)
        }

        center.getDeliveredNotifications { notifications in
            let ids = notifications
                .map(\.request.identifier)
                .filter { $0.hasPrefix(planId.uuidString) }
            self.center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    func cancelNotification(withIdentifier identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func scheduleSingleNotification(
        planId: UUID,
        medication: MedicationItem,
        day: Date,
        time: String,
        identifier: String,
        overrideDose: String?
    ) async throws {
        guard let components = DateTimeUtils.parseTimeComponents(time) else {
            return
        }

        var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: day)
        dateComponents.hour = components.hour
        dateComponents.minute = components.minute

        var reminderMedication = medication
        if let overrideDose {
            reminderMedication.dose = overrideDose
        }

        let content = UNMutableNotificationContent()
        content.title = "Time to take: \(reminderMedication.name)"
        content.body = makeBody(for: reminderMedication)
        content.sound = .default
        content.categoryIdentifier = Self.categoryId
        content.userInfo = [
            "doseId": identifier,
            "planId": planId.uuidString,
            "medicationId": medication.id.uuidString,
            "time": time,
            "day": DateTimeUtils.formatDay(day)
        ]

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await add(request)
    }

    func handleAction(
        response: UNNotificationResponse,
        appStore: AppStore
    ) async {
        let doseId = (response.notification.request.content.userInfo["doseId"] as? String) ?? response.notification.request.identifier

        switch response.actionIdentifier {
        case Self.actionTaken:
            await MainActor.run {
                appStore.markDoseTaken(doseId)
            }
        case Self.actionSnooze:
            await scheduleSnooze(from: response.notification.request)
        default:
            break
        }
    }

    private func scheduleSnooze(from original: UNNotificationRequest) async {
        let content = original.content.mutableCopy() as? UNMutableNotificationContent ?? UNMutableNotificationContent()
        content.sound = .default
        let snoozeId = "\(original.identifier)_snooze_\(Int(Date().timeIntervalSince1970))"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false)
        let request = UNNotificationRequest(identifier: snoozeId, content: content, trigger: trigger)
        do {
            try await add(request)
        } catch {
            Logger.error("Failed to schedule snoozed reminder.")
        }
    }

    private func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func makeBody(for medication: MedicationItem) -> String {
        var parts: [String] = []
        parts.append("Dose: \(medication.dose)")
        parts.append("Route: \(medication.route.displayName)")

        switch medication.withFood {
        case .beforeMeal:
            parts.append("Food: before meal (-15m strategy)")
        case .afterMeal:
            parts.append("Food: after meal (+30m strategy)")
        case .withMeal:
            parts.append("Food: with meal")
        case .noRequirement:
            parts.append("Food: no requirement")
        case .unknown:
            break
        }

        let storage = medication.storage
            .filter { $0 != .unknown }
            .map(\.displayName)
        if !storage.isEmpty {
            parts.append("Storage: \(storage.joined(separator: ", "))")
        }

        if let note = medication.notes.first, !note.isEmpty {
            let truncated = note.count > 80 ? String(note.prefix(80)) + "..." : note
            parts.append("Note: \(truncated)")
        }

        return parts.joined(separator: " • ")
    }
}
