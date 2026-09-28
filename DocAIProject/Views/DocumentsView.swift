import SwiftUI
import SwiftData

struct DocumentsView: View {
    @Query(sort: \Document.createdAt, order: .reverse) private var documents: [Document]
    @AppStorage("persistenceLayer") private var persistenceLayer = PersistenceLayer.local.rawValue
    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var drivePDFs = [GoogleDrivePDF]()
    @State private var isLoadingDriveFiles = false
    @State private var driveError: String?

    private let categories = ["All"] + DocumentCategory.selectableValues

    private var selectedStorage: PersistenceLayer {
        PersistenceLayer(rawValue: persistenceLayer) ?? .local
    }

    private var localDocuments: [Document] {
        documents.filter { $0.googleDriveFileID == nil }
    }

    private var documentsByDriveID: [String: Document] {
        Dictionary(
            documents.compactMap { document in
                document.googleDriveFileID.map { ($0, document) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var filteredDocuments: [Document] {
        localDocuments.filter { document in
            let matchesSearch = searchText.isEmpty ||
                document.originalFileName.localizedCaseInsensitiveContains(searchText) ||
                document.summary.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = selectedCategory == "All" || document.category == selectedCategory
            return matchesSearch && matchesCategory
        }
    }

    private var filteredDrivePDFs: [GoogleDrivePDF] {
        drivePDFs.filter { file in
            let document = documentsByDriveID[file.id]
            let matchesSearch = searchText.isEmpty ||
                file.name.localizedCaseInsensitiveContains(searchText) ||
                (document?.summary.localizedCaseInsensitiveContains(searchText) ?? false)
            let matchesCategory = selectedCategory == "All" || document?.category == selectedCategory
            return matchesSearch && matchesCategory
        }
    }

    private var visibleDocumentCount: Int {
        selectedStorage == .local ? localDocuments.count : drivePDFs.count
    }

    private var visibleCategoryCount: Int {
        let categories = selectedStorage == .local
            ? localDocuments.map(\.category)
            : drivePDFs.compactMap { documentsByDriveID[$0.id]?.category }
        return Set(categories).count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerCard
                    statsSection
                    searchAndFiltersSection

                    if selectedStorage == .googleDrive {
                        if isLoadingDriveFiles {
                            ProgressView("Loading Google Drive files…")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 32)
                        } else if let driveError {
                            ContentUnavailableView(
                                "Google Drive unavailable",
                                systemImage: "externaldrive.badge.exclamationmark",
                                description: Text(driveError)
                            )
                        } else if filteredDrivePDFs.isEmpty {
                            emptyState
                        } else {
                            driveListSection
                        }
                    } else if filteredDocuments.isEmpty {
                        emptyState
                    } else {
                        documentListSection
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(selectedStorage == .local ? "Local Library" : "Google Drive")
            .task(id: persistenceLayer) {
                await loadDriveFilesIfNeeded()
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

    private var documentListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent files")
                .font(.headline)

            ForEach(filteredDocuments) { doc in
                NavigationLink(value: doc) {
                    DocumentCard(document: doc)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var driveListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Google Drive PDFs")
                .font(.headline)

            ForEach(filteredDrivePDFs) { file in
                if let document = documentsByDriveID[file.id] {
                    NavigationLink(value: document) {
                        DocumentCard(document: document)
                    }
                    .buttonStyle(.plain)
                } else {
                    DrivePDFCard(file: file)
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
    private func loadDriveFilesIfNeeded() async {
        guard selectedStorage == .googleDrive else {
            drivePDFs = []
            driveError = nil
            return
        }

        isLoadingDriveFiles = true
        driveError = nil
        defer { isLoadingDriveFiles = false }

        do {
            drivePDFs = try await GoogleDriveDocumentStore.shared.listPDFs()
        } catch {
            driveError = error.localizedDescription
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

private struct DrivePDFCard: View {
    let file: GoogleDrivePDF

    var body: some View {
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
                Text("Google Drive PDF")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if let modifiedTime = file.modifiedTime,
               let date = ISO8601DateFormatter().date(from: modifiedTime) {
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
}

