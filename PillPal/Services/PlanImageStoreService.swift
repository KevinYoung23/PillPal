import Foundation
import UIKit

final class PlanImageStoreService {
    static let shared = PlanImageStoreService()

    private let fileManager: FileManager
    private let baseDirectoryURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let pillPalDirectory = appSupport.appendingPathComponent("PillPal", isDirectory: true)
        let imagesDirectory = pillPalDirectory.appendingPathComponent("PlanImages", isDirectory: true)
        self.baseDirectoryURL = imagesDirectory

        if !fileManager.fileExists(atPath: imagesDirectory.path) {
            try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        }
    }

    func store(images: [UIImage], planId: UUID) -> [String] {
        guard !images.isEmpty else { return [] }

        let planFolder = baseDirectoryURL.appendingPathComponent(planId.uuidString, isDirectory: true)
        if !fileManager.fileExists(atPath: planFolder.path) {
            do {
                try fileManager.createDirectory(at: planFolder, withIntermediateDirectories: true)
            } catch {
                Logger.error("Failed to create local image folder.")
                return []
            }
        }

        var storedPaths: [String] = []
        for image in images {
            let filename = UUID().uuidString + ".jpg"
            let fileURL = planFolder.appendingPathComponent(filename)
            let relativePath = planId.uuidString + "/" + filename

            guard let data = image.jpegData(compressionQuality: 0.92) ?? image.pngData() else {
                continue
            }

            do {
                try data.write(to: fileURL, options: .atomic)
                storedPaths.append(relativePath)
            } catch {
                Logger.error("Failed to persist local plan image.")
            }
        }

        return storedPaths
    }

    func loadImage(relativePath: String) -> UIImage? {
        UIImage(contentsOfFile: absoluteURL(for: relativePath).path)
    }

    func removeImageFiles(relativePaths: [String]) {
        for relativePath in relativePaths {
            let fileURL = absoluteURL(for: relativePath)
            guard fileManager.fileExists(atPath: fileURL.path) else { continue }
            do {
                try fileManager.removeItem(at: fileURL)
            } catch {
                Logger.error("Failed to remove local plan image.")
            }
        }

        cleanupEmptyPlanFolders()
    }

    private func absoluteURL(for relativePath: String) -> URL {
        baseDirectoryURL.appendingPathComponent(relativePath)
    }

    private func cleanupEmptyPlanFolders() {
        guard let folders = try? fileManager.contentsOfDirectory(
            at: baseDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for folder in folders {
            guard let values = try? folder.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory == true
            else {
                continue
            }

            let contents = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
            if contents.isEmpty {
                try? fileManager.removeItem(at: folder)
            }
        }
    }
}
