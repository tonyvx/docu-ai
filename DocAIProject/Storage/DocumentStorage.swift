import Foundation

enum PersistenceLayer: String, CaseIterable, Identifiable {
    case local
    case googleDrive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: "Local"
        case .googleDrive: "Google Drive"
        }
    }

    @MainActor
    var store: any DocumentStorageBackend {
        switch self {
        case .local: LocalDocumentStore()
        case .googleDrive: GoogleDriveDocumentStore.shared
        }
    }
}

struct StoredPDF: Identifiable, Hashable {
    let id: String
    let name: String
    let modifiedAt: Date?
    let localURL: URL?
    let remoteID: String?
}

struct StoredPDFLocation {
    let localURL: URL?
    let remoteID: String?
}

@MainActor
protocol DocumentStorageBackend {
    var isReadyForWrites: Bool { get }

    func listFiles() async throws -> [StoredPDF]
    func localURL(for file: StoredPDF) async throws -> URL
    func savePDF(fileAt url: URL, suggestedPath: String, originalName: String) async throws -> StoredPDFLocation
    func renamePDF(at location: StoredPDFLocation, to newName: String) async throws -> StoredPDFLocation
    func deletePDF(at location: StoredPDFLocation) async throws
}