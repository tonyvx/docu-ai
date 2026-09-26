import Foundation

enum DocumentCategory: String, CaseIterable, Identifiable {
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
        selectableCases.map(\.rawValue)
    }

    static func normalized(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = allCases.first(where: { $0.rawValue.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return match.rawValue
        }
        return selectableCases.first?.rawValue ?? "Insurance"
    }
}
