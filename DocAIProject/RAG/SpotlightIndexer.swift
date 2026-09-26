import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

struct SpotlightIndexer {
    static func index(_ document: Document) {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .pdf)
        attributeSet.title = document.originalFileName
        attributeSet.contentDescription = document.summary
        attributeSet.keywords = [document.category, document.documentType]
        attributeSet.textContent = document.extractedText
        if let date = document.documentDate {
            attributeSet.contentCreationDate = date
        }

        let item = CSSearchableItem(
            uniqueIdentifier: document.spotlightIdentifier,
            domainIdentifier: Bundle.main.bundleIdentifier ?? "com.docai.project",
            attributeSet: attributeSet
        )

        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error {
                print("Spotlight indexing error: \(error)")
            }
        }
    }
}
