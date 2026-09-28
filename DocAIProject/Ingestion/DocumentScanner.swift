import SwiftUI
import VisionKit

struct DocumentScanner: UIViewControllerRepresentable {
    let onScan: (Result<URL, Error>) -> Void

    static var isSupported: Bool {
        VNDocumentCameraViewController.isSupported
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onScan: (Result<URL, Error>) -> Void

        init(onScan: @escaping (Result<URL, Error>) -> Void) {
            self.onScan = onScan
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            do {
                let url = try makePDF(from: scan)
                controller.dismiss(animated: true) {
                    self.onScan(.success(url))
                }
            } catch {
                controller.dismiss(animated: true) {
                    self.onScan(.failure(error))
                }
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            controller.dismiss(animated: true) {
                self.onScan(.failure(error))
            }
        }

        private func makePDF(from scan: VNDocumentCameraScan) throws -> URL {
            let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
            let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
            let data = renderer.pdfData { context in
                for pageIndex in 0..<scan.pageCount {
                    context.beginPage()
                    let image = scan.imageOfPage(at: pageIndex)
                    let scale = min(pageBounds.width / image.size.width, pageBounds.height / image.size.height)
                    let imageSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    let imageRect = CGRect(
                        x: (pageBounds.width - imageSize.width) / 2,
                        y: (pageBounds.height - imageSize.height) / 2,
                        width: imageSize.width,
                        height: imageSize.height
                    )
                    image.draw(in: imageRect)
                }
            }

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("Scan-\(UUID().uuidString).pdf")
            try data.write(to: url, options: .atomic)
            return url
        }
    }
}