import SwiftUI
import VisionKit

struct DocumentScannerView: View {
    var onScanned: ([UIImage]) -> Void
    var onCancel: () -> Void

    @State private var images: [UIImage] = []
    @State private var showScanner = false

    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Scan Prescription")
                    .font(.title2.weight(.semibold))
                Text("Capture all pages. You can redact private info in the next step.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if images.isEmpty {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: 220)
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "doc.text.viewfinder")
                                .font(.system(size: 34))
                            Text("No pages scanned yet")
                                .foregroundStyle(.secondary)
                        }
                    }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 140, height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(alignment: .bottomLeading) {
                                    Text("Page \(index + 1)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(6)
                                        .background(.black.opacity(0.6), in: Capsule())
                                        .padding(8)
                                }
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .frame(height: 190)
            }

            VStack(spacing: 12) {
                Button {
                    showScanner = true
                } label: {
                    Label(images.isEmpty ? "Start Scan" : "Rescan Pages", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!ScannerService.isSupported)

                Button {
                    images = ScannerService.makeDemoPages()
                } label: {
                    Label("Use Demo Pages", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("scan.useDemoPages")

                Button {
                    onScanned(images)
                } label: {
                    Text("Continue to Redaction")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(images.isEmpty)
                .accessibilityIdentifier("scan.continueToRedaction")

                Button("Cancel", role: .cancel, action: onCancel)
                    .font(.footnote)
            }

            Spacer()
        }
        .padding(20)
        .sheet(isPresented: $showScanner) {
            if ScannerService.isSupported {
                ScannerRepresentable(images: $images)
            } else {
                VStack(spacing: 10) {
                    Text("Document scanner is unavailable on this device.")
                    Button("Load Demo Pages") {
                        images = ScannerService.makeDemoPages()
                        showScanner = false
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Close") { showScanner = false }
                }
                .padding()
            }
        }
    }
}

private struct ScannerRepresentable: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    @Binding var images: [UIImage]

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: ScannerRepresentable

        init(_ parent: ScannerRepresentable) {
            self.parent = parent
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            Logger.error("Document scanner failed.")
            parent.dismiss()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let newImages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            parent.images = newImages
            parent.dismiss()
        }
    }
}
