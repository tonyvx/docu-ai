import Foundation

enum DocumentStoreError: LocalizedError {
    case cannotCreateDirectory
    case fileAlreadyExists
    case missingLocalFile

    var errorDescription: String? {
        switch self {
        case .cannotCreateDirectory: "The local document folder is unavailable."
        case .fileAlreadyExists: "A file with that name already exists in this folder."
        case .missingLocalFile: "The local PDF file could not be located."
        }
    }
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

    func localURL(for file: StoredPDF) async throws -> URL {
        guard let url = file.localURL, FileManager.default.fileExists(atPath: url.path) else {
            throw DocumentStoreError.missingLocalFile
        }
        return url
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

    func renamePDF(at location: StoredPDFLocation, to newName: String) async throws -> StoredPDFLocation {
        guard let localURL = location.localURL else { throw DocumentStoreError.missingLocalFile }
        let renamedURL = try Self.rename(fileAt: localURL, to: newName)
        return StoredPDFLocation(localURL: renamedURL, remoteID: nil)
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

    static func rename(fileAt sourceURL: URL, to newName: String) throws -> URL {
        let destination = sourceURL.deletingLastPathComponent().appendingPathComponent(newName)
        if destination.standardizedFileURL == sourceURL.standardizedFileURL {
            return sourceURL
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw DocumentStoreError.fileAlreadyExists
        }
        try FileManager.default.moveItem(at: sourceURL, to: destination)
        return destination
    }

    static func cacheDownloadedPDF(_ data: Data, fileID: String) throws -> URL {
        guard let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw DocumentStoreError.cannotCreateDirectory
        }
        let folder = cachesDirectory
            .appendingPathComponent("DocAI", isDirectory: true)
            .appendingPathComponent("DrivePreviews", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let safeFileID = fileID.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "_"
        }
        let destination = folder.appendingPathComponent("\(String(safeFileID)).pdf")
        try data.write(to: destination, options: .atomic)
        return destination
    }

    static func isDrivePreviewCache(_ url: URL) -> Bool {
        guard let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return false
        }
        let previewDirectory = cachesDirectory
            .appendingPathComponent("DocAI", isDirectory: true)
            .appendingPathComponent("DrivePreviews", isDirectory: true)
        return url.standardizedFileURL.path.hasPrefix(previewDirectory.standardizedFileURL.path + "/")
    }
}