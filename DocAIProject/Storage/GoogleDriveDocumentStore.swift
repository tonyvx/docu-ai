import Foundation
import GoogleSignIn
import UIKit

enum PersistenceLayer: String, CaseIterable, Identifiable {
    case local
    case googleDrive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: "Local"
        case .googleDrive: "Google Drive"
        }
    }
}

enum GoogleDriveStorageError: LocalizedError {
    case missingConfiguration
    case signInRequired
    case presentationUnavailable
    case driveAccessNotGranted
    case invalidResponse
    case configuration(String)
    case requestFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "Google Drive isn't configured. Add your iOS OAuth client ID and reversed client ID to the project build settings."
        case .signInRequired:
            "Connect a Google account in Settings before importing to Google Drive."
        case .presentationUnavailable:
            "Google sign-in is unavailable right now. Try again from the foreground."
        case .driveAccessNotGranted:
            "Google Drive access wasn't granted. Connect Google Drive again in Settings."
        case .invalidResponse:
            "Google Drive returned an invalid response."
        case .configuration(let message):
            message
        case .requestFailed(let status, let message):
            "Google Drive request failed (\(status)): \(message)"
        }
    }
}

@MainActor
final class GoogleDriveDocumentStore {
    static let shared = GoogleDriveDocumentStore()
    static let driveScope = "https://www.googleapis.com/auth/drive.file"

    private let folderMimeType = "application/vnd.google-apps.folder"
    private let rootFolderName = "docu-ai"

    private init() {}

    var isConfigured: Bool {
        configurationMessage == nil
    }

    var configurationMessage: String? {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !clientID.isEmpty,
              !clientID.hasPrefix("YOUR_") else {
            return "Google Drive isn't configured with an OAuth client ID."
        }
        guard let configuredBundleID = Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthBundleID") as? String,
              let appBundleID = Bundle.main.bundleIdentifier else {
            return "Google Drive is missing its registered OAuth bundle ID."
        }
        guard configuredBundleID == appBundleID else {
            return "The Google OAuth client is registered for \(configuredBundleID), but this app uses \(appBundleID). Register the OAuth client for the app's existing bundle ID."
        }
        return nil
    }

    var hasDriveAccess: Bool {
        GIDSignIn.sharedInstance.currentUser?.grantedScopes?.contains(Self.driveScope) == true
    }

    func restoreSignIn() async -> Bool {
        guard isConfigured,
              let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else {
            return false
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        if let currentUser = GIDSignIn.sharedInstance.currentUser {
            return currentUser.grantedScopes?.contains(Self.driveScope) == true
        }
        let requiredScope = Self.driveScope
        return await withCheckedContinuation { continuation in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, _ in
                continuation.resume(returning: user?.grantedScopes?.contains(requiredScope) == true)
            }
        }
    }

