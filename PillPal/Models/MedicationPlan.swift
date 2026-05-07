import Foundation

struct MedicationPlan: Identifiable, Codable, Hashable {
    var id: UUID
    var createdAt: Date
    var sourceOCRText: String
    var sourceInstructionImagePaths: [String]?
    var medications: [MedicationItem]
    var followUp: [FollowUpItem]
    var uncertainties: [ExtractionUncertainty]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        sourceOCRText: String,
        sourceInstructionImagePaths: [String] = [],
        medications: [MedicationItem],
        followUp: [FollowUpItem],
        uncertainties: [ExtractionUncertainty]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceOCRText = sourceOCRText
        self.sourceInstructionImagePaths = sourceInstructionImagePaths
        self.medications = medications
        self.followUp = followUp
        self.uncertainties = uncertainties
    }

    var storedInstructionImagePaths: [String] {
        sourceInstructionImagePaths ?? []
    }
}

struct FollowUpItem: Codable, Hashable, Identifiable {
    var id: UUID
    var date: Date
    var notes: String

    init(id: UUID = UUID(), date: Date, notes: String) {
        self.id = id
        self.date = date
        self.notes = notes
    }
}

struct ExtractionUncertainty: Codable, Hashable, Identifiable {
    var id: UUID
    var path: String
    var reason: String
    var candidates: [String]

    init(id: UUID = UUID(), path: String, reason: String, candidates: [String]) {
        self.id = id
        self.path = path
        self.reason = reason
        self.candidates = candidates
    }
}

struct TodayDose: Identifiable, Hashable {
    var id: String
    var planId: UUID
    var medicationId: UUID
    var medicationName: String
    var dose: String
    var route: MedicationRoute
    var foodTiming: FoodTiming
    var storage: [StorageRequirement]
    var notes: [String]
    var date: Date
    var baseTimeText: String
    var timeText: String
    var isCompleted: Bool
}

struct DoseOverride: Codable, Hashable {
    var dose: String
    var timeText: String
}
