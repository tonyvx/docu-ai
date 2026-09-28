import SwiftUI
import SwiftData
import LocalAuthentication
import GoogleSignIn

@main struct DocAIApp: App {
    var body: some Scene {
        WindowGroup {
            AuthenticationGateView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
        .modelContainer(for: Document.self)
    }
}

private struct AuthenticationGateView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var isUnlocked = false
    @State private var isAuthenticating = false
    @State private var authenticationMessage: String?

    var body: some View {
        Group {
            if isUnlocked {
                HomeView()
            } else {
                lockScreen
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                if !isUnlocked && !isAuthenticating {
                    Task { await authenticate() }
                }
            } else {
                isUnlocked = false
                authenticationMessage = nil
            }
        }
    }

    private var lockScreen: some View {
        VStack(spacing: 20) {
            Image(systemName: "faceid")
                .font(.system(size: 54))
                .foregroundStyle(.tint)

            Text("Docu AI is locked")
                .font(.title2.weight(.semibold))

            Text(authenticationMessage ?? "Authenticate to access your documents.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Unlock with Face ID") {
                Task { await authenticate() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAuthenticating)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private func authenticate() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        var evaluationError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evaluationError) else {
            authenticationMessage = evaluationError?.localizedDescription ?? "Device authentication is unavailable."
            return
        }

        do {
            let authenticated = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock Docu AI to access your documents."
            )
            if authenticated && scenePhase == .active {
                isUnlocked = true
                authenticationMessage = nil
            }
        } catch {
            authenticationMessage = error.localizedDescription
        }
    }
}
