import Foundation

enum DocumentStoreError: Error {
    case cannotCreateDirectory
    case moveFailed
}

struct ICloudDocumentStore {
    /// Local Documents directory inside the app sandbox
    static func documentsDirectory() throws -> URL {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        guard let docs = urls.first else {
            throw DocumentStoreError.cannotCreateDirectory
        }
        return docs
    }

    /// Copies the source file into the app’s Documents folder under the suggested path
    static func move(fileAt sourceURL: URL, suggestedPath: String, originalName: String) throws -> URL {
        let base = try documentsDirectory()
        let folder = base.appendingPathComponent(suggestedPath, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var finalDestination = folder.appendingPathComponent(originalName)

        // Avoid overwriting
        if FileManager.default.fileExists(atPath: finalDestination.path) {
            let name = (originalName as NSString).deletingPathExtension
            let ext = (originalName as NSString).pathExtension
            finalDestination = folder.appendingPathComponent("\(name)-\(UUID().uuidString.prefix(6)).\(ext)")
        }

        // Copy instead of setUbiquitous
        try FileManager.default.copyItem(at: sourceURL, to: finalDestination)
        return finalDestination
    }
}