    func connect(presenting viewController: UIViewController) async throws {
        guard isConfigured,
              let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else {
            throw GoogleDriveStorageError.configuration(
                configurationMessage ?? GoogleDriveStorageError.missingConfiguration.localizedDescription
            )
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        let user: GIDGoogleUser
        if let currentUser = GIDSignIn.sharedInstance.currentUser {
            user = currentUser
        } else {
            let result: GIDSignInResult = try await withCheckedThrowingContinuation { continuation in
                GIDSignIn.sharedInstance.signIn(withPresenting: viewController) { result, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let result {
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(throwing: GoogleDriveStorageError.invalidResponse)
                    }
                }
            }
            user = result.user
        }

        if user.grantedScopes?.contains(Self.driveScope) != true {
            let requiredScope = Self.driveScope
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                user.addScopes([Self.driveScope], presenting: viewController) { result, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if result?.user.grantedScopes?.contains(requiredScope) == true {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: GoogleDriveStorageError.driveAccessNotGranted)
                    }
                }
            }
        }
    }

    func disconnect() {
        GIDSignIn.sharedInstance.signOut()
    }

    func upload(fileAt url: URL, suggestedPath: String, originalName: String) async throws -> String {
        let token = try await freshAccessToken()
        var parentID = try await findOrCreateFolder(named: rootFolderName, parentID: nil, token: token)
        for component in DocumentStoragePath.folderComponents(from: suggestedPath) {
            parentID = try await findOrCreateFolder(named: component, parentID: parentID, token: token)
        }

        let fileData = try Data(contentsOf: url)
        let boundary = "DocAI-\(UUID().uuidString)"
        let metadata = DriveFileMetadata(name: originalName, mimeType: "application/pdf", parents: [parentID])
        let metadataData = try JSONEncoder().encode(metadata)
        var body = Data()
        body.append("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metadataData)
        body.append("\r\n--\(boundary)\r\nContent-Type: application/pdf\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--".data(using: .utf8)!)

        guard var components = URLComponents(string: "https://www.googleapis.com/upload/drive/v3/files") else {
            throw GoogleDriveStorageError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "uploadType", value: "multipart"),
            URLQueryItem(name: "fields", value: "id")
        ]
        guard let uploadURL = components.url else {
            throw GoogleDriveStorageError.invalidResponse
        }
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let response: DriveFileResponse = try await perform(request)
        return response.id
    }

    func delete(fileID: String) async throws {
        let token = try await freshAccessToken()
        let endpoint = URL(string: "https://www.googleapis.com/drive/v3/files")!
            .appendingPathComponent(fileID)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try await requestData(for: request)
    }

    private func freshAccessToken() async throws -> String {
        guard let user = await restoredUser() else {
            throw GoogleDriveStorageError.signInRequired
        }
        guard user.grantedScopes?.contains(Self.driveScope) == true else {
            throw GoogleDriveStorageError.driveAccessNotGranted
        }
        let refreshedUser: GIDGoogleUser = try await withCheckedThrowingContinuation { continuation in
            user.refreshTokensIfNeeded { refreshedUser, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let refreshedUser {
                    continuation.resume(returning: refreshedUser)
                } else {
                    continuation.resume(throwing: GoogleDriveStorageError.invalidResponse)
                }
            }
        }
        return refreshedUser.accessToken.tokenString
    }

    private func restoredUser() async -> GIDGoogleUser? {
        if let currentUser = GIDSignIn.sharedInstance.currentUser {
            return currentUser
        }
        return await withCheckedContinuation { continuation in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, _ in
                continuation.resume(returning: user)
            }
        }
    }

    private func findOrCreateFolder(named name: String, parentID: String?, token: String) async throws -> String {
        let escapedName = name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        var query = "name = '\(escapedName)' and mimeType = '\(folderMimeType)' and trashed = false"
        if let parentID {
            query += " and '\(parentID)' in parents"
        }

        guard var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files") else {
            throw GoogleDriveStorageError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id,name)"),
            URLQueryItem(name: "pageSize", value: "100")
        ]
        guard let listURL = components.url else {
            throw GoogleDriveStorageError.invalidResponse
        }
        var request = URLRequest(url: listURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let listing: DriveFileList = try await perform(request)
        if let existingFolder = listing.files.first {
            return existingFolder.id
        }

        let metadata = DriveFileMetadata(name: name, mimeType: folderMimeType, parents: parentID.map { [$0] })
        guard let createURL = URL(string: "https://www.googleapis.com/drive/v3/files?fields=id") else {
            throw GoogleDriveStorageError.invalidResponse
        }
        var createRequest = URLRequest(url: createURL)
        createRequest.httpMethod = "POST"
        createRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        createRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        createRequest.httpBody = try JSONEncoder().encode(metadata)
        let folder: DriveFileResponse = try await perform(createRequest)
        return folder.id
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let data = try await requestData(for: request)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw GoogleDriveStorageError.invalidResponse
        }
    }

    private func requestData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleDriveStorageError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(DriveAPIError.self, from: data).error.message)
                ?? String(data: data, encoding: .utf8)
                ?? "Unknown error"
            throw GoogleDriveStorageError.requestFailed(httpResponse.statusCode, message)
        }
        return data
    }
}

private struct DriveFileMetadata: Encodable {
    let name: String
    let mimeType: String
    let parents: [String]?
}

private struct DriveFileList: Decodable {
    let files: [DriveFileResponse]
}

private struct DriveFileResponse: Decodable {
    let id: String
}

private struct DriveAPIError: Decodable {
    let error: Details

    struct Details: Decodable {
        let message: String
    }
}
