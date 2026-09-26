import Foundation

struct RAGChunk: Codable, Identifiable {
    let documentID: UUID
    let fileName: String
    let category: String
    let documentType: String
    let text: String
    let chunkIndex: Int

    var id: String {
        "\(documentID.uuidString)-\(chunkIndex)"
    }
}

private struct PersistedRAGIndex: Codable {
    let version: Int
    var indexedDocumentIDs: Set<UUID>
    var chunks: [RAGChunk]
}

@MainActor
final class LocalRAGIndex {
    static let shared = LocalRAGIndex()

    private var indexedDocumentIDs: Set<UUID>
    private var chunks: [RAGChunk]

    private init() {
        if let indexURL = try? Self.indexURL(),
           let data = try? Data(contentsOf: indexURL),
           let index = try? JSONDecoder().decode(PersistedRAGIndex.self, from: data),
           index.version == 1 {
            indexedDocumentIDs = index.indexedDocumentIDs
            chunks = index.chunks
        } else {
            indexedDocumentIDs = []
            chunks = []
        }
    }

    func index(document: Document, fullText: String) throws {
        replaceChunks(for: document, fullText: fullText)
        try persist()
    }

    @discardableResult
    func indexMissingDocuments(from documents: [Document]) async throws -> Int {
        var indexedCount = 0

        for document in documents where !indexedDocumentIDs.contains(document.id) {
            var fullText = document.extractedText

            if let url = document.iCloudURL {
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                if let extractedText = try? await PDFTextExtractor.extractText(from: url) {
                    fullText = extractedText
                }
            }

            replaceChunks(for: document, fullText: fullText)
            indexedCount += 1
        }

        if indexedCount > 0 {
            try persist()
        }
        return indexedCount
    }

    func search(question: String, documentIDs: Set<UUID>, limit: Int = 6) -> [RAGChunk] {
        let terms = Set(question.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 })
        guard !terms.isEmpty else { return [] }

        return chunks
            .filter { documentIDs.contains($0.documentID) }
            .compactMap { chunk -> (RAGChunk, Int)? in
                let contentTerms = chunk.text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
                let nameTerms = chunk.fileName.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
                let categoryTerms = chunk.category.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
                let typeTerms = chunk.documentType.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)

                let score = terms.reduce(into: 0) { total, term in
                    total += contentTerms.filter { $0 == term }.count
                    total += 3 * nameTerms.filter { $0 == term }.count
                    total += 2 * categoryTerms.filter { $0 == term }.count
                    total += 2 * typeTerms.filter { $0 == term }.count
                }
                return score > 0 ? (chunk, score) : nil
            }
            .sorted {
                if $0.1 == $1.1 {
                    return $0.0.id < $1.0.id
                }
                return $0.1 > $1.1
            }
            .prefix(limit)
            .map(\.0)
    }

    private func replaceChunks(for document: Document, fullText: String) {
        chunks.removeAll { $0.documentID == document.id }

        let sourceText = [document.summary, fullText]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
        let characters = Array(sourceText)
        let chunkSize = 1200
        let overlap = 180
        var start = 0
        var chunkIndex = 0

        while start < characters.count {
            let end = min(start + chunkSize, characters.count)
            let text = String(characters[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                chunks.append(
                    RAGChunk(
                        documentID: document.id,
                        fileName: document.originalFileName,
                        category: document.category,
                        documentType: document.documentType,
                        text: text,
                        chunkIndex: chunkIndex
                    )
                )
                chunkIndex += 1
            }
            if end == characters.count { break }
            start = end - overlap
        }

        indexedDocumentIDs.insert(document.id)
    }

    private func persist() throws {
        let indexURL = try Self.indexURL()
        let index = PersistedRAGIndex(version: 1, indexedDocumentIDs: indexedDocumentIDs, chunks: chunks)
        let data = try JSONEncoder().encode(index)
        try data.write(to: indexURL, options: .atomic)
    }

    private static func indexURL() throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent("DocAI", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("RAGIndex.json")
    }
}