import Foundation
import NaturalLanguage
import SQLite3

struct RAGChunk: Identifiable {
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

private enum LocalRAGIndexError: LocalizedError {
    case databaseUnavailable
    case sqlite(String)
    case embeddingUnavailable
    case embeddingAssetsUnavailable
    case invalidVector

    var errorDescription: String? {
        switch self {
        case .databaseUnavailable:
            return "The local document search database is unavailable."
        case .sqlite(let message):
            return "The local document search database failed: \(message)"
        case .embeddingUnavailable:
            return "The on-device English embedding model could not be created."
        case .embeddingAssetsUnavailable:
            return "The on-device English embedding assets are unavailable. Connect to the internet and try again."
        case .invalidVector:
            return "A stored document embedding could not be read."
        }
    }
}

@MainActor
final class LocalRAGIndex {
    static let shared = LocalRAGIndex()

    private let embeddingModel = NLContextualEmbedding(language: .english)
    private var database: OpaquePointer?
    private var isEmbeddingModelLoaded = false

    private var embeddingModelID: String {
        guard let embeddingModel else { return "contextual-english-unavailable" }
        return "\(embeddingModel.modelIdentifier)-\(embeddingModel.revision)"
    }

    private init() {
        do {
            try openDatabase()
        } catch {
            print("Local RAG database could not be opened: \(error.localizedDescription)")
        }
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func index(document: Document, fullText: String) async throws {
        try await prepareEmbeddingModel()
        let texts = makeChunks(summary: document.summary, fullText: fullText)
        let embeddedChunks = texts.enumerated().compactMap { index, text -> (Int, String, [Double])? in
            guard let vector = vector(for: text) else { return nil }
            return (index, text, vector)
        }
        guard !embeddedChunks.isEmpty else {
            throw LocalRAGIndexError.embeddingUnavailable
        }

        try withDatabase { database in
            try execute("BEGIN IMMEDIATE TRANSACTION", on: database)
            do {
                try deleteDocument(document.id, from: database)
                for (index, text, vector) in embeddedChunks {
                    try insertChunk(
                        text: text,
                        vector: vector,
                        index: index,
                        document: document,
                        into: database
                    )
                }
                try markIndexed(document.id, in: database)
                try execute("COMMIT", on: database)
            } catch {
                try? execute("ROLLBACK", on: database)
                throw error
            }
        }
    }

    func updateMetadata(for documents: [Document]) throws {
        guard !documents.isEmpty else { return }

        try withDatabase { database in
            try execute("BEGIN IMMEDIATE TRANSACTION", on: database)
            do {
                for document in documents {
                    let statement = try prepare(
                        "UPDATE rag_chunks SET file_name = ?, category = ?, document_type = ? WHERE document_id = ?",
                        on: database
                    )
                    defer { sqlite3_finalize(statement) }
                    try bind(document.originalFileName, at: 1, to: statement, on: database)
                    try bind(document.category, at: 2, to: statement, on: database)
                    try bind(document.documentType, at: 3, to: statement, on: database)
                    try bind(document.id.uuidString, at: 4, to: statement, on: database)
                    try step(statement, on: database)
                }
                try execute("COMMIT", on: database)
            } catch {
                try? execute("ROLLBACK", on: database)
                throw error
            }
        }
    }

    @discardableResult
    func indexMissingDocuments(from documents: [Document]) async throws -> Int {
        try await prepareEmbeddingModel()
        let indexedIDs = try indexedDocumentIDs()
        var indexedCount = 0

        for document in documents where !indexedIDs.contains(document.id) {
            let fullText = await extractedText(for: document)
            try await index(document: document, fullText: fullText)
            indexedCount += 1
        }
        return indexedCount
    }

    func search(question: String, documentIDs: Set<UUID>, limit: Int = 6) async throws -> [RAGChunk] {
        try await prepareEmbeddingModel()
        let queryVector = vector(for: question)
        let queryTerms = Set(tokens(in: question).filter { $0.count > 2 })
        guard !queryTerms.isEmpty || queryVector != nil else { return [] }

        return try withDatabase { database in
            let statement = try prepare(
                """
                SELECT document_id, file_name, category, document_type, text, chunk_index, embedding_json
                FROM rag_chunks
                WHERE embedding_model = ?
                """,
                on: database
            )
            defer { sqlite3_finalize(statement) }
            try bind(embeddingModelID, at: 1, to: statement, on: database)

            var ranked: [(chunk: RAGChunk, score: Double)] = []
            while true {
                let result = sqlite3_step(statement)
                guard result == SQLITE_ROW || result == SQLITE_DONE else {
                    throw LocalRAGIndexError.sqlite(String(cString: sqlite3_errmsg(database)))
                }
                guard result == SQLITE_ROW else { break }

                guard let idText = columnText(0, from: statement),
                      let documentID = UUID(uuidString: idText),
                      documentIDs.contains(documentID),
                      let fileName = columnText(1, from: statement),
                      let category = columnText(2, from: statement),
                      let documentType = columnText(3, from: statement),
                      let text = columnText(4, from: statement),
                      let vectorJSON = columnText(6, from: statement),
                      let vectorData = vectorJSON.data(using: .utf8),
                      let vector = try? JSONDecoder().decode([Double].self, from: vectorData) else {
                    continue
                }

                let chunk = RAGChunk(
                    documentID: documentID,
                    fileName: fileName,
                    category: category,
                    documentType: documentType,
                    text: text,
                    chunkIndex: Int(sqlite3_column_int(statement, 5))
                )
                let passageTerms = Set(tokens(in: text))
                let metadataTerms = Set(tokens(in: "\(fileName) \(category) \(documentType)"))
                let lexicalBoost =
                    Double(queryTerms.intersection(passageTerms).count) * 0.02 +
                    Double(queryTerms.intersection(metadataTerms).count) * 0.06
                let semanticScore = queryVector.map { cosineSimilarity($0, vector) } ?? 0
                ranked.append((chunk, semanticScore + lexicalBoost))
            }

            return ranked
                .sorted {
                    if $0.score == $1.score {
                        return $0.chunk.id < $1.chunk.id
                    }
                    return $0.score > $1.score
                }
                .prefix(limit)
                .map(\.chunk)
        }
    }

    private func openDatabase() throws {
        let url = try Self.databaseURL()
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open database file."
            if let handle {
                sqlite3_close(handle)
            }
            throw LocalRAGIndexError.sqlite(message)
        }

        database = handle
        sqlite3_busy_timeout(handle, 3_000)
        try execute("PRAGMA journal_mode = WAL", on: handle)
        try execute(
            """
            CREATE TABLE IF NOT EXISTS rag_chunks (
                document_id TEXT NOT NULL,
                chunk_index INTEGER NOT NULL,
                file_name TEXT NOT NULL,
                category TEXT NOT NULL,
                document_type TEXT NOT NULL,
                text TEXT NOT NULL,
                embedding_model TEXT NOT NULL,
                embedding_json TEXT NOT NULL,
                PRIMARY KEY (document_id, chunk_index)
            );
            CREATE INDEX IF NOT EXISTS rag_chunks_model_idx ON rag_chunks(embedding_model);
            CREATE TABLE IF NOT EXISTS rag_indexed_documents (
                document_id TEXT PRIMARY KEY,
                embedding_model TEXT NOT NULL
            );
            """,
            on: handle
        )
        removeLegacyJSONIndex(in: url.deletingLastPathComponent())
    }

