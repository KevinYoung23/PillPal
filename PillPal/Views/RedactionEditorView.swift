import PencilKit
import SwiftUI

struct RedactionEditorView: View {
    let images: [UIImage]
    var onExport: ([UIImage]) -> Void
    var onBack: () -> Void

    @State private var drawings: [PKDrawing]
    @State private var canvasSizes: [CGSize]
    @State private var currentPage = 0
    @State private var brushWidth: CGFloat = 10
    @State private var undoTrigger = 0
    @State private var redoTrigger = 0
    @State private var canUndo = false
    @State private var canRedo = false

    init(images: [UIImage], onExport: @escaping ([UIImage]) -> Void, onBack: @escaping () -> Void) {
        self.images = images
        self.onExport = onExport
        self.onBack = onBack
        _drawings = State(initialValue: Array(repeating: PKDrawing(), count: images.count))
        _canvasSizes = State(initialValue: Array(repeating: .zero, count: images.count))
    }

    var body: some View {
        VStack(spacing: 14) {
            header

            if images.indices.contains(currentPage) {
                GeometryReader { proxy in
                    let targetSize = fittedSize(imageSize: images[currentPage].size, container: proxy.size)
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color(.secondarySystemBackground))

                        Image(uiImage: images[currentPage])
                            .resizable()
                            .scaledToFit()
                            .frame(width: targetSize.width, height: targetSize.height)

                        PencilCanvasView(
                            drawing: $drawings[currentPage],
                            lineWidth: brushWidth,
                            undoTrigger: undoTrigger,
                            redoTrigger: redoTrigger,
                            onUndoRedoStateChange: { undo, redo in
                                canUndo = undo
                                canRedo = redo
                            }
                        )
                        .frame(width: targetSize.width, height: targetSize.height)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        canvasSizes[currentPage] = targetSize
                    }
                    .onChange(of: targetSize) { _, newSize in
                        canvasSizes[currentPage] = newSize
                    }
                }
            }

            controls
        }
        .padding(20)
        .navigationTitle("Privacy Redaction")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Brush over personal details")
                .font(.title3.weight(.semibold))
            Text("Redaction will be burned into new images before OCR. Original scans never upload.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Button {
                    currentPage = max(0, currentPage - 1)
                } label: {
                    Label("Prev", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .disabled(currentPage == 0)

                Text("Page \(currentPage + 1) / \(images.count)")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)

                Button {
                    currentPage = min(images.count - 1, currentPage + 1)
                } label: {
                    Label("Next", systemImage: "chevron.right")
                }
                .buttonStyle(.bordered)
                .disabled(currentPage == images.count - 1)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Brush width")
                        .font(.footnote)
                    Spacer()
                    Text("\(Int(brushWidth))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Slider(value: $brushWidth, in: 6...20, step: 1)
                    .tint(.black)

                HStack(spacing: 10) {
                    Text("Preview")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Circle()
                        .fill(Color.black)
                        .frame(width: brushWidth, height: brushWidth)
                    Spacer()

                    ForEach([8, 14, 22], id: \.self) { size in
                        Button {
                            brushWidth = CGFloat(size)
                        } label: {
                            Text("\(size)")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(12)
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

            HStack(spacing: 10) {
                Button {
                    undoTrigger += 1
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!canUndo)

                Button {
                    redoTrigger += 1
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!canRedo)

                Button("Clear Page") {
                    drawings[currentPage] = PKDrawing()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 10) {
                Button("Back", action: onBack)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                Button {
                    let redacted = RedactionService.burnRedactions(
                        originals: images,
                        drawings: drawings,
                        canvasSizes: canvasSizes
                    )
                    onExport(redacted)
                } label: {
                    Label("Run OCR", systemImage: "text.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func fittedSize(imageSize: CGSize, container: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return .zero
        }
        let widthRatio = container.width / imageSize.width
        let heightRatio = container.height / imageSize.height
        let scale = min(widthRatio, heightRatio)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}

private struct PencilCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var lineWidth: CGFloat
    var undoTrigger: Int
    var redoTrigger: Int
    var onUndoRedoStateChange: (Bool, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let view = PKCanvasView(frame: .zero)
        view.delegate = context.coordinator
        view.drawingPolicy = .anyInput
        view.isOpaque = false
        view.backgroundColor = .clear
        view.tool = PKInkingTool(.monoline, color: .black, width: lineWidth)
        onUndoRedoStateChange(false, false)
        return view
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing {
            uiView.drawing = drawing
        }
        uiView.tool = PKInkingTool(.monoline, color: .black, width: lineWidth)

        if context.coordinator.lastUndoTrigger != undoTrigger {
            context.coordinator.lastUndoTrigger = undoTrigger
            if uiView.undoManager?.canUndo == true {
                uiView.undoManager?.undo()
            }
        }

        if context.coordinator.lastRedoTrigger != redoTrigger {
            context.coordinator.lastRedoTrigger = redoTrigger
            if uiView.undoManager?.canRedo == true {
                uiView.undoManager?.redo()
            }
        }

        onUndoRedoStateChange(
            uiView.undoManager?.canUndo ?? false,
            uiView.undoManager?.canRedo ?? false
        )
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvasView
        var lastUndoTrigger: Int
        var lastRedoTrigger: Int

        init(_ parent: PencilCanvasView) {
            self.parent = parent
            self.lastUndoTrigger = parent.undoTrigger
            self.lastRedoTrigger = parent.redoTrigger
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
            parent.onUndoRedoStateChange(
                canvasView.undoManager?.canUndo ?? false,
                canvasView.undoManager?.canRedo ?? false
            )
        }
    }
}
