import SwiftUI
import SwiftData

struct DocumentsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Document.createdAt, order: .reverse) private var documents: [Document]
    @AppStorage("persistenceLayer") private var persistenceLayer = PersistenceLayer.local.rawValue
    @State private var navigationPath = NavigationPath()
    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var storedPDFs = [StoredPDF]()
    @State private var isLoadingFiles = false
    @State private var storageError: String?
    @State private var creatingRecordID: String?
    @State private var recordCreationError: String?

    private var categories: [String] { ["All"] + DocumentCategory.selectableValues }

    private let analyzer = DocumentAnalyzer()

    private var selectedStorage: PersistenceLayer {
        PersistenceLayer(rawValue: persistenceLayer) ?? .local
    }

    private var documentsByStorageID: [String: Document] {
        Dictionary(
            documents.compactMap { document in
                if let remoteID = document.googleDriveFileID {
                    return (remoteID, document)
                }
                if let localURL = document.localFileURL {
                    return (localURL.standardizedFileURL.path, document)
                }
                return nil
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var driveCachePaths: Set<String> {
        Set(documents.filter { $0.googleDriveFileID != nil }
            .compactMap { $0.localFileURL?.standardizedFileURL.path })
    }

    private var filteredStoredPDFs: [StoredPDF] {
        storedPDFs.filter { file in
            if selectedStorage == .local,
               let localURL = file.localURL,
               driveCachePaths.contains(localURL.standardizedFileURL.path) {
                return false
            }

            let document = documentsByStorageID[file.id]
            let matchesSearch = searchText.isEmpty ||
                file.name.localizedCaseInsensitiveContains(searchText) ||
                (document?.summary.localizedCaseInsensitiveContains(searchText) ?? false)
            let matchesCategory = selectedCategory == "All" || document?.category == selectedCategory
            return matchesSearch && matchesCategory
        }
    }

    private var visibleDocumentCount: Int {
        storedPDFs.count
    }

    private var visibleCategoryCount: Int {
        Set(storedPDFs.compactMap { documentsByStorageID[$0.id]?.category }).count
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerCard
                    statsSection
                    searchAndFiltersSection

                    if let recordCreationError {
                        Text(recordCreationError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if isLoadingFiles {
                        ProgressView("Loading documents…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    } else if let storageError {
                        ContentUnavailableView(
                            "Storage unavailable",
                            systemImage: "externaldrive.badge.exclamationmark",
                            description: Text(storageError)
                        )
                    } else if filteredStoredPDFs.isEmpty {
                        emptyState
                    } else {
                        storedPDFListSection
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(selectedStorage == .local ? "Local Library" : "Google Drive")
            .task(id: persistenceLayer) {
                await loadStoredFiles()
            }
            .navigationDestination(for: Document.self) { doc in
                DocumentDetailView(document: doc)
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedStorage == .local ? "Local Documents" : "Google Drive Documents")
                        .font(.largeTitle.bold())

                    Text(selectedStorage == .local
                         ? "Files saved on this device."
                         : "PDFs stored in your Docu AI Drive folder.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "folder.fill.badge.plus")
                    .font(.title2)
                    .frame(width: 46, height: 46)
                    .background(Color.accentColor.opacity(0.14))
                    .foregroundStyle(.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.10), Color(.secondarySystemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var statsSection: some View {
        HStack(spacing: 12) {
            StatCard(title: "Files", value: "\(visibleDocumentCount)", systemImage: "doc.fill", tint: .blue)
            StatCard(title: "Categories", value: "\(visibleCategoryCount)", systemImage: "folder.fill", tint: .green)
            StatCard(title: "Ready", value: visibleDocumentCount == 0 ? "0" : "AI", systemImage: "sparkles", tint: .purple)
        }
    }

    private var searchAndFiltersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search documents", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { category in
                        Button {
                            selectedCategory = category
                        } label: {
                            Text(category)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedCategory == category ? Color.accentColor : Color(.secondarySystemFill))
                                .foregroundStyle(selectedCategory == category ? .white : .primary)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }

    private var storedPDFListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent files")
                .font(.headline)

            ForEach(filteredStoredPDFs) { file in
                if let document = documentsByStorageID[file.id] {
                    NavigationLink(value: document) {
                        DocumentCard(document: document)
                    }
                    .buttonStyle(.plain)
                } else {
                    StoredPDFCard(
                        file: file,
                        storageTitle: selectedStorage.title,
                        isProcessing: creatingRecordID == file.id
                    ) {
                        Task { await createDocumentRecord(for: file) }
                    }
                    .disabled(creatingRecordID != nil)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text(selectedStorage == .local ? "No local documents" : "No PDFs in Google Drive")
                .font(.headline)

            Text("Use the plus button to import a PDF to this storage location.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @MainActor
    private func loadStoredFiles() async {
        isLoadingFiles = true
        storageError = nil
        defer { isLoadingFiles = false }

        do {
            storedPDFs = try await selectedStorage.store.listFiles()
        } catch {
            storedPDFs = []
            storageError = error.localizedDescription
        }
    }

    @MainActor
    private func createDocumentRecord(for file: StoredPDF) async {
        guard creatingRecordID == nil else { return }
        creatingRecordID = file.id
        recordCreationError = nil
        defer { creatingRecordID = nil }

        do {
            let localURL = try await selectedStorage.store.localURL(for: file)
            let fullText = try await PDFTextExtractor.extractText(from: localURL)
            let analysis = try await analyzer.analyze(text: fullText, fileName: file.name)
            let document = Document(
                originalFileName: file.name,
                category: DocumentCategory.normalized(analysis.category),
                documentType: analysis.documentType,
                summary: analysis.summary,
                suggestedPath: analysis.suggestedPath,
                extractedText: String(fullText.prefix(8000))
            )
            document.localFileURL = localURL
            document.googleDriveFileID = file.remoteID

            if let date = analysis.documentDate {
                document.documentDate = ISO8601DateFormatter().date(from: date)
            }

            modelContext.insert(document)
            do {
                try modelContext.save()
            } catch {
                modelContext.delete(document)
                throw error
            }

            do {
                try await LocalRAGIndex.shared.index(document: document, fullText: fullText)
            } catch {
                print("Local RAG indexing deferred until the next chat scan: \(error.localizedDescription)")
            }
            SpotlightIndexer.index(document)
            navigationPath.append(document)
        } catch {
            recordCreationError = error.localizedDescription
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
                .padding(8)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.14))
                .foregroundStyle(tint)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(value)
                .font(.title2.bold())

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct DocumentCard: View {
    let document: Document

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "doc.fill")
                    .font(.title3)
                    .frame(width: 38, height: 38)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(document.originalFileName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        Text(document.category)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Capsule())

                        if !document.documentType.isEmpty {
                            Text(document.documentType)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                Text(document.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(document.summary.isEmpty ? "No summary available yet." : document.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct StoredPDFCard: View {
    let file: StoredPDF
    let storageTitle: String
    let isProcessing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "doc.fill")
                    .font(.title3)
                    .frame(width: 38, height: 38)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(file.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text("\(storageTitle) PDF · Add to library")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if isProcessing {
                    ProgressView()
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                }

                if let date = file.modifiedAt {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isProcessing ? "Adding \(file.name) to library" : "Add \(file.name) to library")
    }
}

