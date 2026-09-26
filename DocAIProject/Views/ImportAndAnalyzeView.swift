import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportAndAnalyzeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedURL: URL?
    @State private var isImporting = false
    @State private var isProcessing = false
    @State private var analysis: DocumentAnalysis?
    @State private var selectedCategory = "Insurance"
    @State private var extractedText = ""
    @State private var errorMessage: String?

    private let analyzer = DocumentAnalyzer()

    private var availableCategories: [String] {
        DocumentCategory.selectableValues
    }

    private func normalizeCategory(_ value: String) -> String {
        DocumentCategory.normalized(value)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    Button("Choose PDF from Files / iCloud") {
                        isImporting = true
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
                        Picker("Category", selection: $selectedCategory) {
                            ForEach(availableCategories, id: \.self) { category in
                                Text(category).tag(category)
                            }
                        }
                        .pickerStyle(.menu)

                        LabeledContent("Type", value: analysis.documentType)
                        if let date = analysis.documentDate {
                            LabeledContent("Date", value: date)
                        }
                        Text(analysis.summary)
                        LabeledContent("Suggested path", value: analysis.suggestedPath)
                    }

                    Section {
                        Button("Approve & Move to iCloud") {
                            Task { await confirmAndSave() }
                        }
                        .buttonStyle(.borderedProminent)
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
        }
    }

    private func process(url: URL) async {
        isProcessing = true
        errorMessage = nil
        analysis = nil

        // Start accessing security-scoped resource
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let text = try await PDFTextExtractor.extractText(from: url)
            extractedText = text
            let result = try await analyzer.analyze(text: text, fileName: url.lastPathComponent)
            analysis = result
            selectedCategory = normalizeCategory(result.category)
        } catch {
            errorMessage = error.localizedDescription
        }

        isProcessing = false
    }

    private func confirmAndSave() async {
        guard let sourceURL = selectedURL, let analysis else { return }

        isProcessing = true
        defer { isProcessing = false }

        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        do {
            // Move into iCloud under the suggested path
            let destination = try ICloudDocumentStore.move(
                fileAt: sourceURL,
                suggestedPath: analysis.suggestedPath,
                originalName: sourceURL.lastPathComponent
            )

            // Create SwiftData record
            let doc = Document(
                originalFileName: sourceURL.lastPathComponent,
                category: selectedCategory,
                documentType: analysis.documentType,
                summary: analysis.summary,
                suggestedPath: analysis.suggestedPath,
                extractedText: String(extractedText.prefix(8000))   // keep a usable excerpt
            )
            doc.iCloudURL = destination

            // Simple date parsing (improve later)
            if let dateStr = analysis.documentDate {
                let formatter = ISO8601DateFormatter()
                doc.documentDate = formatter.date(from: dateStr)
            }

            modelContext.insert(doc)
            try modelContext.save()

            do {
                try LocalRAGIndex.shared.index(document: doc, fullText: extractedText)
            } catch {
                print("Local RAG indexing deferred until the next chat scan: \(error.localizedDescription)")
            }

            // Keep the document discoverable through system search.
            SpotlightIndexer.index(doc)

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
