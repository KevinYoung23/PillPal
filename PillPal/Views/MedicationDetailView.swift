import SwiftUI

struct MedicationDetailView: View {
    @EnvironmentObject private var appStore: AppStore

    let planId: UUID

    @State private var isEditing = false
    @State private var draft: EditablePlanDraft?
    @State private var errorMessage: String?
    @State private var showingInstructionImages = false

    private var plan: MedicationPlan? {
        appStore.plan(by: planId)
    }

    var body: some View {
        Group {
            if let plan {
                Form {
                    Section("Plan") {
                        Text("Created: \(DateTimeUtils.formatDisplayDate(plan.createdAt))")
                        Text("Medications: \(plan.medications.count)")
                        Text("Follow-ups: \(plan.followUp.count)")
                    }

                    if !plan.storedInstructionImagePaths.isEmpty {
                        Section("Original Instructions") {
                            Button {
                                showingInstructionImages = true
                            } label: {
                                HStack {
                                    Label("View Doctor Instruction Images", systemImage: "doc.viewfinder")
                                    Spacer()
                                    Text("\(plan.storedInstructionImagePaths.count)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if isEditing {
                        editableMedicationSection
                        editableFollowUpSection
                    } else {
                        readOnlyMedicationSection(plan: plan)
                        readOnlyFollowUpSection(plan: plan)
                    }
                }
                .dockSafeContentInset()
                .sheet(isPresented: $showingInstructionImages) {
                    InstructionImagesViewer(
                        title: "Original Instructions",
                        imagePaths: plan.storedInstructionImagePaths
                    )
                }
            } else {
                ContentUnavailableView(
                    "Plan Not Found",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This plan may have been deleted.")
                )
                .padding()
            }
        }
        .navigationTitle("My Plan")
        .toolbar {
            if plan != nil {
                if isEditing {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            isEditing = false
                            syncDraftFromCurrentPlan()
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") {
                            saveEdits()
                        }
                        .disabled(!(draft?.isValid ?? false))
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Edit") {
                            syncDraftFromCurrentPlan()
                            isEditing = true
                        }
                    }
                }
            }
        }
        .onAppear {
            syncDraftFromCurrentPlan()
        }
        .alert(
            "Could Not Save Plan",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func readOnlyMedicationSection(plan: MedicationPlan) -> some View {
        Section("Medications") {
            ForEach(plan.medications) { med in
                VStack(alignment: .leading, spacing: 4) {
                    Text(med.name)
                        .font(.headline)
                    Text("\(med.dose) • \(med.route.displayName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Times: \(med.times.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Course: \(DateTimeUtils.formatDisplayDate(med.startDate)) → \(DateTimeUtils.formatDisplayDate(med.endDate))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func readOnlyFollowUpSection(plan: MedicationPlan) -> some View {
        Section("Follow-up") {
            if plan.followUp.isEmpty {
                Text("No follow-up yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(plan.followUp) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(DateTimeUtils.formatDisplayDate(item.date))
                            .font(.subheadline.weight(.medium))
                        Text(item.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var editableMedicationSection: some View {
        Section("Edit Medications") {
            let meds = draft?.medications ?? []
            ForEach(Array(meds.enumerated()), id: \.element.id) { offset, medication in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Medication \(offset + 1)")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button(role: .destructive) {
                            removeMedication(at: offset)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }

                    TextField("Name", text: medicationBinding(offset, keyPath: \.name, default: ""))
                    TextField("Dose", text: medicationBinding(offset, keyPath: \.dose, default: ""))

                    Picker("Route", selection: medicationBinding(offset, keyPath: \.route, default: .unknown)) {
                        ForEach(MedicationRoute.allCases, id: \.self) { route in
                            Text(route.displayName).tag(route)
                        }
                    }
                    .pickerStyle(.menu)

                    TextField("Times (HH:mm, comma separated)", text: medicationBinding(offset, keyPath: \.timesText, default: "08:00"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    DatePicker("Start", selection: medicationBinding(offset, keyPath: \.startDate, default: Date()), displayedComponents: .date)
                    DatePicker("End", selection: medicationBinding(offset, keyPath: \.endDate, default: Date()), displayedComponents: .date)

                    Picker("Food timing", selection: medicationBinding(offset, keyPath: \.withFood, default: .noRequirement)) {
                        ForEach(FoodTiming.allCases, id: \.self) { timing in
                            Text(timing.displayName).tag(timing)
                        }
                    }
                    .pickerStyle(.menu)

                    TextField("Notes (; separated)", text: medicationBinding(offset, keyPath: \.notesText, default: ""))

                    Menu {
                        ForEach(StorageRequirement.allCases.filter { $0 != .unknown }, id: \.self) { requirement in
                            Button {
                                toggleStorage(requirement, forMedicationAt: offset)
                            } label: {
                                Label(
                                    requirement.displayName,
                                    systemImage: (draft?.medications[safe: offset]?.storage.contains(requirement) ?? false)
                                    ? "checkmark.circle.fill"
                                    : "circle"
                                )
                            }
                        }
                    } label: {
                        HStack {
                            Text("Storage")
                            Spacer()
                            Text(storageSummary(forMedicationAt: offset))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let med = draft?.medications[safe: offset], !med.hasValidTimes {
                        Text("Use valid HH:mm times separated by commas.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if let med = draft?.medications[safe: offset], med.endDate < med.startDate {
                        Text("End date must be on or after start date.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 4)
            }

            Button {
                addMedication()
            } label: {
                Label("Add Medication", systemImage: "plus.circle.fill")
            }
        }
    }

    private var editableFollowUpSection: some View {
        Section("Edit Follow-up") {
            let followUps = draft?.followUps ?? []
            ForEach(Array(followUps.enumerated()), id: \.element.id) { offset, _ in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Follow-up \(offset + 1)")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button(role: .destructive) {
                            removeFollowUp(at: offset)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }

                    DatePicker(
                        "Date",
                        selection: followUpBinding(offset, keyPath: \.date, default: Date()),
                        displayedComponents: .date
                    )

                    TextField("Notes", text: followUpBinding(offset, keyPath: \.notes, default: ""))
                }
                .padding(.vertical, 4)
            }

            Button {
                addFollowUp()
            } label: {
                Label("Add Follow-up", systemImage: "plus.circle.fill")
            }
        }
    }

    private func syncDraftFromCurrentPlan() {
        guard let plan else { return }
        draft = EditablePlanDraft(plan: plan)
    }

    private func saveEdits() {
        guard let draft else { return }
        guard let updatedPlan = draft.buildPlan() else {
            errorMessage = "Complete medication name, dose, times, and valid course dates before saving."
            return
        }

        let didUpdate = appStore.updatePlan(updatedPlan)
        guard didUpdate else {
            errorMessage = "This plan no longer exists. Please return and try again."
            return
        }

        isEditing = false
        self.draft = EditablePlanDraft(plan: updatedPlan)

        Task {
            NotificationService.shared.cancelNotifications(for: updatedPlan.id)
            let notificationsEnabled = await NotificationService.shared.notificationsEnabled()
            guard notificationsEnabled else { return }

            do {
                _ = try await NotificationService.shared.scheduleNotifications(for: updatedPlan)
            } catch {
                await MainActor.run {
                    errorMessage = "Plan saved, but reminders could not be fully rescheduled."
                }
            }
        }
    }

    private func addMedication() {
        guard var draft else { return }
        draft.medications.append(.newDefault())
        self.draft = draft
    }

    private func removeMedication(at index: Int) {
        guard var draft, draft.medications.indices.contains(index), draft.medications.count > 1 else { return }
        draft.medications.remove(at: index)
        self.draft = draft
    }

    private func addFollowUp() {
        guard var draft else { return }
        draft.followUps.append(.newDefault())
        self.draft = draft
    }

    private func removeFollowUp(at index: Int) {
        guard var draft, draft.followUps.indices.contains(index) else { return }
        draft.followUps.remove(at: index)
        self.draft = draft
    }

    private func medicationBinding<Value>(
        _ index: Int,
        keyPath: WritableKeyPath<EditableMedicationDraft, Value>,
        default defaultValue: Value
    ) -> Binding<Value> {
        Binding(
            get: {
                guard let draft, draft.medications.indices.contains(index) else {
                    return defaultValue
                }
                return draft.medications[index][keyPath: keyPath]
            },
            set: { newValue in
                guard var draft, draft.medications.indices.contains(index) else { return }
                draft.medications[index][keyPath: keyPath] = newValue
                self.draft = draft
            }
        )
    }

    private func followUpBinding<Value>(
        _ index: Int,
        keyPath: WritableKeyPath<EditableFollowUpDraft, Value>,
        default defaultValue: Value
    ) -> Binding<Value> {
        Binding(
            get: {
                guard let draft, draft.followUps.indices.contains(index) else {
                    return defaultValue
                }
                return draft.followUps[index][keyPath: keyPath]
            },
            set: { newValue in
                guard var draft, draft.followUps.indices.contains(index) else { return }
                draft.followUps[index][keyPath: keyPath] = newValue
                self.draft = draft
            }
        )
    }

    private func toggleStorage(_ requirement: StorageRequirement, forMedicationAt index: Int) {
        guard var draft, draft.medications.indices.contains(index) else { return }
        if draft.medications[index].storage.contains(requirement) {
            draft.medications[index].storage.removeAll { $0 == requirement }
        } else {
            draft.medications[index].storage.append(requirement)
        }
        self.draft = draft
    }

    private func storageSummary(forMedicationAt index: Int) -> String {
        guard let medication = draft?.medications[safe: index] else { return "None" }
        let filtered = medication.storage.filter { $0 != .unknown }
        if filtered.isEmpty {
            return "None"
        }
        return filtered.map(\.displayName).joined(separator: ", ")
    }
}

@MainActor
private struct EditablePlanDraft {
    var id: UUID
    var createdAt: Date
    var sourceOCRText: String
    var sourceInstructionImagePaths: [String]
    var uncertainties: [ExtractionUncertainty]
    var medications: [EditableMedicationDraft]
    var followUps: [EditableFollowUpDraft]

    init(plan: MedicationPlan) {
        self.id = plan.id
        self.createdAt = plan.createdAt
        self.sourceOCRText = plan.sourceOCRText
        self.sourceInstructionImagePaths = plan.storedInstructionImagePaths
        self.uncertainties = plan.uncertainties
        self.medications = plan.medications.map(EditableMedicationDraft.init)
        self.followUps = plan.followUp.map(EditableFollowUpDraft.init)
    }

    var isValid: Bool {
        buildPlan() != nil
    }

    func buildPlan() -> MedicationPlan? {
        guard !medications.isEmpty else { return nil }
        let mappedMeds = medications.compactMap { $0.toMedicationItem() }
        guard mappedMeds.count == medications.count else { return nil }

        let mappedFollowUps = followUps.compactMap { $0.toFollowUpItem() }

        return MedicationPlan(
            id: id,
            createdAt: createdAt,
            sourceOCRText: sourceOCRText,
            sourceInstructionImagePaths: sourceInstructionImagePaths,
            medications: mappedMeds,
            followUp: mappedFollowUps,
            uncertainties: uncertainties
        )
    }
}

@MainActor
private struct EditableMedicationDraft {
    var id: UUID
    var name: String
    var dose: String
    var route: MedicationRoute
    var frequency: MedicationFrequency
    var timesText: String
    var startDate: Date
    var endDate: Date
    var withFood: FoodTiming
    var notesText: String
    var storage: [StorageRequirement]

    init(
        id: UUID,
        name: String,
        dose: String,
        route: MedicationRoute,
        frequency: MedicationFrequency,
        timesText: String,
        startDate: Date,
        endDate: Date,
        withFood: FoodTiming,
        notesText: String,
        storage: [StorageRequirement]
    ) {
        self.id = id
        self.name = name
        self.dose = dose
        self.route = route
        self.frequency = frequency
        self.timesText = timesText
        self.startDate = startDate
        self.endDate = endDate
        self.withFood = withFood
        self.notesText = notesText
        self.storage = storage
    }

    init(item: MedicationItem) {
        self.id = item.id
        self.name = item.name
        self.dose = item.dose
        self.route = item.route
        self.frequency = item.frequency
        self.timesText = item.times.joined(separator: ", ")
        self.startDate = item.startDate
        self.endDate = item.endDate
        self.withFood = item.withFood
        self.notesText = item.notes.joined(separator: "; ")
        self.storage = item.storage.filter { $0 != .unknown }
    }

    static func newDefault() -> EditableMedicationDraft {
        let today = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 6, to: today) ?? today
        return EditableMedicationDraft(
            id: UUID(),
            name: "",
            dose: "",
            route: .oral,
            frequency: MedicationFrequency(type: .timesPerDay, value: 1),
            timesText: "08:00",
            startDate: today,
            endDate: end,
            withFood: .noRequirement,
            notesText: "",
            storage: []
        )
    }

    var hasValidTimes: Bool {
        Self.parseTimes(timesText) != nil
    }

    func toMedicationItem() -> MedicationItem? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDose = dose.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty,
              !trimmedDose.isEmpty,
              let parsedTimes = Self.parseTimes(timesText),
              endDate >= startDate
        else {
            return nil
        }

        let notes = notesText
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return MedicationItem(
            id: id,
            name: trimmedName,
            dose: trimmedDose,
            route: route,
            frequency: MedicationFrequency(type: .specificTimes, value: parsedTimes.count),
            times: parsedTimes,
            startDate: Calendar.current.startOfDay(for: startDate),
            endDate: Calendar.current.startOfDay(for: endDate),
            withFood: withFood,
            notes: notes,
            storage: storage.isEmpty ? [.unknown] : storage
        )
    }

    private static func parseTimes(_ raw: String) -> [String]? {
        let values = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !values.isEmpty, values.allSatisfy({ DateTimeUtils.parseTimeComponents($0) != nil }) else {
            return nil
        }
        return values
    }
}

@MainActor
private struct EditableFollowUpDraft {
    var id: UUID
    var date: Date
    var notes: String

    init(item: FollowUpItem) {
        self.id = item.id
        self.date = item.date
        self.notes = item.notes
    }

    static func newDefault() -> EditableFollowUpDraft {
        EditableFollowUpDraft(id: UUID(), date: Date(), notes: "")
    }

    init(id: UUID, date: Date, notes: String) {
        self.id = id
        self.date = date
        self.notes = notes
    }

    func toFollowUpItem() -> FollowUpItem? {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNotes.isEmpty else {
            return nil
        }
        return FollowUpItem(id: id, date: Calendar.current.startOfDay(for: date), notes: trimmedNotes)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

private struct InstructionImagesViewer: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let imagePaths: [String]

    @State private var images: [UIImage] = []

    var body: some View {
        NavigationStack {
            Group {
                if images.isEmpty {
                    ContentUnavailableView(
                        "No instruction images",
                        systemImage: "doc.viewfinder",
                        description: Text("This plan was created without original scans.")
                    )
                    .padding()
                } else {
                    TabView {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                            ZStack {
                                Color.black.opacity(0.92)
                                    .ignoresSafeArea()
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .padding(12)
                                    .accessibilityLabel("Instruction image \(index + 1)")
                            }
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            images = imagePaths.compactMap {
                PlanImageStoreService.shared.loadImage(relativePath: $0)
            }
        }
    }
}
