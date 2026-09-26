import SwiftUI
import SwiftData

struct DocumentsView: View {
    @Query(sort: \Document.createdAt, order: .reverse) private var documents: [Document]
    @State private var showingImport = false
    @State private var searchText = ""
    @State private var selectedCategory = "All"

    private let categories = ["All"] + DocumentCategory.selectableValues

    private var filteredDocuments: [Document] {
        documents.filter { document in
            let matchesSearch = searchText.isEmpty ||
                document.originalFileName.localizedCaseInsensitiveContains(searchText) ||
                document.summary.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = selectedCategory == "All" || document.category == selectedCategory
            return matchesSearch && matchesCategory
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerCard
                    statsSection
                    searchAndFiltersSection

                    if filteredDocuments.isEmpty {
                        emptyState
                    } else {
                        documentListSection
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingImport = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .sheet(isPresented: $showingImport) {
                ImportAndAnalyzeView()
            }
            .navigationDestination(for: Document.self) { doc in
                DocumentDetailView(document: doc)
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("My Documents")
                        .font(.largeTitle.bold())

                    Text("AI-powered filing for receipts, contracts, and personal records.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "folder.fill.badge.plus")
                    .font(.title2)
                    .frame(width: 46, height: 46)
                    .background(Color.accentColor.opacity(0.14))
                    .foregroundStyle(.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.10), Color(.secondarySystemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var statsSection: some View {
        HStack(spacing: 12) {
            StatCard(title: "Files", value: "\(documents.count)", systemImage: "doc.fill", tint: .blue)
            StatCard(title: "Categories", value: "\(Set(documents.map(\.category)).count)", systemImage: "folder.fill", tint: .green)
            StatCard(title: "Ready", value: documents.isEmpty ? "0" : "AI", systemImage: "sparkles", tint: .purple)
        }
    }

    private var searchAndFiltersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search documents", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { category in
                        Button {
                            selectedCategory = category
                        } label: {
                            Text(category)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedCategory == category ? Color.accentColor : Color(.secondarySystemFill))
                                .foregroundStyle(selectedCategory == category ? .white : .primary)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }

    private var documentListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent files")
                .font(.headline)

            ForEach(filteredDocuments) { doc in
                NavigationLink(value: doc) {
                    DocumentCard(document: doc)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text("No documents yet")
                .font(.headline)

            Text("Import a PDF to start organizing and chatting with your files.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showingImport = true
            } label: {
                Label("Import a document", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
                .padding(8)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.14))
                .foregroundStyle(tint)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(value)
                .font(.title2.bold())

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct DocumentCard: View {
    let document: Document

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "doc.fill")
                    .font(.title3)
                    .frame(width: 38, height: 38)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(document.originalFileName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        Text(document.category)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Capsule())

                        if !document.documentType.isEmpty {
                            Text(document.documentType)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                Text(document.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(document.summary.isEmpty ? "No summary available yet." : document.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

