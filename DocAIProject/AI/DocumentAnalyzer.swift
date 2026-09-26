import Foundation
import FoundationModels

@MainActor
final class DocumentAnalyzer {
    private let session: LanguageModelSession

    init() {
        // Use the system on-device model. You can later switch to Private Cloud Compute if needed.
        self.session = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: """
            You are a precise document classifier and summarizer for a personal document manager.
            Always return structured data. Be concise. Prefer clear category names and realistic folder paths.
            """
        )
    }

    func analyze(text: String, fileName: String) async throws -> DocumentAnalysis {
        // Keep prompt reasonably sized for the on-device model
        let truncated = String(text.prefix(6000))

        let prompt = """
        Analyze this document.

        File name: \(fileName)

        Content:
        \(truncated)

        Extract category, specific document type, any primary date, a short summary, and a suggested folder path.
        """

        let response = try await session.respond(to: prompt, generating: DocumentAnalysis.self)
        return response.content
    }
}
