import SwiftUI

struct MedicationsListView: View {
    @EnvironmentObject private var appStore: AppStore

    var body: some View {
        List {
            if appStore.plans.isEmpty {
                ContentUnavailableView(
                    "No plans yet",
                    systemImage: "pills",
                    description: Text("Create a plan to see medications here.")
                )
            } else {
                ForEach(appStore.plans) { plan in
                    Section(DateTimeUtils.formatDisplayDate(plan.createdAt)) {
                        ForEach(plan.medications) { medication in
                            NavigationLink {
                                MedicationInstructionView(
                                    medication: medication,
                                    planCreatedAt: plan.createdAt
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(medication.name)
                                        .font(.headline)
                                    Text("\(medication.dose) • \(medication.route.displayName)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text("Times: \(medication.times.joined(separator: ", "))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        }
        .dockSafeContentInset()
        .navigationTitle("Medications")
    }
}

private struct MedicationInstructionView: View {
    let medication: MedicationItem
    let planCreatedAt: Date

    private var notesText: String {
        let filtered = medication.notes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return filtered.isEmpty ? "No additional notes." : filtered.joined(separator: "\n")
    }

    private var storageText: String {
        let filtered = medication.storage.filter { $0 != .unknown }
        return filtered.isEmpty ? "No specific storage requirements." : filtered.map(\.displayName).joined(separator: ", ")
    }

    private var frequencyText: String {
        switch medication.frequency.type {
        case .timesPerDay:
            return "\(medication.frequency.value)x/day"
        case .intervalHours:
            return "Every \(medication.frequency.value) hour(s)"
        case .specificTimes:
            return "Specific times"
        case .unknown:
            return "Unknown"
        }
    }

    var body: some View {
        List {
            Section("Medication") {
                infoRow(title: "Name", value: medication.name)
                infoRow(title: "Dose", value: medication.dose)
                infoRow(title: "Route", value: medication.route.displayName)
                infoRow(title: "Frequency", value: frequencyText)
                infoRow(title: "Time(s)", value: medication.times.joined(separator: ", "))
            }

            Section("Course") {
                infoRow(title: "Start", value: DateTimeUtils.formatDisplayDate(medication.startDate))
                infoRow(title: "End", value: DateTimeUtils.formatDisplayDate(medication.endDate))
                infoRow(title: "Plan Created", value: DateTimeUtils.formatDisplayDate(planCreatedAt))
            }

            Section("Instructions") {
                infoRow(title: "Food Timing", value: medication.withFood.displayName)
                infoRow(title: "Storage", value: storageText)
                Text(notesText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
            }
        }
        .dockSafeContentInset()
        .navigationTitle(medication.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func infoRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 2)
    }
}
