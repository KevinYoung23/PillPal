import SwiftUI

struct ConfirmCreateRemindersView: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.openURL) private var openURL

    let plan: MedicationPlan
    let originalScannedImages: [UIImage]
    let targetPlanId: UUID?
    var onBack: () -> Void
    var onFinish: () -> Void

    @State private var state: ScreenState = .ready
    @State private var addToSystemReminders = false
    @State private var addToCalendar = false

    enum ScreenState {
        case ready
        case scheduling
        case finished(ResultSummary)
        case failed(String)
    }

    struct ResultSummary {
        let notificationCount: Int
        let remindersCount: Int
        let calendarCount: Int
        let warnings: [String]
        let notificationsDenied: Bool

        var totalCreated: Int {
            notificationCount + remindersCount + calendarCount
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "bell.badge")
                .font(.system(size: 42))
                .foregroundStyle(.tint)

            Text("Create Reminders")
                .font(.title2.weight(.semibold))

            Text("Create in-app notifications, and optionally also add to Apple Reminders or Calendar.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            summaryCard
            destinationOptionsCard

            switch state {
            case .ready:
                EmptyView()
            case .scheduling:
                ProgressView("Preparing reminders...")
            case .finished(let summary):
                resultView(summary)
            case .failed(let message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 10) {
                if case .finished = state {
                    Button("Done", action: onFinish)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Back", action: onBack)
                        .buttonStyle(.bordered)

                    Button {
                        Task { await createReminders() }
                    } label: {
                        Text("Confirm & Create")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isScheduling)
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .padding(20)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plan Summary")
                .font(.headline)
            Text("Destination: \(destinationSummary)")
            Text("Medications: \(plan.medications.count)")
            Text("Follow-ups: \(plan.followUp.count)")
            Text("Uncertainties flagged: \(plan.uncertainties.count)")
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var destinationOptionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Also Add To (Optional)")
                .font(.headline)

            Toggle("Apple Reminders", isOn: $addToSystemReminders)
            Toggle("Calendar", isOn: $addToCalendar)

            Text("You can choose where to add reminders. Permissions are requested only for selected destinations.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func resultView(_ summary: ResultSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if summary.totalCreated > 0 {
                Text("Created successfully")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Text("Plan saved locally")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            Text("In-app notifications: \(summary.notificationCount)")
            Text("Apple Reminders: \(summary.remindersCount)")
            Text("Calendar events: \(summary.calendarCount)")

            ForEach(summary.warnings, id: \.self) { warning in
                Text("• \(warning)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if summary.notificationsDenied {
                Button("Open Settings") {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        openURL(settingsURL)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var isScheduling: Bool {
        if case .scheduling = state {
            return true
        }
        return false
    }

    private func createReminders() async {
        state = .scheduling

        var warnings: [String] = []
        var notificationCount = 0
        var remindersCount = 0
        var calendarCount = 0
        var preparedPlan = plan
        if preparedPlan.storedInstructionImagePaths.isEmpty, !originalScannedImages.isEmpty {
            preparedPlan.sourceInstructionImagePaths = PlanImageStoreService.shared.store(
                images: originalScannedImages,
                planId: preparedPlan.id
            )
        }

        var targetPlan = preparedPlan
        var isUpdatingExistingPlan = false

        if let targetPlanId,
           let existingPlan = appStore.plan(by: targetPlanId) {
            targetPlan = merge(existing: existingPlan, with: preparedPlan)
            isUpdatingExistingPlan = true
        } else if targetPlanId != nil {
            warnings.append("Selected plan was unavailable. Created as a new plan instead.")
        }

        let notificationsGranted = await NotificationService.shared.requestAuthorization()
        if notificationsGranted {
            if isUpdatingExistingPlan {
                NotificationService.shared.cancelNotifications(for: targetPlan.id)
            }
            do {
                notificationCount = try await NotificationService.shared.scheduleNotifications(for: targetPlan)
            } catch {
                warnings.append("In-app notifications could not be scheduled.")
                Logger.error("Failed to schedule in-app notifications.")
            }
        } else {
            warnings.append("Notifications permission was denied.")
        }

        if addToSystemReminders {
            let remindersGranted = await SystemIntegrationService.shared.requestRemindersAccess()
            if remindersGranted {
                do {
                    remindersCount = try SystemIntegrationService.shared.createReminders(for: targetPlan)
                } catch {
                    warnings.append("Could not add items to Apple Reminders.")
                    Logger.error("Failed to create Apple Reminders items.")
                }
            } else {
                warnings.append("Apple Reminders permission was denied.")
            }
        }

        if addToCalendar {
            let calendarGranted = await SystemIntegrationService.shared.requestCalendarAccess()
            if calendarGranted {
                do {
                    calendarCount = try SystemIntegrationService.shared.createCalendarEvents(for: targetPlan)
                } catch {
                    warnings.append("Could not add events to Calendar.")
                    Logger.error("Failed to create Calendar events.")
                }
            } else {
                warnings.append("Calendar permission was denied.")
            }
        }

        if isUpdatingExistingPlan {
            let didUpdate = appStore.updatePlan(targetPlan)
            if !didUpdate {
                appStore.addPlan(plan)
                warnings.append("Existing plan update failed. Created as a new plan instead.")
            }
        } else {
            appStore.addPlan(targetPlan)
        }

        let result = ResultSummary(
            notificationCount: notificationCount,
            remindersCount: remindersCount,
            calendarCount: calendarCount,
            warnings: warnings,
            notificationsDenied: !notificationsGranted
        )
        state = .finished(result)
    }

    private var destinationSummary: String {
        if let targetPlanId,
           let existingPlan = appStore.plan(by: targetPlanId) {
            return "Existing plan (\(DateTimeUtils.formatDisplayDate(existingPlan.createdAt)))"
        }
        return "New plan"
    }

    private func merge(existing: MedicationPlan, with appended: MedicationPlan) -> MedicationPlan {
        var merged = existing
        merged.medications.append(contentsOf: appended.medications)
        merged.followUp = mergeFollowUps(primary: existing.followUp, secondary: appended.followUp)
        merged.uncertainties = mergeUncertainties(primary: existing.uncertainties, secondary: appended.uncertainties)
        merged.sourceInstructionImagePaths = Array(
            Set(existing.storedInstructionImagePaths + appended.storedInstructionImagePaths)
        )
        .sorted()

        let trimmedSource = appended.sourceOCRText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSource.isEmpty {
            if merged.sourceOCRText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                merged.sourceOCRText = trimmedSource
            } else {
                merged.sourceOCRText += "\n\n[Appended Prescription]\n\(trimmedSource)"
            }
        }
        return merged
    }

    private func mergeFollowUps(primary: [FollowUpItem], secondary: [FollowUpItem]) -> [FollowUpItem] {
        var seen = Set<String>()
        var merged: [FollowUpItem] = []

        for item in primary + secondary {
            let key = "\(DateTimeUtils.formatDay(item.date))|\(item.notes.lowercased())"
            if seen.insert(key).inserted {
                merged.append(item)
            }
        }

        return merged.sorted { $0.date < $1.date }
    }

    private func mergeUncertainties(
        primary: [ExtractionUncertainty],
        secondary: [ExtractionUncertainty]
    ) -> [ExtractionUncertainty] {
        var seen = Set<String>()
        var merged: [ExtractionUncertainty] = []

        for item in primary + secondary {
            let key = "\(item.path)|\(item.reason)"
            if seen.insert(key).inserted {
                merged.append(item)
            }
        }
        return merged
    }
}
