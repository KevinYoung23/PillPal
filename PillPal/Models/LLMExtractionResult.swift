import Foundation

struct LLMExtractionResult: Codable {
    var medications: [LLMMedication]
    var followUp: [LLMFollowUp]
    var uncertainties: [LLMUncertainty]

    enum CodingKeys: String, CodingKey {
        case medications
        case followUp = "follow_up"
        case uncertainties
    }
}

struct LLMMedication: Codable {
    var name: String
    var dose: String
    var route: MedicationRoute
    var frequency: MedicationFrequency
    var times: [String]
    var startDate: String
    var endDate: String
    var withFood: FoodTiming
    var notes: [String]
    var storage: [StorageRequirement]

    enum CodingKeys: String, CodingKey {
        case name
        case dose
        case route
        case frequency
        case times
        case startDate = "start_date"
        case endDate = "end_date"
        case withFood = "with_food"
        case notes
        case storage
    }
}

struct LLMFollowUp: Codable {
    var date: String
    var notes: String
}

struct LLMUncertainty: Codable {
    var path: String
    var reason: String
    var candidates: [String]
}
