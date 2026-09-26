import Foundation
import PDFKit
import Vision
import UIKit

enum ExtractionError: Error {
    case cannotOpenPDF
    case noTextFound
}

struct PDFTextExtractor {
    /// Extracts text from a PDF. Falls back to Vision OCR on image-only pages.
    static func extractText(from url: URL) async throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw ExtractionError.cannotOpenPDF
        }

        var fullText = ""

        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }

            // Try native text first
            if let pageText = page.string, !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fullText += pageText + "\n\n"
                continue
            }

            // Fallback: render page and run Vision OCR
            let pageRect = page.bounds(for: .mediaBox)
            let renderer = UIGraphicsImageRenderer(size: pageRect.size)
            let image = renderer.image { ctx in
                UIColor.white.set()
                ctx.fill(pageRect)
                ctx.cgContext.translateBy(x: 0, y: pageRect.size.height)
                ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }

            if let cgImage = image.cgImage {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try handler.perform([request])

                let observations = request.results ?? []
                let pageOCR = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                fullText += pageOCR + "\n\n"
            }
        }

        let cleaned = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw ExtractionError.noTextFound }
        return cleaned
    }
}
