import SwiftUI
import PDFKit

struct DocumentDetailView: View {
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
}

private struct PDFPreviewSection: View {
    let document: Document

    @State private var pdfDocument: PDFDocument?
    @State private var currentPage = 0
    @State private var unavailableMessage = "The saved PDF file could not be found. Reimport this document to restore its preview."

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
        .task( loadPDF )
    }

    private func loadPDF() {
        let fileManager = FileManager.default
        var candidateURLs = [URL]()

        if let savedURL = document.iCloudURL {
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
