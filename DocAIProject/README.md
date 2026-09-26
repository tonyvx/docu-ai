# DocAI Project

A SwiftUI document library and AI assistant for organizing personal PDFs and interrogating their contents.

## Current app flow

1. Import a PDF from Files or iCloud
2. Extract text using PDFKit and Vision OCR fallback
3. Classify the document with a Foundation Models call
4. Review the AI analysis and choose a valid category
5. Save the document metadata into SwiftData
6. Search the document library and ask questions in the chat view

## Project structure

- `DocAI.swift` — app entry point
- `Models/` — `Document` and `DocumentAnalysis`
- `Ingestion/` — PDF extraction logic
- `AI/` — document analysis with Foundation Models
- `RAG/` — retrieval and Spotlight indexing
- `Storage/` — local document persistence helper
- `Views/` — SwiftUI screens
- `Resources/` — category definitions and shared metadata

## Requirements

- Xcode 26+ / latest available toolchain
- iOS 26+ deployment target for the current project configuration
- Device or simulator with Foundation Models support for on-device analysis

## Notes

- Text extraction keeps a truncated excerpt for RAG use.
- Retrieval uses a simple term-scoring strategy rather than embeddings.
- The app currently stores documents in the app sandbox and indexes them for Spotlight search.
- Its current design is a working prototype for personal document AI workflows.

## Next improvements

- Better retrieval ranking with metadata weighting and richer search
- Persistent security-scoped bookmarks for external files
- More robust category validation and custom user categories
- Image + scanned document support
- Better chat history and source citations
