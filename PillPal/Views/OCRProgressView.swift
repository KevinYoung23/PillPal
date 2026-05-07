import SwiftUI

struct OCRProgressView: View {
    let images: [UIImage]
    var autoStart: Bool = true
    var onComplete: (String) -> Void
    var onBack: () -> Void

    @State private var progress: Double = 0
    @State private var isRunning = false
    @State private var errorMessage: String?
    @State private var ocrTask: Task<Void, Never>?
    @State private var isInterrupted = false

    private let ocrService = OCRService()

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "text.viewfinder")
                .font(.system(size: 40))
                .symbolRenderingMode(.hierarchical)

            Text("Extracting Text")
                .font(.title3.weight(.semibold))

            Text("OCR runs on redacted images only.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ProgressView(value: progress)
                .padding(.horizontal, 40)

            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !autoStart, !isRunning, errorMessage == nil, progress == 0 {
                Button("Run OCR") {
                    startOCR()
                }
                .buttonStyle(.borderedProminent)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                Button("Try Again") {
                    startOCR()
                }
                .buttonStyle(.borderedProminent)
            }

            Button("Back") {
                interruptOCR()
                onBack()
            }
                .buttonStyle(.bordered)

            Spacer()
        }
        .padding(20)
        .onAppear {
            if autoStart, ocrTask == nil {
                startOCR()
            }
        }
        .onDisappear {
            interruptOCR()
        }
    }

    private func startOCR() {
        interruptOCR()
        isInterrupted = false
        errorMessage = nil
        ocrTask = Task {
            await runOCR()
        }
    }

    private func interruptOCR() {
        isInterrupted = true
        ocrTask?.cancel()
        ocrTask = nil
    }

    private func runOCR() async {
        isRunning = true
        errorMessage = nil
        progress = 0

        do {
            let text = try await ocrService.recognizeText(from: images) { ratio in
                progress = ratio
            }
            guard !Task.isCancelled, !isInterrupted else {
                isRunning = false
                return
            }
            onComplete(text)
        } catch is CancellationError {
            // User interrupted OCR by leaving this screen.
        } catch {
            if !isInterrupted {
                errorMessage = "OCR failed. Please verify redacted pages and retry."
                Logger.error("OCR stage failed.")
            }
        }

        isRunning = false
        ocrTask = nil
    }
}