    private func removeLegacyJSONIndex(in directory: URL) {
        let legacyIndexURL = directory.appendingPathComponent("RAGIndex.json")
        guard FileManager.default.fileExists(atPath: legacyIndexURL.path) else { return }

        do {
            try FileManager.default.removeItem(at: legacyIndexURL)
        } catch {
            print("Legacy keyword RAG index could not be removed: \(error.localizedDescription)")
        }
    }

    private func indexedDocumentIDs() throws -> Set<UUID> {
        try withDatabase { database in
            let statement = try prepare(
                "SELECT document_id FROM rag_indexed_documents WHERE embedding_model = ?",
                on: database
            )
            defer { sqlite3_finalize(statement) }
            try bind(embeddingModelID, at: 1, to: statement, on: database)

            var ids = Set<UUID>()
            while true {
                let result = sqlite3_step(statement)
                guard result == SQLITE_ROW || result == SQLITE_DONE else {
                    throw LocalRAGIndexError.sqlite(String(cString: sqlite3_errmsg(database)))
                }
                guard result == SQLITE_ROW else { break }

                if let value = columnText(0, from: statement), let id = UUID(uuidString: value) {
                    ids.insert(id)
                }
            }
            return ids
        }
    }

    private func extractedText(for document: Document) async -> String {
        guard let url = document.localFileURL else {
            return document.extractedText
        }

        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return (try? await PDFTextExtractor.extractText(from: url)) ?? document.extractedText
    }

