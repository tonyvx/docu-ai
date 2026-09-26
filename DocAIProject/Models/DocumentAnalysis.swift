import Foundation
import FoundationModels

@Generable
struct DocumentAnalysis {
    @Guide(description: "High-level category. Use one of: Insurance, Tax, Medical, Finance, Legal, Personal, Receipts. Do not use Uncategorized.")
    var category: String

    @Guide(description: "More specific type, e.g. Home Insurance Renewal, W-2, Lab Results")
    var documentType: String

    @Guide(description: "Primary date mentioned in the document if any, ISO8601 preferred")
    var documentDate: String?

    @Guide(description: "One or two sentence summary of the document")
    var summary: String

    @Guide(description: "Suggested folder path using / separators, e.g. Insurance/Home/2026")
    var suggestedPath: String
}
