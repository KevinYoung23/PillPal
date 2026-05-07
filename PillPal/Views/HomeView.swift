import SwiftUI
import Combine
import UIKit

enum CalendarDot: Hashable {
    case medication
    case perfect
    case missed
    case followUp

    var color: Color {
        switch self {
        case .medication:
            return .blue
        case .perfect:
            return .green
        case .missed:
            return .red
        case .followUp:
            return .purple
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var appStore: AppStore

    @AppStorage("pile_by_default") private var pileByDefault = true
    @AppStorage("home_card_style") private var homeCardStyle = "concise"
    @State private var pendingUnmarkDose: TodayDose?
    @State private var pendingDeleteDose: TodayDose?
    @State private var editingDose: TodayDose?
    @State private var viewingDose: TodayDose?
    @State private var checkingDoseID: String?
    @State private var now = Date()
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var displayedMonth = DateTimeUtils.startOfMonth(for: Date())
    @State private var showCalendarPopover = false
    @State private var showMissingExpanded = false
    @State private var showTODOExpanded = false
    @State private var showLaterExpanded = false
    @State private var showTakenHistory = false
    @Namespace private var doseCardNamespace

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var selectedDateBinding: Binding<Date> {
        Binding(
            get: { selectedDate },
            set: { selectedDate = Calendar.current.startOfDay(for: $0) }
        )
    }

    private var isSelectedDateToday: Bool {
        Calendar.current.isDate(selectedDate, inSameDayAs: now)
    }

    private var isSelectedDatePast: Bool {
        let startOfToday = Calendar.current.startOfDay(for: now)
        return selectedDate < startOfToday
    }

    private var isSelectedDateFuture: Bool {
        let startOfToday = Calendar.current.startOfDay(for: now)
        return selectedDate > startOfToday
    }

    private var todayDoses: [TodayDose] {
        appStore.todaySchedule(referenceDate: selectedDate)
    }

    private var showDetailedMainCards: Bool {
        homeCardStyle != "concise"
    }

    private var missingDoses: [TodayDose] {
        todayDoses.filter { dose in
            guard !dose.isCompleted else { return false }
            if isSelectedDateToday {
                return now.timeIntervalSince(dose.date) > 3600
            }
            return isSelectedDatePast
        }
    }

    private var todoDoses: [TodayDose] {
        guard isSelectedDateToday else { return [] }
        return todayDoses.filter { dose in
            guard !dose.isCompleted else { return false }
            let delta = dose.date.timeIntervalSince(now)
            return delta >= -3600 && delta <= 3600
        }
    }

    private var laterDoses: [TodayDose] {
        todayDoses.filter { dose in
            guard !dose.isCompleted else { return false }
            if isSelectedDateToday {
                return dose.date.timeIntervalSince(now) > 3600
            }
            return isSelectedDateFuture
        }
    }

    private var takenDoses: [TodayDose] {
        todayDoses
            .filter { $0.isCompleted }
            .sorted { $0.date > $1.date }
    }

    private var scheduleAnimationSignature: [String] {
        [DateTimeUtils.formatDay(selectedDate)] + todayDoses.map { dose in
            "\(dose.id)|\(bucketName(for: dose))|\(dose.isCompleted)"
        }
    }

    private var followUpsForDate: [FollowUpItem] {
        appStore.plans
            .flatMap(\.followUp)
            .filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
            .sorted { $0.date < $1.date }
    }

    private var calendarDayDots: (Date) -> [CalendarDot] {
        { date in
            let dayStart = Calendar.current.startOfDay(for: date)
            let todayStart = Calendar.current.startOfDay(for: now)
            let isPast = dayStart < todayStart
            let isToday = Calendar.current.isDate(dayStart, inSameDayAs: todayStart)

            let doses = appStore.todaySchedule(referenceDate: dayStart)
            let hasMedications = !doses.isEmpty
            let hasIncomplete = doses.contains { !$0.isCompleted }
            let allCompleted = hasMedications && doses.allSatisfy { $0.isCompleted }

            let hasFollowUps = appStore.plans
                .flatMap(\.followUp)
                .contains { Calendar.current.isDate($0.date, inSameDayAs: dayStart) }

            var dots: [CalendarDot] = []

            if isPast {
                if hasIncomplete {
                    dots.append(.missed)
                } else if allCompleted {
                    dots.append(.perfect)
                }
            } else {
                if isToday || dayStart > todayStart {
                    if hasIncomplete {
                        dots.append(.medication)
                    }
                }
            }

            if hasFollowUps {
                dots.append(.followUp)
            }

            return dots
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header

                    todaySection

                    dateDetailsSection
                }
                .padding(20)
            }
            .dockSafeContentInset()
            .navigationTitle("PillPal")
            .sheet(item: $editingDose) { dose in
                DoseEditView(
                    dose: dose,
                    onCancel: {
                        editingDose = nil
                    },
                    onSave: { payload in
                        applyDoseEdit(dose: dose, payload: payload)
                        editingDose = nil
                    }
                )
            }
            .sheet(item: $viewingDose) { dose in
                TodayDoseDetailView(dose: dose)
            }
            .alert(
                "Confirm to unmark",
                isPresented: Binding(
                    get: { pendingUnmarkDose != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingUnmarkDose = nil
                        }
                    }
                ),
                presenting: pendingUnmarkDose
            ) { dose in
                Button("Yes", role: .destructive) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                        appStore.unmarkDoseTaken(dose.id)
                    }
                    pendingUnmarkDose = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingUnmarkDose = nil
                }
            } message: { dose in
                Text("Unmark \(dose.medicationName) at \(DateTimeUtils.formatDisplayTime(dose.date)) as taken?")
            }
            .alert(
                "Delete medication?",
                isPresented: Binding(
                    get: { pendingDeleteDose != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingDeleteDose = nil
                        }
                    }
                ),
                presenting: pendingDeleteDose
            ) { dose in
                Button("Delete", role: .destructive) {
                    deleteDoseFromPlan(dose)
                    pendingDeleteDose = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteDose = nil
                }
            } message: { dose in
                Text("Delete \(dose.medicationName) from this plan and remove future reminders?")
            }
            .onReceive(clock) { current in
                now = current
            }
            .onAppear {
                displayedMonth = DateTimeUtils.startOfMonth(for: selectedDate)
                applyPilePreference()
            }
            .onChange(of: selectedDate) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                    if !Calendar.current.isDate(selectedDate, equalTo: displayedMonth, toGranularity: .month) {
                        displayedMonth = DateTimeUtils.startOfMonth(for: selectedDate)
                    }
                    applyPilePreference()
                    showCalendarPopover = false
                }
            }
            .onChange(of: pileByDefault) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                    applyPilePreference()
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isSelectedDateToday ? "Today" : selectedDate.formatted(.dateTime.weekday(.wide)))
                .font(.largeTitle.bold())

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                    showCalendarPopover.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .font(.subheadline.weight(.semibold))
                    Text(DateTimeUtils.formatDisplayDate(selectedDate))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: showCalendarPopover ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.38), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showCalendarPopover, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                floatingCalendarPopover
                    .frame(width: calendarPopoverSize.width, height: calendarPopoverSize.height)
                    .presentationCompactAdaptation(.popover)
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var floatingCalendarPopover: some View {
        let width = calendarPopoverSize.width
        let height = calendarPopoverSize.height

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Select Date")
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        showCalendarPopover = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            CompactColorCalendarView(
                displayedMonth: $displayedMonth,
                selectedDate: selectedDateBinding,
                dayDots: calendarDayDots
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(14)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 24, x: 0, y: 10)
    }

    private var calendarPopoverSize: CGSize {
        let width = min(UIScreen.main.bounds.width - 30, 312)
        let height = min(UIScreen.main.bounds.height * 0.48, 318)
        return CGSize(width: width, height: height)
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Medication Schedule")
                .font(.headline)

            if todayDoses.isEmpty {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: 120)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.title3)
                            Text("No reminders yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
            } else {
                if !missingDoses.isEmpty {
                    missingSection
                }

                if !todoDoses.isEmpty {
                    todoSection
                }

                if !laterDoses.isEmpty {
                    laterSection
                }

                if !takenDoses.isEmpty {
                    takenSection
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: scheduleAnimationSignature)
    }

    private var dateDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Date Details")
                .font(.headline)

            if followUpsForDate.isEmpty {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: 90)
                    .overlay {
                        Text("No follow-up items on this date.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
            } else {
                if !followUpsForDate.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Follow-up")
                            .font(.subheadline.weight(.semibold))

                        ForEach(followUpsForDate) { followUp in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(DateTimeUtils.formatDisplayDate(followUp.date))
                                    .font(.subheadline.weight(.semibold))
                                Text(followUp.notes)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(response: 0.35, dampingFraction: 0.88), value: DateTimeUtils.formatDay(selectedDate))
    }

    private var missingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !missingDoses.isEmpty {
                expandableDosePile(
                    collapsedTitle: isSelectedDateToday ? "Missing" : "Missed",
                    expandedTitle: isSelectedDateToday ? "Missing" : "Missed",
                    icon: "exclamationmark.triangle.fill",
                    tint: .red,
                    doses: missingDoses,
                    isExpanded: $showMissingExpanded,
                    cardStyle: .missing
                )
            }
        }
    }

    private var todoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Now")
                    .font(.headline)
                Spacer()
                Text("± 1 hour")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if !todoDoses.isEmpty {
                expandableDosePile(
                    collapsedTitle: "Now",
                    expandedTitle: "Now",
                    icon: "list.bullet",
                    tint: .blue,
                    doses: todoDoses,
                    isExpanded: $showTODOExpanded,
                    cardStyle: .todo
                )
            }
        }
    }

    private var laterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !laterDoses.isEmpty {
                expandableDosePile(
                    collapsedTitle: isSelectedDateToday ? "Later Today" : "Scheduled",
                    expandedTitle: isSelectedDateToday ? "Later Today" : "Scheduled",
                    icon: "clock",
                    tint: Color(uiColor: .darkGray),
                    doses: laterDoses,
                    isExpanded: $showLaterExpanded,
                    cardStyle: .later
                )
            }
        }
    }

    private var takenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !takenDoses.isEmpty {
                expandableDosePile(
                    collapsedTitle: isSelectedDateToday ? "Taken Today" : "Taken",
                    expandedTitle: isSelectedDateToday ? "Taken Today" : "Taken",
                    icon: "checkmark.circle.fill",
                    tint: .green,
                    doses: takenDoses,
                    isExpanded: $showTakenHistory,
                    cardStyle: .taken
                )
            }
        }
    }

    @ViewBuilder
    private func expandableDosePile(
        collapsedTitle: String,
        expandedTitle: String,
        icon: String,
        tint: Color,
        doses: [TodayDose],
        isExpanded: Binding<Bool>,
        cardStyle: DoseCardStyle
    ) -> some View {
        let canCollapse = doses.count > 1
        let expanded = canCollapse ? isExpanded.wrappedValue : true
        let visibleDoses = expanded ? doses : Array(doses.prefix(3))
        // Keep only a thin edge visible; avoid showing underlying text.
        let collapsedSpacing = showDetailedMainCards ? -124.0 : -70.0
        let canPeekExpand = !expanded && doses.count > 1
        let collapsedPeekTapHeight: CGFloat = showDetailedMainCards ? 24 : 18

        VStack(alignment: .leading, spacing: 10) {
            Button {
                guard canCollapse else { return }
                withAnimation(.spring(response: 0.36, dampingFraction: 0.87)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack {
                    Label(expanded ? expandedTitle : collapsedTitle, systemImage: icon)
                        .font(.headline)
                        .foregroundStyle(tint)
                    Spacer()
                    Text("\(doses.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if canCollapse {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            VStack(spacing: expanded ? 10 : collapsedSpacing) {
                ForEach(Array(visibleDoses.enumerated()), id: \.element.id) { index, dose in
                    let isCardInteractive = expanded || index == 0
                    doseCard(
                        dose,
                        style: cardStyle,
                        isInteractive: isCardInteractive,
                        forceOpaqueBackground: !expanded
                    )
                    .allowsHitTesting(isCardInteractive)
                    .overlay(
                        Group {
                            if !expanded {
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(index == 0 ? 0.16 : 0.24), lineWidth: 1)

                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.black.opacity(index == 0 ? 0.05 : 0.11), lineWidth: 0.9)
                            } else {
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(.clear, lineWidth: 0)
                            }
                        }
                    )
                    .shadow(
                        color: Color.black.opacity(!expanded ? (index == 0 ? 0.12 : 0.22) : 0.05),
                        radius: !expanded ? (index == 0 ? 6 : 12) : 3,
                        x: 0,
                        y: !expanded ? (index == 0 ? 4 : 8) : 2
                    )
                    .shadow(
                        color: Color.white.opacity(!expanded && index > 0 ? 0.22 : 0),
                        radius: !expanded && index > 0 ? 2.5 : 0,
                        x: 0,
                        y: !expanded && index > 0 ? -1 : 0
                    )
                    .zIndex(Double(visibleDoses.count - index))
                }
            }
            .animation(.spring(response: 0.36, dampingFraction: 0.87), value: expanded)
            .overlay {
                if canPeekExpand {
                    VStack {
                        Spacer(minLength: 0)
                        Color.clear
                            .frame(height: collapsedPeekTapHeight)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.36, dampingFraction: 0.87)) {
                                    isExpanded.wrappedValue = true
                                }
                            }
                    }
                }
            }
        }
    }

    private enum DoseCardStyle {
        case todo
        case later
        case missing
        case taken
    }

    private func bucketName(for dose: TodayDose) -> String {
        if dose.isCompleted {
            return "taken"
        }
        if now.timeIntervalSince(dose.date) > 3600 {
            return "missing"
        }
        let delta = dose.date.timeIntervalSince(now)
        if delta >= -3600 && delta <= 3600 {
            return "todo"
        }
        return "later"
    }

    private func markDoseTakenWithAnimation(_ dose: TodayDose) {
        HapticService.shared.playConfirm()

        withAnimation(.easeOut(duration: 0.15)) {
            checkingDoseID = dose.id
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                appStore.markDoseTaken(dose.id)
            }
            withAnimation(.easeOut(duration: 0.2)) {
                checkingDoseID = nil
            }
        }
    }

    private func doseCard(
        _ dose: TodayDose,
        style: DoseCardStyle,
        isInteractive: Bool = true,
        forceOpaqueBackground: Bool = false
    ) -> some View {
        let isChecking = checkingDoseID == dose.id
        let backgroundColor = doseCardBackgroundColor(for: style, opaque: forceOpaqueBackground)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(DateTimeUtils.formatDisplayTime(dose.date))
                    .font(.headline)
                Spacer()
                if isInteractive {
                    Button {
                        if dose.isCompleted {
                            pendingUnmarkDose = dose
                        } else {
                            markDoseTakenWithAnimation(dose)
                        }
                    } label: {
                        Label(
                            (dose.isCompleted || isChecking) ? "Taken" : "Mark Taken",
                            systemImage: (dose.isCompleted || isChecking) ? "checkmark.circle.fill" : "circle"
                        )
                        .font(.caption.weight(.semibold))
                        .scaleEffect(isChecking ? 1.16 : 1)
                        .symbolEffect(.bounce, value: isChecking)
                    }
                    .buttonStyle(.bordered)
                    .tint((dose.isCompleted || isChecking) ? .green : .accentColor)
                    .disabled(isChecking)
                }
            }

            Text(dose.medicationName)
                .font(.title3.weight(.semibold))

            if showDetailedMainCards {
                Text("\(dose.dose) • \(dose.route.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if dose.foodTiming != .unknown {
                    Text("Food: \(dose.foodTiming.displayName)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                let storageValues = dose.storage
                    .filter { $0 != .unknown }
                    .map(\.displayName)
                    .joined(separator: ", ")
                if !storageValues.isEmpty {
                    Text("Storage: \(storageValues)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let note = dose.notes.first, !note.isEmpty {
                    Text("Notes: \(note)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if style == .missing {
                    Text(isSelectedDateToday ? "Missing for more than 1 hour" : "Not marked as taken on this date")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.red)
                }

                if isInteractive {
                    Label("Tap for details • Hold to edit", systemImage: "hand.tap")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(backgroundColor)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            guard isInteractive else { return }
            viewingDose = dose
        }
        .contextMenu {
            if isInteractive {
                Button {
                    editingDose = dose
                } label: {
                    Label("Edit", systemImage: "square.and.pencil")
                }

                Button(role: .destructive) {
                    pendingDeleteDose = dose
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .matchedGeometryEffect(id: dose.id, in: doseCardNamespace)
    }

    private func doseCardBackgroundColor(for style: DoseCardStyle, opaque: Bool) -> Color {
        if opaque {
            switch style {
            case .todo:
                return Color(red: 0.86, green: 0.92, blue: 0.98)
            case .later:
                return Color(uiColor: .systemGray6)
            case .missing:
                return Color(red: 0.99, green: 0.90, blue: 0.90)
            case .taken:
                return Color(red: 0.89, green: 0.96, blue: 0.91)
            }
        }

        switch style {
        case .todo:
            return Color.blue.opacity(0.1)
        case .later:
            return Color(.systemGray6)
        case .missing:
            return Color.red.opacity(0.11)
        case .taken:
            return Color.green.opacity(0.1)
        }
    }

    private func applyDoseEdit(dose: TodayDose, payload: DoseEditPayload) {
        let trimmedDose = payload.doseText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDose.isEmpty else { return }

        switch payload.scope {
        case .thisArrangementOnly:
            appStore.applySingleArrangementEdit(
                dose: dose,
                newDose: trimmedDose,
                newTimeText: payload.timeText
            )

            Task {
                guard let medication = await MainActor.run(
                    body: { appStore.medicationItem(planId: dose.planId, medicationId: dose.medicationId) }
                ) else {
                    return
                }

                NotificationService.shared.cancelNotification(withIdentifier: dose.id)

                let notificationsEnabled = await NotificationService.shared.notificationsEnabled()
                guard notificationsEnabled else { return }

                let day = Calendar.current.startOfDay(for: dose.date)
                guard let editedDate = DateTimeUtils.dateAndTime(day: day, time: payload.timeText),
                      editedDate > Date()
                else {
                    return
                }

                do {
                    try await NotificationService.shared.scheduleSingleNotification(
                        planId: dose.planId,
                        medication: medication,
                        day: day,
                        time: payload.timeText,
                        identifier: dose.id,
                        overrideDose: trimmedDose
                    )
                } catch {
                    Logger.error("Failed to update edited single reminder notification.")
                }
            }

        case .allFutureArrangements:
            guard let updatedPlan = appStore.applyFutureArrangementEdit(
                dose: dose,
                newDose: trimmedDose,
                newTimeText: payload.timeText
            ) else {
                Logger.error("Failed to apply future reminder edit due to missing plan or medication.")
                return
            }

            Task {
                NotificationService.shared.cancelNotifications(for: updatedPlan.id)

                let notificationsEnabled = await NotificationService.shared.notificationsEnabled()
                guard notificationsEnabled else { return }

                do {
                    _ = try await NotificationService.shared.scheduleNotifications(for: updatedPlan)
                } catch {
                    Logger.error("Failed to reschedule notifications after future reminder edit.")
                }
            }
        }
    }

    private func applyPilePreference() {
        let defaultExpanded = !pileByDefault
        showMissingExpanded = defaultExpanded
        showTODOExpanded = defaultExpanded
        showLaterExpanded = defaultExpanded
        showTakenHistory = defaultExpanded
    }

    private func deleteDoseFromPlan(_ dose: TodayDose) {
        guard let updatedPlan = appStore.deleteMedication(planId: dose.planId, medicationId: dose.medicationId) else {
            return
        }

        if viewingDose?.id == dose.id {
            viewingDose = nil
        }

        Task {
            NotificationService.shared.cancelNotifications(for: updatedPlan.id)
            let notificationsEnabled = await NotificationService.shared.notificationsEnabled()
            guard notificationsEnabled else { return }

            do {
                _ = try await NotificationService.shared.scheduleNotifications(for: updatedPlan)
            } catch {
                Logger.error("Failed to reschedule notifications after medication deletion.")
            }
        }
    }
}

private struct TodayDoseDetailView: View {
    let dose: TodayDose

    private var storageText: String {
        let filtered = dose.storage.filter { $0 != .unknown }.map(\.displayName)
        return filtered.isEmpty ? "No specific storage requirements." : filtered.joined(separator: ", ")
    }

    private var notesText: String {
        let filtered = dose.notes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return filtered.isEmpty ? "No additional instructions." : filtered.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Dose") {
                    infoRow(title: "Medication", value: dose.medicationName)
                    infoRow(title: "Time", value: DateTimeUtils.formatDisplayTime(dose.date))
                    infoRow(title: "Dose", value: dose.dose)
                    infoRow(title: "Route", value: dose.route.displayName)
                }

                Section("Instructions") {
                    infoRow(title: "Food timing", value: dose.foodTiming.displayName)
                    infoRow(title: "Storage", value: storageText)
                    Text(notesText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                }
            }
            .navigationTitle("Medication Detail")
            .navigationBarTitleDisplayMode(.inline)
        }
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

private struct CompactColorCalendarView: View {
    @Binding var displayedMonth: Date
    @Binding var selectedDate: Date
    let dayDots: (Date) -> [CalendarDot]

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 10) {
            monthHeader
            weekdayHeader
            dayGrid
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    private var monthHeader: some View {
        HStack(spacing: 8) {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(orderedWeekdaySymbols, id: \.self) { symbol in
                Text(symbol.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var dayGrid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(monthDayCells.enumerated()), id: \.offset) { _, day in
                if let date = day {
                    dayCell(for: date)
                } else {
                    Color.clear
                        .frame(height: 34)
                }
            }
        }
    }

    private func dayCell(for date: Date) -> some View {
        let day = calendar.component(.day, from: date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let dots = Array(dayDots(calendar.startOfDay(for: date)).prefix(2))

        return Button {
            selectedDate = calendar.startOfDay(for: date)
            displayedMonth = DateTimeUtils.startOfMonth(for: date)
        } label: {
            VStack(spacing: 3) {
                Text("\(day)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .frame(width: 30, height: 30)
                    .background {
                        if isSelected {
                            Circle().fill(Color.accentColor)
                        } else if isToday {
                            Circle().stroke(Color.accentColor.opacity(0.42), lineWidth: 1.2)
                        }
                    }

                HStack(spacing: 3) {
                    ForEach(Array(dots.enumerated()), id: \.offset) { _, dot in
                        Circle()
                            .fill(dot.color)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var monthDayCells: [Date?] {
        let monthStart = DateTimeUtils.startOfMonth(for: displayedMonth)
        guard let dayRange = calendar.range(of: .day, in: .month, for: monthStart) else {
            return Array(repeating: nil, count: 42)
        }

        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingPadding = (firstWeekday - calendar.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leadingPadding)
        cells.append(contentsOf: dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: monthStart)
        })

        while cells.count < 42 {
            cells.append(nil)
        }

        return Array(cells.prefix(42))
    }

    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let first = max(calendar.firstWeekday - 1, 0)
        let leading = Array(symbols[first..<symbols.count])
        let trailing = Array(symbols[0..<first])
        return leading + trailing
    }

    private func shiftMonth(by value: Int) {
        guard let shifted = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        displayedMonth = DateTimeUtils.startOfMonth(for: shifted)
    }
}