    private func makeChunks(summary: String, fullText: String) -> [String] {
        let sourceText = [summary, fullText]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
        let characters = Array(sourceText)
        let chunkSize = 1_000
        let overlap = 150
        var chunks: [String] = []
        var start = 0

        while start < characters.count {
            let end = min(start + chunkSize, characters.count)
            let text = String(characters[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                chunks.append(text)
            }
            if end == characters.count { break }
            start = end - overlap
        }
        return chunks
    }

    private func insertChunk(
        text: String,
        vector: [Double],
        index: Int,
        document: Document,
        into database: OpaquePointer
    ) throws {
        let statement = try prepare(
            """
            INSERT INTO rag_chunks (
                document_id, chunk_index, file_name, category, document_type,
                text, embedding_model, embedding_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            on: database
        )
        defer { sqlite3_finalize(statement) }

        let vectorJSON = try JSONEncoder().encode(vector)
        guard let encodedVector = String(data: vectorJSON, encoding: .utf8) else {
            throw LocalRAGIndexError.invalidVector
        }
        try bind(document.id.uuidString, at: 1, to: statement, on: database)
        try bind(index, at: 2, to: statement, on: database)
        try bind(document.originalFileName, at: 3, to: statement, on: database)
        try bind(document.category, at: 4, to: statement, on: database)
        try bind(document.documentType, at: 5, to: statement, on: database)
        try bind(text, at: 6, to: statement, on: database)
        try bind(embeddingModelID, at: 7, to: statement, on: database)
        try bind(encodedVector, at: 8, to: statement, on: database)
        try step(statement, on: database)
    }

    private func deleteDocument(_ id: UUID, from database: OpaquePointer) throws {
        for table in ["rag_chunks", "rag_indexed_documents"] {
            let statement = try prepare("DELETE FROM \(table) WHERE document_id = ?", on: database)
            defer { sqlite3_finalize(statement) }
            try bind(id.uuidString, at: 1, to: statement, on: database)
            try step(statement, on: database)
        }
    }

    private func markIndexed(_ id: UUID, in database: OpaquePointer) throws {
        let statement = try prepare(
            "INSERT OR REPLACE INTO rag_indexed_documents (document_id, embedding_model) VALUES (?, ?)",
            on: database
        )
        defer { sqlite3_finalize(statement) }
        try bind(id.uuidString, at: 1, to: statement, on: database)
        try bind(embeddingModelID, at: 2, to: statement, on: database)
        try step(statement, on: database)
    }

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        guard let database else {
            throw LocalRAGIndexError.databaseUnavailable
        }
        return try body(database)
    }

    private func execute(_ sql: String, on database: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw LocalRAGIndexError.sqlite(message)
        }
    }

    private func prepare(_ sql: String, on database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw LocalRAGIndexError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
        return statement
    }

    private func bind(_ value: String, at index: Int32, to statement: OpaquePointer, on database: OpaquePointer) throws {
        let result = value.withCString {
            sqlite3_bind_text(statement, index, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard result == SQLITE_OK else {
            throw LocalRAGIndexError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func bind(_ value: Int, at index: Int32, to statement: OpaquePointer, on database: OpaquePointer) throws {
        guard sqlite3_bind_int(statement, index, Int32(value)) == SQLITE_OK else {
            throw LocalRAGIndexError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func step(_ statement: OpaquePointer, on database: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LocalRAGIndexError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func columnText(_ column: Int32, from statement: OpaquePointer) -> String? {
        guard let value = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: value)
    }

    private func tokens(in text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private func prepareEmbeddingModel() async throws {
        guard let embeddingModel else {
            throw LocalRAGIndexError.embeddingUnavailable
        }
        if !embeddingModel.hasAvailableAssets {
            let result = try await embeddingModel.requestAssets()
            guard result == .available else {
                throw LocalRAGIndexError.embeddingAssetsUnavailable
            }
        }
        guard !isEmbeddingModelLoaded else { return }
        try embeddingModel.load()
        isEmbeddingModelLoaded = true
    }

    private func vector(for text: String) -> [Double]? {
        guard let embeddingModel,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let result = try? embeddingModel.embeddingResult(for: text, language: .english) else {
            return nil
        }

        var vectorSum: [Double] = []
        var vectorCount = 0
        result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { tokenVector, _ in
            if vectorSum.isEmpty {
                vectorSum = Array(repeating: 0.0, count: tokenVector.count)
            }
            guard tokenVector.count == vectorSum.count else { return true }
            for index in tokenVector.indices {
                vectorSum[index] += tokenVector[index]
            }
            vectorCount += 1
            return true
        }
        guard vectorCount > 0 else { return nil }
        return vectorSum.map { $0 / Double(vectorCount) }
    }

    private func cosineSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return -1 }
        let dotProduct = zip(lhs, rhs).reduce(0) { $0 + $1.0 * $1.1 }
        let lhsMagnitude = sqrt(lhs.reduce(0) { $0 + $1 * $1 })
        let rhsMagnitude = sqrt(rhs.reduce(0) { $0 + $1 * $1 })
        guard lhsMagnitude > 0, rhsMagnitude > 0 else { return -1 }
        return dotProduct / (lhsMagnitude * rhsMagnitude)
    }

    private static func databaseURL() throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent("DocAI", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("RAGVectors.sqlite")
    }
}