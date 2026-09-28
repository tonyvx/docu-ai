import SwiftUI
import SwiftData
import PDFKit

struct DocumentDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isEditing = false

    let document: Document

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard

                metadataCard

                summaryCard

                PDFPreviewSection(document: document)

                excerptCard
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(document.originalFileName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isEditing = true
                } label: {
                    Label("Edit document", systemImage: "pencil")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            EditDocumentSheet(document: document, onSave: updateDocument)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "doc.fill")
                    .font(.title2)
                    .frame(width: 42, height: 42)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.accent)

                Spacer()

                Text(document.category)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())
            }

            Text(document.originalFileName)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)

            if !document.documentType.isEmpty {
                Text(document.documentType)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .font(.headline)

            VStack(spacing: 10) {
                metadataRow(label: "Category", value: document.category)
                metadataRow(label: "Type", value: document.documentType.isEmpty ? "—" : document.documentType)
                if let date = document.documentDate {
                    metadataRow(label: "Date", value: date.formatted(date: .abbreviated, time: .omitted))
                }
                metadataRow(label: "Path", value: document.suggestedPath.isEmpty ? "—" : document.suggestedPath)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Summary")
                .font(.headline)

            Text(document.summary.isEmpty ? "No summary available." : document.summary)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var excerptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Excerpt")
                .font(.headline)

            Text(document.extractedText.isEmpty ? "No excerpt available." : document.extractedText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @MainActor
    private func updateDocument(fileName: String, category: String) async throws {
        let trimmedName = fileName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        let nameWithoutExtension = (trimmedName as NSString).deletingPathExtension
        guard !nameWithoutExtension.isEmpty else { throw DocumentEditError.emptyFileName }
        let updatedFileName = "\(nameWithoutExtension).pdf"

        let storage: any DocumentStorageBackend = document.googleDriveFileID == nil
            ? PersistenceLayer.local.store
            : PersistenceLayer.googleDrive.store

        let oldFileName = document.originalFileName
        let oldLocalURL = document.localFileURL
        let oldCategory = document.category
        var renamedLocation: StoredPDFLocation?

        if updatedFileName != oldFileName {
            let location = try documentStorageLocation()
            let renamed = try await storage.renamePDF(at: location, to: updatedFileName)
            renamedLocation = renamed
            document.originalFileName = updatedFileName
            document.localFileURL = renamed.localURL
        }

        document.category = DocumentCategory.normalized(category)
        do {
            try modelContext.save()
        } catch {
            document.originalFileName = oldFileName
            document.localFileURL = oldLocalURL
            document.category = oldCategory
            if let renamedLocation {
                _ = try? await storage.renamePDF(at: renamedLocation, to: oldFileName)
            }
            throw error
        }

        SpotlightIndexer.index(document)
        do {
            try LocalRAGIndex.shared.updateMetadata(for: [document])
        } catch {
            print("RAG metadata refresh deferred until the next chat request: \(error.localizedDescription)")
        }
    }

    private func documentStorageLocation() throws -> StoredPDFLocation {
        if let localFileURL = document.localFileURL {
            return StoredPDFLocation(localURL: localFileURL, remoteID: document.googleDriveFileID)
        }
        if let remoteID = document.googleDriveFileID {
            return StoredPDFLocation(localURL: nil, remoteID: remoteID)
        }
        let folderURL = try LocalDocumentStore.folderURL(for: document.suggestedPath)
        return StoredPDFLocation(
            localURL: folderURL.appendingPathComponent(document.originalFileName),
            remoteID: nil
        )
    }
}

private enum DocumentEditError: LocalizedError {
    case emptyFileName

    var errorDescription: String? {
        "Enter a filename before saving."
    }
}

private struct EditDocumentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var fileName: String
    @State private var category: String
    @State private var newCategory = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    let document: Document
    let onSave: (String, String) async throws -> Void

    init(document: Document, onSave: @escaping (String, String) async throws -> Void) {
        self.document = document
        self.onSave = onSave
        _fileName = State(initialValue: document.originalFileName)
        _category = State(initialValue: document.category)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("File") {
                    TextField("Filename", text: $fileName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(DocumentCategory.selectableValues, id: \.self) { value in
                            Text(value).tag(value)
                        }
                    }
                    .pickerStyle(.menu)

                    HStack {
                        TextField("New category", text: $newCategory)
                            .textInputAutocapitalization(.words)
                        Button {
                            guard let addedCategory = DocumentCategory.addCustom(newCategory) else { return }
                            category = addedCategory
                            newCategory = ""
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .labelStyle(.iconOnly)
                        .disabled(newCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Add category")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await save() }
                        }
                        .disabled(fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await onSave(fileName, category)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PDFPreviewSection: View {
    @Environment(\.modelContext) private var modelContext

    let document: Document

    @State private var pdfDocument: PDFDocument?
    @State private var currentPage = 0
    @State private var unavailableMessage = "The saved PDF file could not be found. Reimport this document to restore its preview."

    private var previewTaskID: String {
        "\(document.localFileURL?.path ?? "")|\(document.googleDriveFileID ?? "")|\(document.originalFileName)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Document preview")
                    .font(.headline)

                Spacer()

                if let pdfDocument, pdfDocument.pageCount > 0 {
                    Text("Page \(min(currentPage + 1, pdfDocument.pageCount)) of \(pdfDocument.pageCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let pdfDocument, pdfDocument.pageCount > 0 {
                PDFPageViewer(document: pdfDocument, currentPage: $currentPage)
                    .frame(height: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                ContentUnavailableView(
                    "Preview unavailable",
                    systemImage: "doc.questionmark",
                    description: Text(unavailableMessage)
                )
                .frame(maxWidth: .infinity)
                .frame(height: 220)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .task(id: previewTaskID) {
            await loadPDF()
        }
    }

    private func loadPDF() async {
        pdfDocument = nil
        currentPage = 0
        unavailableMessage = "The saved PDF file could not be found. Reimport this document to restore its preview."
        let fileManager = FileManager.default
        var candidateURLs = [URL]()

        if let savedURL = document.localFileURL {
            candidateURLs.append(savedURL)
        }

        if let folderURL = try? LocalDocumentStore.folderURL(for: document.suggestedPath) {
            candidateURLs.append(folderURL.appendingPathComponent(document.originalFileName))

            if let files = try? fileManager.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: nil
            ) {
                let baseName = (document.originalFileName as NSString).deletingPathExtension
                candidateURLs.append(contentsOf: files.filter { fileURL in
                    fileURL.pathExtension.lowercased() == "pdf" &&
                    fileURL.deletingPathExtension().lastPathComponent.hasPrefix("\(baseName)-")
                })
            }
        }

        var foundPDFFile = false
        for fileURL in candidateURLs where fileManager.fileExists(atPath: fileURL.path) {
            foundPDFFile = true
            if let pdf = openPDF(at: fileURL), pdf.pageCount > 0 {
                pdfDocument = pdf
                currentPage = 0
                return
            }
        }

        if let remoteID = document.googleDriveFileID {
            do {
                let data = try await GoogleDriveDocumentStore.shared.downloadPDF(fileID: remoteID)
                guard let pdf = PDFDocument(data: data), pdf.pageCount > 0 else {
                    unavailableMessage = "The Google Drive file could not be read as a PDF."
                    return
                }

                let cachedURL = try LocalDocumentStore.cacheDownloadedPDF(
                    data,
                    fileID: remoteID
                )
                let previousURL = document.localFileURL
                document.localFileURL = cachedURL
                do {
                    try modelContext.save()
                } catch {
                    document.localFileURL = previousURL
                    try? FileManager.default.removeItem(at: cachedURL)
                    throw error
                }
                pdfDocument = pdf
                return
            } catch {
                unavailableMessage = error.localizedDescription
                return
            }
        }

        unavailableMessage = foundPDFFile
            ? "The saved file exists, but it could not be read as a PDF. It may be damaged or password-protected."
            : "The saved PDF file could not be found. Reimport this document to restore its preview."
    }

    private func openPDF(at url: URL) -> PDFDocument? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return nil
        }
        return PDFDocument(data: data)
    }
}

private struct PDFPageViewer: UIViewRepresentable {
    let document: PDFDocument
    @Binding var currentPage: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(currentPage: $currentPage)
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.usePageViewController(true, withViewOptions: nil)
        pdfView.autoScales = true
        pdfView.backgroundColor = UIColor.secondarySystemBackground
        context.coordinator.observePageChanges(in: pdfView)
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
    }

    final class Coordinator {
        @Binding var currentPage: Int
        private var pageChangeObserver: NSObjectProtocol?

        init(currentPage: Binding<Int>) {
            _currentPage = currentPage
        }

        func observePageChanges(in pdfView: PDFView) {
            pageChangeObserver = NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged,
                object: pdfView,
                queue: .main
            ) { [weak self, weak pdfView] _ in
                guard let pdfView,
                      let page = pdfView.currentPage,
                      let document = pdfView.document else { return }
                self?.currentPage = document.index(for: page)
            }
        }

        deinit {
            if let pageChangeObserver {
                NotificationCenter.default.removeObserver(pageChangeObserver)
            }
        }
    }
}
