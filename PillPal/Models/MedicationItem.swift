import Foundation

struct MedicationItem: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var dose: String
    var route: MedicationRoute
    var frequency: MedicationFrequency
    var times: [String]
    var startDate: Date
    var endDate: Date
    var withFood: FoodTiming
    var notes: [String]
    var storage: [StorageRequirement]

    init(
        id: UUID = UUID(),
        name: String,
        dose: String,
        route: MedicationRoute,
        frequency: MedicationFrequency,
        times: [String],
        startDate: Date,
        endDate: Date,
        withFood: FoodTiming,
        notes: [String],
        storage: [StorageRequirement]
    ) {
        self.id = id
        self.name = name
        self.dose = dose
        self.route = route
        self.frequency = frequency
        self.times = times
        self.startDate = startDate
        self.endDate = endDate
        self.withFood = withFood
        self.notes = notes
        self.storage = storage
    }
}

enum MedicationRoute: String, Codable, CaseIterable, Hashable {
    case oral
    case topical
    case eye
    case injection
    case other
    case unknown

    var displayName: String {
        switch self {
        case .oral: return "Oral"
        case .topical: return "Topical"
        case .eye: return "Eye"
        case .injection: return "Injection"
        case .other: return "Other"
        case .unknown: return "Unknown"
        }
    }
}

struct MedicationFrequency: Codable, Hashable {
    var type: FrequencyType
    var value: Int
}

enum FrequencyType: String, Codable, CaseIterable, Hashable {
    case timesPerDay = "times_per_day"
    case intervalHours = "interval_hours"
    case specificTimes = "specific_times"
    case unknown

    var displayName: String {
        switch self {
        case .timesPerDay: return "Times/Day"
        case .intervalHours: return "Every X Hours"
        case .specificTimes: return "Specific Times"
        case .unknown: return "Unknown"
        }
    }
}

enum FoodTiming: String, Codable, CaseIterable, Hashable {
    case beforeMeal = "before_meal"
    case afterMeal = "after_meal"
    case withMeal = "with_meal"
    case noRequirement = "no_requirement"
    case unknown

    var displayName: String {
        switch self {
        case .beforeMeal: return "Before meal"
        case .afterMeal: return "After meal"
        case .withMeal: return "With meal"
        case .noRequirement: return "No requirement"
        case .unknown: return "Unknown"
        }
    }

    var offsetMinutes: Int {
        switch self {
        case .beforeMeal: return -15
        case .afterMeal: return 30
        case .withMeal, .noRequirement, .unknown: return 0
        }
    }
}

enum StorageRequirement: String, Codable, CaseIterable, Hashable {
    case refrigerate
    case avoidLight = "avoid_light"
    case roomTemp = "room_temp"
    case shakeWell = "shake_well"
    case unknown

    var displayName: String {
        switch self {
        case .refrigerate: return "Refrigerate"
        case .avoidLight: return "Avoid light"
        case .roomTemp: return "Room temp"
        case .shakeWell: return "Shake well"
        case .unknown: return "Unknown"
        }
    }
}
