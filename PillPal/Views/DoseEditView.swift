import SwiftUI

enum DoseEditScope: String, CaseIterable, Identifiable {
    case thisArrangementOnly = "this_only"
    case allFutureArrangements = "future"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .thisArrangementOnly:
            return "This Only"
        case .allFutureArrangements:
            return "All Future"
        }
    }
}

struct DoseEditPayload {
    var doseText: String
    var timeText: String
    var scope: DoseEditScope
}

struct DoseEditView: View {
    let dose: TodayDose
    var onCancel: () -> Void
    var onSave: (DoseEditPayload) -> Void

    @State private var doseText: String
    @State private var selectedTime: Date
    @State private var scope: DoseEditScope = .thisArrangementOnly

    init(
        dose: TodayDose,
        onCancel: @escaping () -> Void,
        onSave: @escaping (DoseEditPayload) -> Void
    ) {
        self.dose = dose
        self.onCancel = onCancel
        self.onSave = onSave
        _doseText = State(initialValue: dose.dose)
        _selectedTime = State(initialValue: DateTimeUtils.dateAndTime(day: dose.date, time: dose.timeText) ?? dose.date)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Dose") {
                    TextField("Dose", text: $doseText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Reminder Time") {
                    DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                }

                Section("Apply Change") {
                    Picker("Scope", selection: $scope) {
                        ForEach(DoseEditScope.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Text("Medication: \(dose.medicationName)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(
                            DoseEditPayload(
                                doseText: doseText.trimmingCharacters(in: .whitespacesAndNewlines),
                                timeText: DateTimeUtils.timeFormatter.string(from: selectedTime),
                                scope: scope
                            )
                        )
                    }
                    .disabled(doseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
