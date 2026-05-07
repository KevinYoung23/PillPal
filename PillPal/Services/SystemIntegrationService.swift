import EventKit
import Foundation

final class SystemIntegrationService {
    static let shared = SystemIntegrationService()

    private let eventStore = EKEventStore()

    private init() {}

    func requestRemindersAccess() async -> Bool {
        do {
            return try await eventStore.requestFullAccessToReminders()
        } catch {
            Logger.error("Reminders authorization request failed.")
            return false
        }
    }

    func requestCalendarAccess() async -> Bool {
        do {
            return try await eventStore.requestFullAccessToEvents()
        } catch {
            Logger.error("Calendar authorization request failed.")
            return false
        }
    }

    func createReminders(for plan: MedicationPlan) throws -> Int {
        guard let list = eventStore.defaultCalendarForNewReminders() else {
            throw NSError(domain: "SystemIntegrationService", code: 3001, userInfo: [NSLocalizedDescriptionKey: "No default reminders list available."])
        }

        var count = 0

        for medication in plan.medications {
            var day = Calendar.current.startOfDay(for: medication.startDate)
            let endDay = Calendar.current.startOfDay(for: medication.endDate)

            while day <= endDay {
                for time in medication.times {
                    guard let dueDate = DateTimeUtils.dateAndTime(day: day, time: time) else { continue }

                    let reminder = EKReminder(eventStore: eventStore)
                    reminder.calendar = list
                    reminder.title = "Take: \(medication.name)"
                    reminder.notes = reminderNotes(for: medication)
                    reminder.dueDateComponents = Calendar.current.dateComponents(
                        in: .current,
                        from: dueDate
                    )

                    try eventStore.save(reminder, commit: false)
                    count += 1
                }

                guard let next = Calendar.current.date(byAdding: .day, value: 1, to: day) else {
                    break
                }
                day = next
            }
        }

        if count > 0 {
            try eventStore.commit()
        }

        return count
    }

    func createCalendarEvents(for plan: MedicationPlan) throws -> Int {
        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            throw NSError(domain: "SystemIntegrationService", code: 3002, userInfo: [NSLocalizedDescriptionKey: "No default calendar available."])
        }

        var count = 0

        for medication in plan.medications {
            var day = Calendar.current.startOfDay(for: medication.startDate)
            let endDay = Calendar.current.startOfDay(for: medication.endDate)

            while day <= endDay {
                for time in medication.times {
                    guard let startDate = DateTimeUtils.dateAndTime(day: day, time: time),
                          let endDate = Calendar.current.date(byAdding: .minute, value: 10, to: startDate)
                    else {
                        continue
                    }

                    let event = EKEvent(eventStore: eventStore)
                    event.calendar = calendar
                    event.title = "Medication: \(medication.name)"
                    event.startDate = startDate
                    event.endDate = endDate
                    event.notes = reminderNotes(for: medication)
                    event.isAllDay = false

                    try eventStore.save(event, span: .thisEvent, commit: false)
                    count += 1
                }

                guard let next = Calendar.current.date(byAdding: .day, value: 1, to: day) else {
                    break
                }
                day = next
            }
        }

        if count > 0 {
            try eventStore.commit()
        }

        return count
    }

    private func reminderNotes(for medication: MedicationItem) -> String {
        var parts: [String] = [
            "Dose: \(medication.dose)",
            "Route: \(medication.route.displayName)"
        ]

        if medication.withFood != .unknown {
            parts.append("Food: \(medication.withFood.displayName)")
        }

        let storage = medication.storage
            .filter { $0 != .unknown }
            .map(\.displayName)
        if !storage.isEmpty {
            parts.append("Storage: \(storage.joined(separator: ", "))")
        }

        if !medication.notes.isEmpty {
            parts.append("Notes: \(medication.notes.joined(separator: "; "))")
        }

        return parts.joined(separator: " • ")
    }
}
