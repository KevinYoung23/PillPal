import Foundation

struct PersistedState: Codable {
    var plans: [MedicationPlan]
    var completedDoseIDs: Set<String>
    var doseOverrides: [String: DoseOverride]

    static let empty = PersistedState(plans: [], completedDoseIDs: [], doseOverrides: [:])

    init(plans: [MedicationPlan], completedDoseIDs: Set<String>, doseOverrides: [String: DoseOverride]) {
        self.plans = plans
        self.completedDoseIDs = completedDoseIDs
        self.doseOverrides = doseOverrides
    }

    enum CodingKeys: String, CodingKey {
        case plans
        case completedDoseIDs
        case doseOverrides
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.plans = try container.decodeIfPresent([MedicationPlan].self, forKey: .plans) ?? []
        self.completedDoseIDs = try container.decodeIfPresent(Set<String>.self, forKey: .completedDoseIDs) ?? []
        self.doseOverrides = try container.decodeIfPresent([String: DoseOverride].self, forKey: .doseOverrides) ?? [:]
    }
}

final class StorageService {
    private let fileManager: FileManager
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folderURL = appSupport.appendingPathComponent("PillPal", isDirectory: true)
        if !fileManager.fileExists(atPath: folderURL.path) {
            try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        self.fileURL = folderURL.appendingPathComponent("pillpal_state.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadState() -> PersistedState {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let state = try? decoder.decode(PersistedState.self, from: data)
        else {
            return .empty
        }
        return state
    }

    func saveState(_ state: PersistedState) {
        do {
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Logger.error("Failed to persist app state.")
        }
    }
}
