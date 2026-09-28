import Foundation
import SwiftData

@Model
final class Document {
    var id: UUID
    var originalFileName: String
    @Attribute(originalName: "iCloudURL") var localFileURL: URL?
    var googleDriveFileID: String?
    var category: String
    var documentType: String
    var documentDate: Date?
    var summary: String
    var suggestedPath: String
    var extractedText: String              // keep a reasonable excerpt for RAG
    var createdAt: Date
    var spotlightIdentifier: String

    init(
        originalFileName: String,
        category: String = "Insurance",
        documentType: String = "",
        documentDate: Date? = nil,
        summary: String = "",
        suggestedPath: String = "",
        extractedText: String = ""
    ) {
        let newID = UUID()
        
        self.id = newID
        self.originalFileName = originalFileName
        self.googleDriveFileID = nil
        self.localFileURL = nil
        self.category = category
        self.documentType = documentType
        self.documentDate = documentDate
        self.summary = summary
        self.suggestedPath = suggestedPath
        self.extractedText = extractedText
        self.createdAt = Date()
        self.spotlightIdentifier = "docai.\(newID.uuidString)"
    }
}
