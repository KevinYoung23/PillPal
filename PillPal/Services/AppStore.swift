import Foundation
import Combine

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var plans: [MedicationPlan]
    @Published private(set) var completedDoseIDs: Set<String>
    @Published private(set) var doseOverrides: [String: DoseOverride]

    private let storageService: StorageService

    init(storageService: StorageService? = nil) {
        let resolvedStorage = storageService ?? StorageService()
        self.storageService = resolvedStorage
        let state = resolvedStorage.loadState()
        self.plans = state.plans
        self.completedDoseIDs = state.completedDoseIDs
        self.doseOverrides = state.doseOverrides
    }

    func reload() {
        let state = storageService.loadState()
        plans = state.plans
        completedDoseIDs = state.completedDoseIDs
        doseOverrides = state.doseOverrides
    }

    func addPlan(_ plan: MedicationPlan) {
        plans.insert(plan, at: 0)
        persist()
    }

    func plan(by id: UUID) -> MedicationPlan? {
        plans.first(where: { $0.id == id })
    }

    @discardableResult
    func updatePlan(_ updatedPlan: MedicationPlan) -> Bool {
        guard let index = plans.firstIndex(where: { $0.id == updatedPlan.id }) else {
            return false
        }
        let previousImagePaths = Set(plans[index].storedInstructionImagePaths)
        let nextImagePaths = Set(updatedPlan.storedInstructionImagePaths)
        let removedImagePaths = previousImagePaths.subtracting(nextImagePaths)

        plans[index] = updatedPlan
        completedDoseIDs = completedDoseIDs.filter { !$0.hasPrefix(updatedPlan.id.uuidString) }
        doseOverrides = doseOverrides.filter { !isDoseIdentifier($0.key, withinPlanId: updatedPlan.id) }

        if !removedImagePaths.isEmpty {
            PlanImageStoreService.shared.removeImageFiles(relativePaths: Array(removedImagePaths))
        }
        persist()
        return true
    }

    func deletePlan(_ planId: UUID) {
        if let planToDelete = plan(by: planId) {
            PlanImageStoreService.shared.removeImageFiles(relativePaths: planToDelete.storedInstructionImagePaths)
        }
        plans.removeAll { $0.id == planId }
        completedDoseIDs = completedDoseIDs.filter { !$0.hasPrefix(planId.uuidString) }
        doseOverrides = doseOverrides.filter { !isDoseIdentifier($0.key, withinPlanId: planId) }
        persist()
    }

    func markDoseTaken(_ doseId: String) {
        completedDoseIDs.insert(doseId)
        persist()
    }

    func unmarkDoseTaken(_ doseId: String) {
        completedDoseIDs.remove(doseId)
        persist()
    }

    func isDoseCompleted(_ doseId: String) -> Bool {
        completedDoseIDs.contains(doseId)
    }

    func medicationItem(planId: UUID, medicationId: UUID) -> MedicationItem? {
        guard let plan = plans.first(where: { $0.id == planId }) else { return nil }
        return plan.medications.first(where: { $0.id == medicationId })
    }

    @discardableResult
    func deleteMedication(planId: UUID, medicationId: UUID) -> MedicationPlan? {
        guard let planIndex = plans.firstIndex(where: { $0.id == planId }) else {
            return nil
        }

        guard plans[planIndex].medications.contains(where: { $0.id == medicationId }) else {
            return nil
        }

        plans[planIndex].medications.removeAll { $0.id == medicationId }

        completedDoseIDs = completedDoseIDs.filter { key in
            !isDoseIdentifier(key, withinPlanId: planId, medicationId: medicationId)
        }
        doseOverrides = doseOverrides.filter { key, _ in
            !isDoseIdentifier(key, withinPlanId: planId, medicationId: medicationId)
        }

        persist()
        return plans[planIndex]
    }

    func applySingleArrangementEdit(
        dose: TodayDose,
        newDose: String,
        newTimeText: String
    ) {
        doseOverrides[dose.id] = DoseOverride(
            dose: newDose.trimmingCharacters(in: .whitespacesAndNewlines),
            timeText: newTimeText
        )
        persist()
    }

    func applyFutureArrangementEdit(
        dose: TodayDose,
        newDose: String,
        newTimeText: String
    ) -> MedicationPlan? {
        let trimmedDose = newDose.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let planIndex = plans.firstIndex(where: { $0.id == dose.planId }),
              let medicationIndex = plans[planIndex].medications.firstIndex(where: { $0.id == dose.medicationId })
        else {
            return nil
        }

        plans[planIndex].medications[medicationIndex].dose = trimmedDose

        var times = plans[planIndex].medications[medicationIndex].times
        if let targetIndex = times.firstIndex(of: dose.baseTimeText) {
            times[targetIndex] = newTimeText
        } else if let displayIndex = times.firstIndex(of: dose.timeText) {
            times[displayIndex] = newTimeText
        } else {
            times.append(newTimeText)
        }
        plans[planIndex].medications[medicationIndex].times = Array(Set(times)).sorted()

        doseOverrides = doseOverrides.filter { key, _ in
            !isDoseIdentifier(key, withinPlanId: dose.planId, medicationId: dose.medicationId)
        }

        persist()
        return plans[planIndex]
    }

    func todaySchedule(referenceDate: Date = Date()) -> [TodayDose] {
        let startOfDay = Calendar.current.startOfDay(for: referenceDate)

        let doses: [TodayDose] = plans.flatMap { plan -> [TodayDose] in
            plan.medications.flatMap { medication -> [TodayDose] in
                guard medication.startDate <= startOfDay,
                      medication.endDate >= startOfDay
                else {
                    return []
                }

                return medication.times.compactMap { time in
                    let baseIdentifier = DateTimeUtils.makeNotificationIdentifier(
                        planId: plan.id,
                        medicationId: medication.id,
                        day: startOfDay,
                        time: time
                    )
                    let override = doseOverrides[baseIdentifier]
                    let effectiveTime = override?.timeText ?? time
                    let effectiveDose = override?.dose ?? medication.dose

                    guard let triggerDate = DateTimeUtils.dateAndTime(day: startOfDay, time: time) else {
                        return nil
                    }

                    let effectiveTriggerDate = DateTimeUtils.dateAndTime(day: startOfDay, time: effectiveTime) ?? triggerDate

                    return TodayDose(
                        id: baseIdentifier,
                        planId: plan.id,
                        medicationId: medication.id,
                        medicationName: medication.name,
                        dose: effectiveDose,
                        route: medication.route,
                        foodTiming: medication.withFood,
                        storage: medication.storage,
                        notes: medication.notes,
                        date: effectiveTriggerDate,
                        baseTimeText: time,
                        timeText: effectiveTime,
                        isCompleted: completedDoseIDs.contains(baseIdentifier)
                    )
                }
            }
        }

        return doses.sorted { $0.date < $1.date }
    }

    private func persist() {
        storageService.saveState(
            PersistedState(
                plans: plans,
                completedDoseIDs: completedDoseIDs,
                doseOverrides: doseOverrides
            )
        )
    }

    private func isDoseIdentifier(_ identifier: String, withinPlanId planId: UUID, medicationId: UUID? = nil) -> Bool {
        let parts = identifier.split(separator: "_")
        guard parts.count >= 4,
              let parsedPlanId = UUID(uuidString: String(parts[0]))
        else {
            return false
        }
        if parsedPlanId != planId { return false }

        if let medicationId {
            guard let parsedMedicationId = UUID(uuidString: String(parts[1])) else {
                return false
            }
            return parsedMedicationId == medicationId
        }

        return true
    }
}
