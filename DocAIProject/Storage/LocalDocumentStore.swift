import Foundation

enum DocumentStoreError: Error {
    case cannotCreateDirectory
}

enum DocumentStoragePath {
    static func folderComponents(from suggestedPath: String) -> [String] {
        suggestedPath.split(separator: "/").compactMap { rawComponent in
            let component = String(rawComponent)
                .replacingOccurrences(of: "\\", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .trimmingCharacters(in: CharacterSet(charactersIn: " .\t\n\r"))
            guard !component.isEmpty, component != ".", component != ".." else { return nil }
            return String(component.prefix(100))
        }
    }
}

struct LocalDocumentStore: DocumentStorageBackend {
    var isReadyForWrites: Bool { true }

    func listFiles() async throws -> [StoredPDF] {
        let directory = try Self.documentsDirectory()
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var pdfs = [StoredPDF]()
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension.lowercased() == "pdf" else { continue }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values.isRegularFile == true else { continue }
            pdfs.append(StoredPDF(
                id: url.standardizedFileURL.path,
                name: url.lastPathComponent,
                modifiedAt: values.contentModificationDate,
                localURL: url,
                remoteID: nil
            ))
        }

        return pdfs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func savePDF(fileAt url: URL, suggestedPath: String, originalName: String) async throws -> StoredPDFLocation {
        let localURL = try Self.copy(fileAt: url, suggestedPath: suggestedPath, originalName: originalName)
        return StoredPDFLocation(localURL: localURL, remoteID: nil)
    }

    func deletePDF(at location: StoredPDFLocation) async throws {
        if let localURL = location.localURL {
            try FileManager.default.removeItem(at: localURL)
        }
    }

    static func documentsDirectory() throws -> URL {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        guard let documents = urls.first else {
            throw DocumentStoreError.cannotCreateDirectory
        }
        return documents
    }

    static func folderURL(for suggestedPath: String) throws -> URL {
        var folder = try documentsDirectory()
        for component in DocumentStoragePath.folderComponents(from: suggestedPath) {
            folder.appendPathComponent(component, isDirectory: true)
        }
        return folder
    }

    static func copy(fileAt sourceURL: URL, suggestedPath: String, originalName: String) throws -> URL {
        let folder = try folderURL(for: suggestedPath)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var destination = folder.appendingPathComponent(originalName)
        if FileManager.default.fileExists(atPath: destination.path) {
            let name = (originalName as NSString).deletingPathExtension
            let ext = (originalName as NSString).pathExtension
            let uniqueName = ext.isEmpty
                ? "\(name)-\(UUID().uuidString.prefix(6))"
                : "\(name)-\(UUID().uuidString.prefix(6)).\(ext)"
            destination = folder.appendingPathComponent(uniqueName)
        }

        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }
}