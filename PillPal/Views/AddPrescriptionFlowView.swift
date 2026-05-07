import SwiftUI

struct AddPrescriptionFlowView: View {
    @Environment(\.dismiss) private var dismiss

    let targetPlanId: UUID?

    @State private var stage: Stage = .entry
    @State private var inputMode: InputMode?
    @State private var scannedImages: [UIImage] = []
    @State private var redactedImages: [UIImage] = []
    @State private var ocrText: String = ""
    @State private var ocrAutoStart = true
    @State private var extractionResult: LLMExtractionResult?
    @State private var finalPlan: MedicationPlan?

    private let llmService = LLMService()

    enum Stage {
        case entry
        case scan
        case redact
        case ocr
        case upload
        case draft
        case confirm
    }

    enum InputMode {
        case scan
        case manual
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .entry:
                    entryView

                case .scan:
                    DocumentScannerView(
                        onScanned: { images in
                            scannedImages = images
                            stage = .redact
                        },
                        onCancel: { dismiss() }
                    )

                case .redact:
                    RedactionEditorView(
                        images: scannedImages,
                        onExport: { images in
                            redactedImages = images
                            ocrAutoStart = true
                            stage = .ocr
                        },
                        onBack: { stage = .scan }
                    )

                case .ocr:
                    OCRProgressView(
                        images: redactedImages,
                        autoStart: ocrAutoStart,
                        onComplete: { text in
                            guard stage == .ocr else {
                                return
                            }
                            ocrText = text
                            ocrAutoStart = false
                            stage = .upload
                        },
                        onBack: {
                            ocrAutoStart = false
                            stage = .redact
                        }
                    )

                case .upload:
                    UploadPreviewView(
                        ocrText: ocrText,
                        redactedImages: redactedImages,
                        llmService: llmService,
                        onDraftReady: { result in
                            extractionResult = result
                            stage = .draft
                        },
                        onBack: {
                            stage = .redact
                        }
                    )

                case .draft:
                    if let extractionResult {
                        PlanDraftView(
                            extraction: extractionResult,
                            sourceOCRText: ocrText,
                            onBack: {
                                if inputMode == .manual {
                                    stage = .entry
                                } else {
                                    stage = .upload
                                }
                            },
                            onConfirm: { plan in
                                finalPlan = plan
                                stage = .confirm
                            }
                        )
                    } else {
                        fallbackView
                    }

                case .confirm:
                    if let finalPlan {
                        ConfirmCreateRemindersView(
                            plan: finalPlan,
                            originalScannedImages: scannedImages,
                            targetPlanId: targetPlanId,
                            onBack: { stage = .draft },
                            onFinish: { dismiss() }
                        )
                    } else {
                        fallbackView
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var entryView: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(targetPlanId == nil ? "Add New Plan" : "Add Prescription to Plan")
                    .font(.title2.weight(.semibold))
                Text(targetPlanId == nil
                     ? "Choose how you want to create your plan."
                     : "Choose how you want to append this prescription to the selected plan.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                inputMode = .scan
                stage = .scan
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Scan with Camera", systemImage: "camera.viewfinder")
                        .font(.headline)
                    Text("Scan one or more pages, then redact before OCR.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("flow.entry.scan")

            Button {
                inputMode = .manual
                extractionResult = Self.manualSeedExtraction
                scannedImages = []
                redactedImages = []
                ocrText = "Manual entry"
                finalPlan = nil
                stage = .draft
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Add Manually", systemImage: "square.and.pencil")
                        .font(.headline)
                    Text("Manually fill medications and follow-up details.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("flow.entry.manual")

            Spacer()

            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .font(.footnote)
        }
        .padding(20)
    }

    private var fallbackView: some View {
        VStack(spacing: 12) {
            Text("Flow state missing. Please restart.")
                .foregroundStyle(.secondary)
            Button("Close") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
    }

    private static var manualSeedExtraction: LLMExtractionResult {
        LLMExtractionResult(
            medications: [
                LLMMedication(
                    name: "",
                    dose: "",
                    route: .unknown,
                    frequency: MedicationFrequency(type: .timesPerDay, value: 1),
                    times: ["08:00"],
                    startDate: "unknown",
                    endDate: "unknown",
                    withFood: .unknown,
                    notes: [],
                    storage: [.unknown]
                )
            ],
            followUp: [],
            uncertainties: [
                LLMUncertainty(path: "medications[0].name", reason: "Manual entry required", candidates: []),
                LLMUncertainty(path: "medications[0].dose", reason: "Manual entry required", candidates: []),
                LLMUncertainty(path: "medications[0].start_date", reason: "Manual entry required", candidates: []),
                LLMUncertainty(path: "medications[0].end_date", reason: "Manual entry required", candidates: [])
            ]
        )
    }
}
