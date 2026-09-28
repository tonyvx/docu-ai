# DocAI

DocAI is an iOS document library for importing, analyzing, organizing, and asking questions about PDFs. It uses SwiftUI, SwiftData, PDFKit, Vision, Apple Foundation Models, and Google Drive.

## Features

- Import PDFs from Files and extract selectable text, with Vision OCR for image-only pages.
- Analyze and classify documents with Apple Foundation Models.
- Browse, filter, preview, and search document records; index them with Spotlight.
- Ask document-grounded questions using a local SQLite vector index and Natural Language embeddings.
- Choose Local or Google Drive as the destination for new PDF imports.
- Protect the app interface with Face ID or the device passcode.

## Requirements

- Xcode 26 or later.
- iOS 26 or later.
- A device that supports Apple Foundation Models for on-device document analysis.
- Google Cloud project with the Google Drive API enabled to use Drive storage.

## Google Drive setup

1. In Google Cloud Console, configure the OAuth consent screen and enable the Google Drive API.
2. Create an OAuth client of type **iOS**. Its registered bundle ID must match the app's `PRODUCT_BUNDLE_IDENTIFIER` in both Debug and Release. The checked-in project currently uses `com.anthonyvalantrapersonalteam.DocAIProject`.
3. Set `GOOGLE_IOS_CLIENT_ID`, `GOOGLE_IOS_REVERSED_CLIENT_ID`, and `GOOGLE_IOS_BUNDLE_ID` in both Xcode build configurations. Use the values for that same iOS OAuth client; the bundle ID must match both the app and the OAuth registration.
4. Build and run the app, open **Settings**, select **Google Drive**, and connect a Google account.

The iOS client ID is public application configuration; do not add a client secret to the app. `GoogleOAuthInfo.plist` expands the build settings into the `GIDClientID` value and OAuth callback URL scheme.

Drive uploads are placed in a `docu-ai` folder, with subfolders from the suggested filing path. The app requests the `drive.file` scope, which limits access to files created or opened by DocAI. PDF files are stored in Drive; document metadata, extracted text, and the local SQLite search index remain on the device. A local PDF copy is also retained for preview and search.

## Build and validate

Resolve the Swift package dependencies in Xcode, then build the `DocAIProject` scheme. From Terminal, the simulator build can be checked with:

```sh
xcodebuild -project DocAIProject.xcodeproj -scheme DocAIProject -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

There is no automated test target in the current project. Face ID and Google OAuth flows require a device or simulator session to exercise interactively; Google Drive uploads also require valid OAuth configuration and network access.

## Data and privacy notes

- Face ID gates access to the app UI; it does not encrypt the app's SwiftData store, local PDF cache, or Drive files.
- Analysis and vector indexing run on-device. Natural Language may need to download its embedding assets the first time indexing is used.
- Imported files are currently limited to PDFs. The text excerpt stored with each document is truncated for local retrieval.

# TODO
1. ~~Add scan file via camera and crop as a pdf and import~~
2. ~~Handle scenario when changing the persistance from Local to drive and back~~
3. ~~Add logic to list files from persistance layer in the app Local / Drive~~
4. ~~Update google drive client Id / Move it to valantra.app~~
5. Handle repeat import of same scan, maybe provide an option to upload an update to a file or add smartness in AI to identify and inform and convert import to an update

6. Improve chat to be made scalable by focusing a category to build RAG, use category RAG to chat against. Any other scalable way.
7. Option to add a personal LLM subscription to do better chat