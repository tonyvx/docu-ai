import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportAndAnalyzeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedURL: URL?
    @State private var isImporting = false
    @State private var isScanning = false
    @State private var isProcessing = false
    @State private var analysis: DocumentAnalysis?
    @State private var selectedCategory = "Insurance"
    @State private var fileName = ""
    @State private var folderPath = ""
    @State private var extractedText = ""
    @State private var errorMessage: String?
    @AppStorage("persistenceLayer") private var persistenceLayer = PersistenceLayer.local.rawValue

    private let analyzer = DocumentAnalyzer()

    private var availableCategories: [String] {
        DocumentCategory.selectableValues
    }

    private var selectedPersistenceLayer: PersistenceLayer {
        PersistenceLayer(rawValue: persistenceLayer) ?? .local
    }

    private var canSave: Bool {
        selectedPersistenceLayer != .googleDrive || GoogleDriveDocumentStore.shared.hasDriveAccess
    }

    private func normalizeCategory(_ value: String) -> String {
        DocumentCategory.normalized(value)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    Button("Choose PDF from Files") {
                        isImporting = true
                    }
                    Button {
                        if DocumentScanner.isSupported {
                            isScanning = true
                        } else {
                            errorMessage = "Document scanning is unavailable on this device."
                        }
                    } label: {
                        Label("Scan Document", systemImage: "doc.viewfinder")
                    }
                    if let url = selectedURL {
                        Text(url.lastPathComponent)
                            .foregroundStyle(.secondary)
                    }
                }

                if isProcessing {
                    Section {
                        ProgressView("Extracting & analyzing…")
                    }
                }

                if let analysis {
                    Section("AI Analysis") {
                        LabeledContent("Type", value: analysis.documentType)
                        if let date = analysis.documentDate {
                            LabeledContent("Date", value: date)
                        }
                        Text(analysis.summary)
                    }

                    Section("Filing details") {
                        TextField("File name", text: $fileName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Folder path", text: $folderPath)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Picker("Category", selection: $selectedCategory) {
                            ForEach(availableCategories, id: \.self) { category in
                                Text(category).tag(category)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Section {
                        Button(saveButtonTitle) {
                            Task { await confirmAndSave() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isProcessing || !canSave)
                        if selectedPersistenceLayer == .googleDrive && !canSave {
                            Text("Connect Google Drive in Settings before saving this document.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Import Document")
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    selectedURL = url
                    Task { await process(url: url) }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            .sheet(isPresented: $isScanning) {
                DocumentScanner { result in
                    switch result {
                    case .success(let url):
                        selectedURL = url
                        Task { await process(url: url) }
                    case .failure(let error):
                        errorMessage = error.localizedDescription
                    }
                }
                .ignoresSafeArea()
            }
        }
    }

    private func process(url: URL) async {
        isProcessing = true
        errorMessage = nil
        analysis = nil
        fileName = url.lastPathComponent
        folderPath = ""

        // Start accessing security-scoped resource
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let text = try await PDFTextExtractor.extractText(from: url)
            extractedText = text
            let result = try await analyzer.analyze(text: text, fileName: url.lastPathComponent)
            analysis = result
            selectedCategory = normalizeCategory(result.category)
            folderPath = result.suggestedPath
        } catch {
            errorMessage = error.localizedDescription
        }

        isProcessing = false
    }

    private func confirmAndSave() async {
        guard let sourceURL = selectedURL, let analysis else { return }

        let saveFileName = normalizedFileName
        let saveFolderPath = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)

        isProcessing = true
        defer { isProcessing = false }

        var localDestination: URL?
        var uploadedFileID: String?
        var pendingDocument: Document?

        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        do {
            // Keep a local copy for previews and document search.
            let destination = try LocalDocumentStore.copy(
                fileAt: sourceURL,
                suggestedPath: saveFolderPath,
                originalName: saveFileName
            )
            localDestination = destination

            if selectedPersistenceLayer == .googleDrive {
                uploadedFileID = try await GoogleDriveDocumentStore.shared.upload(
                    fileAt: destination,
                    suggestedPath: saveFolderPath,
                    originalName: saveFileName
                )
            }

            // Create SwiftData record
            let doc = Document(
                originalFileName: saveFileName,
                category: selectedCategory,
                documentType: analysis.documentType,
                summary: analysis.summary,
                suggestedPath: saveFolderPath,
                extractedText: String(extractedText.prefix(8000))   // keep a usable excerpt
            )
            doc.iCloudURL = destination
            doc.googleDriveFileID = uploadedFileID

            // Simple date parsing (improve later)
            if let dateStr = analysis.documentDate {
                let formatter = ISO8601DateFormatter()
                doc.documentDate = formatter.date(from: dateStr)
            }

            modelContext.insert(doc)
            pendingDocument = doc
            try modelContext.save()
            pendingDocument = nil

            do {
                try await LocalRAGIndex.shared.index(document: doc, fullText: extractedText)
            } catch {
                print("Local RAG indexing deferred until the next chat scan: \(error.localizedDescription)")
            }

            // Keep the document discoverable through system search.
            SpotlightIndexer.index(doc)

            dismiss()
        } catch {
            if let pendingDocument {
                modelContext.delete(pendingDocument)
            }
            if let uploadedFileID {
                try? await GoogleDriveDocumentStore.shared.delete(fileID: uploadedFileID)
            }
            if let localDestination {
                try? FileManager.default.removeItem(at: localDestination)
            }
            errorMessage = error.localizedDescription
        }
    }

    private var saveButtonTitle: String {
        selectedPersistenceLayer == .googleDrive
            ? "Approve & Save to Google Drive"
            : "Approve & Save Locally"
    }

    private var normalizedFileName: String {
        let enteredName = fileName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        let nameWithoutExtension = (enteredName as NSString).deletingPathExtension
        let baseName = nameWithoutExtension.isEmpty ? "Document" : nameWithoutExtension
        return "\(baseName).pdf"
    }
}
