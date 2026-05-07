import SwiftUI

struct PlanDraftView: View {
    let extraction: LLMExtractionResult
    let sourceOCRText: String
    var onBack: () -> Void
    var onConfirm: (MedicationPlan) -> Void

    @State private var medications: [EditableMedication]
    @State private var uncertaintyPaths: Set<String>

    init(
        extraction: LLMExtractionResult,
        sourceOCRText: String,
        onBack: @escaping () -> Void,
        onConfirm: @escaping (MedicationPlan) -> Void
    ) {
        self.extraction = extraction
        self.sourceOCRText = sourceOCRText
        self.onBack = onBack
        self.onConfirm = onConfirm

        let sharedDefaultStartDate = Calendar.current.startOfDay(for: Date())
        let mapped = extraction.medications.map { med in
            EditableMedication.fromLLM(med, defaultStartDate: sharedDefaultStartDate)
        }
        _medications = State(initialValue: mapped)
        _uncertaintyPaths = State(initialValue: Set(extraction.uncertainties.map(\.path)))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    header

                    ForEach(medications.indices, id: \.self) { index in
                        medicationCard(index: index)
                    }
                }
                .padding(20)
            }

            actionBar
                .padding(16)
                .background(.ultraThinMaterial)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plan Draft Review")
                .font(.title2.weight(.semibold))
            Text("Review details, fill missing course dates, and fix uncertain fields.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func medicationCard(index: Int) -> some View {
        let pathPrefix = "medications[\(index)]"
        let invalidTimes = !Validation.hasValidTimes(medications[index].times)
        let invalidDates = !Validation.areCourseDatesValid(start: medications[index].startDate, end: medications[index].endDate)
        let uncertainTimes = uncertaintyPaths.contains("\(pathPrefix).times")
        let uncertainStartDate = uncertaintyPaths.contains("\(pathPrefix).start_date")
        let uncertainEndDate = uncertaintyPaths.contains("\(pathPrefix).end_date")

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Medication \(index + 1)", systemImage: "pills")
                    .font(.headline)
                Spacer()
                if hasAnyUncertainty(index: index) {
                    Text("Needs review")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.yellow.opacity(0.25), in: Capsule())
                }
            }

            textField(
                title: "Name",
                text: $medications[index].name,
                uncertain: uncertaintyPaths.contains("\(pathPrefix).name")
            )

            textField(
                title: "Dose",
                text: $medications[index].dose,
                uncertain: uncertaintyPaths.contains("\(pathPrefix).dose")
            )

            Picker("Route", selection: $medications[index].route) {
                ForEach(MedicationRoute.allCases, id: \.self) { route in
                    Text(route.displayName).tag(route)
                }
            }
            .pickerStyle(.menu)

            Picker("Food timing", selection: $medications[index].withFood) {
                ForEach(FoodTiming.allCases, id: \.self) { timing in
                    Text(timing.displayName).tag(timing)
                }
            }
            .pickerStyle(.menu)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Reminder times")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Button {
                        medications[index].times.append("08:00")
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .font(.caption)
                }

                ForEach(medications[index].times.indices, id: \.self) { timeIndex in
                    HStack {
                        TextField("HH:mm", text: $medications[index].times[timeIndex])
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(
                                        Validation.isValidTimeString(medications[index].times[timeIndex]) ? Color.gray.opacity(0.4) : .red,
                                        lineWidth: 1
                                    )
                            )
                        Button(role: .destructive) {
                            medications[index].times.remove(at: timeIndex)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                if invalidTimes {
                    Text("Use at least one valid HH:mm time.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(12)
            .background(
                (uncertainTimes ? Color.yellow.opacity(0.22) : Color(.tertiarySystemBackground)),
                in: RoundedRectangle(cornerRadius: 12)
            )

            courseDateSection(index: index, uncertainStartDate: uncertainStartDate, uncertainEndDate: uncertainEndDate)

            if medications[index].requiresDurationConfirmation && medications[index].endDate == nil {
                Text("Duration was not found. Please confirm by selecting End date or Duration.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if invalidDates {
                Text("A valid end date is required before creating reminders.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            textField(
                title: "Notes",
                text: $medications[index].notesText,
                uncertain: uncertaintyPaths.contains("\(pathPrefix).notes")
            )

            Menu {
                ForEach(StorageRequirement.allCases, id: \.self) { requirement in
                    if requirement != .unknown {
                        Button {
                            medications[index].toggleStorage(requirement)
                        } label: {
                            Label(
                                requirement.displayName,
                                systemImage: medications[index].storage.contains(requirement) ? "checkmark.circle.fill" : "circle"
                            )
                        }
                    }
                }
            } label: {
                HStack {
                    Text("Storage")
                    Spacer()
                    Text(storageSummary(medications[index].storage))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func courseDateSection(index: Int, uncertainStartDate: Bool, uncertainEndDate: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Course dates")
                .font(.subheadline.weight(.medium))

            DatePicker("Start", selection: $medications[index].startDate, displayedComponents: .date)

            Picker("End mode", selection: $medications[index].endMode) {
                Text("End date").tag(EditableMedication.EndMode.endDate)
                Text("Duration").tag(EditableMedication.EndMode.duration)
            }
            .pickerStyle(.segmented)

            switch medications[index].endMode {
            case .endDate:
                if let endDate = medications[index].endDate {
                    DatePicker(
                        "End",
                        selection: Binding(
                            get: { endDate },
                            set: { medications[index].endDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                } else {
                    DatePicker("End (select then apply)", selection: $medications[index].draftEndDate, displayedComponents: .date)
                    Button("Apply End Date") {
                        medications[index].endDate = medications[index].draftEndDate
                    }
                    .buttonStyle(.bordered)
                }
            case .duration:
                Stepper("Duration: \(medications[index].durationDays) day(s)", value: $medications[index].durationDays, in: 1...365)
                Button("Apply Duration") {
                    let start = medications[index].startDate
                    let end = Calendar.current.date(byAdding: .day, value: medications[index].durationDays - 1, to: start)
                    medications[index].endDate = end
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(
            ((uncertainStartDate || uncertainEndDate) ? Color.yellow.opacity(0.22) : Color(.tertiarySystemBackground)),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button("Back", action: onBack)
                .buttonStyle(.bordered)

            Button {
                guard let plan = buildPlan() else { return }
                onConfirm(plan)
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(buildPlan() == nil)
        }
    }

    private func textField(title: String, text: Binding<String>, uncertain: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(uncertain ? Color.yellow.opacity(0.22) : Color(.tertiarySystemBackground))
                )
        }
    }

    private func storageSummary(_ storage: [StorageRequirement]) -> String {
        let values = storage.filter { $0 != .unknown }
        if values.isEmpty {
            return "None"
        }
        return values.map(\.displayName).joined(separator: ", ")
    }

    private func hasAnyUncertainty(index: Int) -> Bool {
        uncertaintyPaths.contains { $0.hasPrefix("medications[\(index)]") }
    }

    private func buildPlan() -> MedicationPlan? {
        guard !medications.isEmpty else { return nil }

        let mapped: [MedicationItem] = medications.compactMap { editable in
            guard !editable.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !editable.dose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  Validation.hasValidTimes(editable.times),
                  let end = editable.endDate,
                  end >= editable.startDate
            else {
                return nil
            }

            let notes = editable.notesText
                .split(separator: ";")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            return MedicationItem(
                id: editable.id,
                name: editable.name,
                dose: editable.dose,
                route: editable.route,
                frequency: editable.frequency,
                times: editable.times,
                startDate: Calendar.current.startOfDay(for: editable.startDate),
                endDate: Calendar.current.startOfDay(for: end),
                withFood: editable.withFood,
                notes: notes,
                storage: editable.storage.isEmpty ? [.unknown] : editable.storage
            )
        }

        guard mapped.count == medications.count else { return nil }

        let followUp = extraction.followUp.compactMap { item -> FollowUpItem? in
            guard let date = DateTimeUtils.parseDay(item.date) else { return nil }
            return FollowUpItem(date: date, notes: item.notes)
        }

        let uncertainties = extraction.uncertainties.map {
            ExtractionUncertainty(path: $0.path, reason: $0.reason, candidates: $0.candidates)
        }

        return MedicationPlan(
            sourceOCRText: sourceOCRText,
            medications: mapped,
            followUp: followUp,
            uncertainties: uncertainties
        )
    }
}

private struct EditableMedication {
    enum EndMode {
        case endDate
        case duration
    }

    var id: UUID
    var name: String
    var dose: String
    var route: MedicationRoute
    var frequency: MedicationFrequency
    var times: [String]
    var withFood: FoodTiming
    var notesText: String
    var storage: [StorageRequirement]
    var startDate: Date
    var endDate: Date?
    var draftEndDate: Date
    var durationDays: Int
    var endMode: EndMode
    var requiresDurationConfirmation: Bool

    static func fromLLM(_ med: LLMMedication, defaultStartDate: Date) -> EditableMedication {
        let calendar = Calendar.current
        let parsedStartDate = DateTimeUtils.parseDay(med.startDate)
        let inferredAbsoluteStartDate = inferAbsoluteStartDate(from: med)
        let inferredRelativeStartDate = inferRelativeStartDate(from: med, referenceDate: defaultStartDate)
        let resolvedStartDate = calendar.startOfDay(
            for: parsedStartDate ?? inferredAbsoluteStartDate ?? inferredRelativeStartDate ?? defaultStartDate
        )
        let parsedEndDate = DateTimeUtils.parseDay(med.endDate).map { calendar.startOfDay(for: $0) }

        let generatedTimes: [String]
        if med.times.isEmpty && med.frequency.type == .timesPerDay {
            generatedTimes = DateTimeUtils.defaultTimes(for: med.frequency)
        } else {
            generatedTimes = med.times
        }

        let safeTimes = generatedTimes.isEmpty ? ["08:00"] : generatedTimes

        var resolvedEndDate = parsedEndDate
        var resolvedDurationDays = 7
        var resolvedEndMode: EndMode = .duration
        var needsDurationConfirmation = false

        if let parsedEndDate {
            resolvedDurationDays = max(durationDays(from: resolvedStartDate, to: parsedEndDate), 1)
            resolvedEndMode = .endDate
        } else if let inferredDurationDays = inferDurationDays(from: med) {
            resolvedDurationDays = inferredDurationDays
            resolvedEndDate = calendar.date(byAdding: .day, value: inferredDurationDays - 1, to: resolvedStartDate)
            resolvedEndMode = .duration
        } else {
            needsDurationConfirmation = true
        }

        let resolvedDraftEndDate = resolvedEndDate
            ?? calendar.date(byAdding: .day, value: resolvedDurationDays - 1, to: resolvedStartDate)
            ?? resolvedStartDate

        return EditableMedication(
            id: UUID(),
            name: med.name,
            dose: med.dose,
            route: med.route,
            frequency: med.frequency,
            times: safeTimes,
            withFood: med.withFood,
            notesText: med.notes.joined(separator: "; "),
            storage: med.storage.filter { $0 != .unknown },
            startDate: resolvedStartDate,
            endDate: resolvedEndDate,
            draftEndDate: resolvedDraftEndDate,
            durationDays: resolvedDurationDays,
            endMode: resolvedEndMode,
            requiresDurationConfirmation: needsDurationConfirmation
        )
    }

    mutating func toggleStorage(_ value: StorageRequirement) {
        if storage.contains(value) {
            storage.removeAll { $0 == value }
        } else {
            storage.append(value)
        }
    }

    private static func durationDays(from start: Date, to end: Date) -> Int {
        let diff = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: start), to: Calendar.current.startOfDay(for: end)).day ?? 0
        return diff + 1
    }

    private static func inferDurationDays(from med: LLMMedication) -> Int? {
        let corpus = inferenceCorpus(from: med)

        if let explicitStopDays = firstMatchedDurationDays(
            in: corpus,
            pattern: #"([0-9零〇一二两三四五六七八九十百半]{1,6})\s*(天|日|周|星期|个?月)\s*(半)?\s*(?:后)?\s*(?:停|停止|停药|结束|即可停药)"#
        ) {
            return max(explicitStopDays, 1)
        }
        if let courseDays = firstMatchedDurationDays(
            in: corpus,
            pattern: #"(?:疗程(?:为)?|持续|连续|连用|共|总共|用药)\s*([0-9零〇一二两三四五六七八九十百半]{1,6})\s*(天|日|周|星期|个?月)\s*(半)?"#
        ) {
            return max(courseDays, 1)
        }
        if let usageDays = firstMatchedDurationDays(
            in: corpus,
            pattern: #"(?:使用|服用|滴用|外用)\s*([0-9零〇一二两三四五六七八九十百半]{1,6})\s*(天|日|周|星期|个?月)\s*(半)?(?!\s*[0-9零〇一二两三四五六七八九十]+\s*次)"#
        ) {
            return max(usageDays, 1)
        }
        if let days = firstMatchedInt(in: corpus, pattern: #"(\d{1,3})\s*(day|days|d)\b"#) {
            return max(days, 1)
        }
        if let weeks = firstMatchedInt(in: corpus, pattern: #"(\d{1,3})\s*(week|weeks|w)\b"#) {
            return max(weeks * 7, 1)
        }
        if let months = firstMatchedInt(in: corpus, pattern: #"(\d{1,2})\s*(month|months|mo)\b"#) {
            return max(months * 30, 1)
        }
        return nil
    }

    private static func inferAbsoluteStartDate(from med: LLMMedication) -> Date? {
        let text = inferenceCorpus(from: med)
        guard let regex = try? NSRegularExpression(pattern: #"(20\d{2})\s*[年/\-\.]\s*(\d{1,2})\s*[月/\-\.]\s*(\d{1,2})\s*日?"#, options: []) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 4,
              let yearRange = Range(match.range(at: 1), in: text),
              let monthRange = Range(match.range(at: 2), in: text),
              let dayRange = Range(match.range(at: 3), in: text),
              let year = Int(text[yearRange]),
              let month = Int(text[monthRange]),
              let day = Int(text[dayRange])
        else {
            return nil
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)
    }

    private static func inferRelativeStartDate(from med: LLMMedication, referenceDate: Date) -> Date? {
        let text = inferenceCorpus(from: med)
        let calendar = Calendar.current

        let relativePatterns = [
            #"(?:术后|手术后)\s*(?:第)?\s*([0-9零〇一二两三四五六七八九十百半]{1,6})\s*(天|日|周|星期|个?月)\s*(半)?\s*(?:后)?\s*(?:开始|开始使用|开始服用|使用|服用|滴用)"#,
            #"([0-9零〇一二两三四五六七八九十百半]{1,6})\s*(天|日|周|星期|个?月)\s*(半)?\s*后\s*(?:开始|开始使用|开始服用|使用|服用|滴用)"#,
            #"(?:start|begin)\s*(?:after|in)\s*(\d{1,3})\s*(day|days|week|weeks|month|months)"#
        ]

        for pattern in relativePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range),
                  match.numberOfRanges >= 3,
                  let valueRange = Range(match.range(at: 1), in: text),
                  let unitRange = Range(match.range(at: 2), in: text)
            else {
                continue
            }

            let rawValue = String(text[valueRange])
            let rawUnit = String(text[unitRange])
            let halfRange = match.numberOfRanges > 3 ? match.range(at: 3) : NSRange(location: NSNotFound, length: 0)
            let hasHalf = halfRange.location != NSNotFound
            guard let days = durationToDays(valueToken: rawValue, unitToken: rawUnit, hasHalf: hasHalf) else {
                continue
            }
            return calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: referenceDate))
        }

        return nil
    }

    private static func inferenceCorpus(from med: LLMMedication) -> String {
        ([med.name, med.dose, med.startDate, med.endDate] + med.notes).joined(separator: " ").lowercased()
    }

    private static func firstMatchedInt(in text: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return Int(text[captureRange])
    }

    private static func firstMatchedDurationDays(in text: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 3,
              let valueRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text)
        else {
            return nil
        }

        let valueToken = String(text[valueRange])
        let unitToken = String(text[unitRange])
        let halfRange = match.range(at: 3)
        let hasHalf = halfRange.location != NSNotFound
        return durationToDays(valueToken: valueToken, unitToken: unitToken, hasHalf: hasHalf)
    }

    private static func durationToDays(valueToken: String, unitToken: String, hasHalf: Bool) -> Int? {
        guard var value = parseNumericToken(valueToken) else { return nil }
        if hasHalf {
            value += 0.5
        }

        let normalizedUnit = unitToken.replacingOccurrences(of: " ", with: "")
        let dayValue: Double
        switch normalizedUnit {
        case "天", "日", "day", "days", "d":
            dayValue = value
        case "周", "星期", "week", "weeks", "w":
            dayValue = value * 7
        case "月", "个月", "month", "months", "mo":
            dayValue = value * 30
        default:
            return nil
        }

        return max(Int(round(dayValue)), 1)
    }

    private static func parseNumericToken(_ token: String) -> Double? {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        if normalized == "half" || normalized == "半" {
            return 0.5
        }
        if let direct = Double(normalized) {
            return direct
        }
        if normalized.hasSuffix("半") {
            let base = String(normalized.dropLast())
            if base.isEmpty {
                return 0.5
            }
            guard let integerPart = chineseIntegerValue(base) else { return nil }
            return Double(integerPart) + 0.5
        }

        if let intValue = chineseIntegerValue(normalized) {
            return Double(intValue)
        }
        return nil
    }

    private static func chineseIntegerValue(_ token: String) -> Int? {
        let map: [Character: Int] = [
            "零": 0, "〇": 0,
            "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
            "五": 5, "六": 6, "七": 7, "八": 8, "九": 9
        ]

        if let numeric = Int(token) {
            return numeric
        }

        var total = 0
        var current = 0
        var consumed = false

        for char in token {
            if let digit = map[char] {
                current = digit
                consumed = true
                continue
            }
            if char == "十" {
                consumed = true
                let value = current == 0 ? 1 : current
                total += value * 10
                current = 0
                continue
            }
            if char == "百" {
                consumed = true
                let value = current == 0 ? 1 : current
                total += value * 100
                current = 0
                continue
            }
            return nil
        }

        guard consumed else { return nil }
        return total + current
    }
}
