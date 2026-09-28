import SwiftUI
import UIKit

struct SettingsView: View {
    @AppStorage("persistenceLayer") private var persistenceLayer = PersistenceLayer.local.rawValue
    @State private var isGoogleConnected = false
    @State private var isConnecting = false
    @State private var connectionMessage: String?

    private var driveStore: GoogleDriveDocumentStore {
        GoogleDriveDocumentStore.shared
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Document storage") {
                    Picker("Save imported documents to", selection: $persistenceLayer) {
                        ForEach(PersistenceLayer.allCases) { layer in
                            Text(layer.title).tag(layer.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Changing this setting changes where new imports are saved and which files appear in the Library. Existing files stay in their original location and are not moved.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if PersistenceLayer(rawValue: persistenceLayer) == .googleDrive {
                        Text("Docu AI can list PDFs across your Drive using read-only access. New uploads are filed in the docu-ai folder, with a local copy kept for previews and document search.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if PersistenceLayer(rawValue: persistenceLayer) == .googleDrive {
                    Section("Google Drive") {
                        HStack {
                            Label(
                                isGoogleConnected ? "Connected" : "Not connected",
                                systemImage: isGoogleConnected ? "checkmark.circle.fill" : "xmark.circle"
                            )
                            .foregroundStyle(isGoogleConnected ? .green : .secondary)
                            Spacer()
                            if isConnecting {
                                ProgressView()
                            }
                        }

                        if isGoogleConnected {
                            Button("Disconnect Google Drive", role: .destructive) {
                                driveStore.disconnect()
                                isGoogleConnected = false
                            }
                        } else {
                            Button {
                                Task { await connectGoogleDrive() }
                            } label: {
                                Label("Connect Google Drive", systemImage: "externaldrive.badge.person.crop")
                            }
                            .disabled(isConnecting || !driveStore.isConfigured)
                        }

                        if let configurationMessage = driveStore.configurationMessage {
                            Text(configurationMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if let connectionMessage {
                            Text(connectionMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .task {
                isGoogleConnected = await driveStore.restoreSignIn()
            }
        }
    }

    @MainActor
    private func connectGoogleDrive() async {
        guard let presenter = activeViewController() else {
            connectionMessage = GoogleDriveStorageError.presentationUnavailable.localizedDescription
            return
        }

        isConnecting = true
        connectionMessage = nil
        defer { isConnecting = false }

        do {
            try await driveStore.connect(presenting: presenter)
            isGoogleConnected = true
        } catch {
            connectionMessage = error.localizedDescription
        }
    }

    @MainActor
    private func activeViewController() -> UIViewController? {
        let activeScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return activeScene?.windows.first(where: \.isKeyWindow)?.rootViewController
    }
}