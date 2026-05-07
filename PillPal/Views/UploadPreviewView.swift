import SwiftUI

struct UploadPreviewView: View {
    let ocrText: String
    let redactedImages: [UIImage]
    var llmService: LLMService
    var onDraftReady: (LLMExtractionResult) -> Void
    var onBack: () -> Void

    @State private var userConsent = false
    @State private var showText = true
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var extractionTask: Task<Void, Never>?
    @State private var loadingAnimationTask: Task<Void, Never>?
    @State private var isInterrupted = false
    @State private var loadingMessageIndex = 0
    @State private var dotPhase = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Upload Preview")
                        .font(.title2.weight(.semibold))
                    Text("For DeepSeek, only redacted OCR text is sent for extraction.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    Image(systemName: llmService.isConfigured ? "network" : "exclamationmark.triangle")
                    Text(llmService.isConfigured ? "Live LLM endpoint: \(llmService.endpointHost)" : "LLM API key not configured")
                        .font(.footnote.weight(.medium))
                }
                .foregroundStyle(llmService.isConfigured ? .green : .orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))

                DisclosureGroup(isExpanded: $showText) {
                    Text(ocrText)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                } label: {
                    Text("Text to upload")
                        .font(.headline)
                }
                .padding(14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))

                HStack(spacing: 8) {
                    Image(systemName: "doc.on.doc")
                    Text("Redacted pages processed locally: \(redactedImages.count)")
                        .font(.footnote.weight(.medium))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

                Toggle(isOn: $userConsent) {
                    Text("I confirm private information has been redacted and I consent to upload this OCR text.")
                        .font(.footnote)
                }
                .toggleStyle(.switch)

                if isLoading {
                    loadingCard
                        .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity), removal: .opacity))
                }

                if !llmService.isConfigured {
                    Text("Add a valid DeepSeek API key in Config.plist (LLMApiKey) before generating a draft.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
        .onDisappear {
            interruptExtraction()
        }
    }

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(Color.blue.opacity(0.18), lineWidth: 8)
                        .frame(width: 34, height: 34)
                    Circle()
                        .trim(from: 0.1, to: 0.85)
                        .stroke(
                            AngularGradient(
                                colors: [.blue, .cyan, .blue.opacity(0.25)],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 34, height: 34)
                        .rotationEffect(.degrees(Double(dotPhase) * 90))
                        .animation(.linear(duration: 0.45), value: dotPhase)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Generating your draft")
                        .font(.headline)
                    Text(Self.loadingMessages[loadingMessageIndex])
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                        .id(loadingMessageIndex)
                }
                Spacer()
            }

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index <= (dotPhase % 3) ? Color.blue : Color.blue.opacity(0.2))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.25), value: dotPhase)
                }
            }

            Text("Please keep this screen open. This usually takes 10-30 seconds.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.10), Color.cyan.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button("Back") {
                interruptExtraction()
                onBack()
            }
            .buttonStyle(.bordered)

            Button {
                startExtraction()
            } label: {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Generate Draft")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!userConsent || isLoading || !llmService.isConfigured)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func startExtraction() {
        interruptExtraction()
        isInterrupted = false
        extractionTask = Task {
            await runExtraction()
        }
        startLoadingAnimation()
    }

    private func interruptExtraction() {
        isInterrupted = true
        stopLoadingAnimation()
        extractionTask?.cancel()
        extractionTask = nil
    }

    private func runExtraction() async {
        withAnimation(.easeOut(duration: 0.2)) {
            isLoading = true
        }
        errorMessage = nil

        do {
            let result = try await llmService.extract(ocrText: ocrText, redactedImages: redactedImages)
            guard !Task.isCancelled, !isInterrupted else {
                withAnimation(.easeOut(duration: 0.2)) {
                    isLoading = false
                }
                return
            }
            onDraftReady(result)
        } catch is CancellationError {
            // User interrupted extraction by leaving this screen.
        } catch let extractionError as LLMService.ExtractionError {
            if !isInterrupted {
                errorMessage = extractionError.localizedDescription
                Logger.error("LLM extraction failed: \(extractionError.localizedDescription)")
            }
        } catch {
            if !isInterrupted {
                errorMessage = "Could not generate a structured plan. \(error.localizedDescription)"
                Logger.error("LLM extraction failed.")
            }
        }

        withAnimation(.easeOut(duration: 0.2)) {
            isLoading = false
        }
        stopLoadingAnimation()
        extractionTask = nil
    }

    private func startLoadingAnimation() {
        stopLoadingAnimation()
        loadingMessageIndex = 0
        dotPhase = 0
        loadingAnimationTask = Task {
            while !Task.isCancelled && extractionTask != nil {
                try? await Task.sleep(nanoseconds: 550_000_000)
                guard !Task.isCancelled else { return }
                dotPhase = (dotPhase + 1) % 12
                if dotPhase % 3 == 0 {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        loadingMessageIndex = (loadingMessageIndex + 1) % Self.loadingMessages.count
                    }
                }
            }
        }
    }

    private func stopLoadingAnimation() {
        loadingAnimationTask?.cancel()
        loadingAnimationTask = nil
        dotPhase = 0
        loadingMessageIndex = 0
    }

    private static let loadingMessages: [String] = [
        "Analyzing OCR text",
        "Matching medications and schedule terms",
        "Checking start and end dates",
        "Building your editable plan"
    ]
}
