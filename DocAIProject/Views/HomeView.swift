import SwiftUI

struct HomeView: View {
    @State private var showingImport = false

    var body: some View {
        TabView {
            OverviewView()
                .tabItem { Label("Overview", systemImage: "house.fill") }

            DocumentsView()
                .tabItem { Label("Documents", systemImage: "doc.on.doc.fill") }

            ChatView()
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right.fill") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(.accentColor)
        .overlay(alignment: .bottom) {
            Button {
                showingImport = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(Color.accentColor, in: Circle())
                    .overlay(Circle().stroke(.background, lineWidth: 4))
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
            }
            .accessibilityLabel("Import document")
            .padding(.bottom, 58)
        }
        .sheet(isPresented: $showingImport) {
            ImportAndAnalyzeView()
        }
    }
}

private struct OverviewView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heroCard

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quick actions")
                            .font(.headline)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            QuickActionCard(icon: "plus.circle.fill", title: "Import", subtitle: "Add a PDF")
                            QuickActionCard(icon: "sparkles", title: "Analyze", subtitle: "Review AI summary")
                            QuickActionCard(icon: "folder.fill", title: "Organize", subtitle: "Keep files tidy")
                            QuickActionCard(icon: "bubble.left.and.bubble.right.fill", title: "Ask AI", subtitle: "Search your docs")
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("What this app does")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            featureRow(title: "Import PDFs", detail: "Capture receipts, documents, and records in seconds.")
                            featureRow(title: "Auto-classify", detail: "Use AI to suggest the right category and type.")
                            featureRow(title: "Ask questions", detail: "Search across your tracked documents with natural language.")
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Overview")
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("DocAI")
                        .font(.title.bold())
                    Text("Your personal document workspace")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 34))
                    .foregroundStyle(.accent)
                    .padding(12)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            Text("Sort, review, and ask questions about imported PDFs without losing context.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.14), Color(.secondarySystemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct QuickActionCard: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(.accent)

            Text(title)
                .font(.headline)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct featureRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

