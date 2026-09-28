import Foundation

enum DocumentCategory: String, CaseIterable, Identifiable {
    static let customCategoriesKey = "customDocumentCategories"

    case insurance = "Insurance"
    case tax = "Tax"
    case medical = "Medical"
    case finance = "Finance"
    case legal = "Legal"
    case personal = "Personal"
    case receipts = "Receipts"
    case uncategorized = "Uncategorized"

    var id: String { rawValue }

    static var selectableCases: [DocumentCategory] {
        allCases.filter { $0 != .uncategorized }
    }

    static var selectableValues: [String] {
        var values = selectableCases.map(\.rawValue)
        for customValue in UserDefaults.standard.stringArray(forKey: customCategoriesKey) ?? [] {
            guard !values.contains(where: { $0.caseInsensitiveCompare(customValue) == .orderedSame }) else { continue }
            values.append(customValue)
        }
        return values
    }

    static func normalized(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = selectableValues.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return match
        }
        return selectableCases.first?.rawValue ?? "Insurance"
    }

    @discardableResult
    static func addCustom(_ value: String) -> String? {
        let trimmed = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !trimmed.isEmpty else { return nil }
        if let existing = selectableValues.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }

        var customValues = UserDefaults.standard.stringArray(forKey: customCategoriesKey) ?? []
        customValues.append(trimmed)
        UserDefaults.standard.set(customValues, forKey: customCategoriesKey)
        return trimmed
    }
}
