import SwiftUI
import UniformTypeIdentifiers

/// Drop zone view for dragging and dropping RAML ZIP files
struct DropZoneView: View {
    @Binding var state: ProcessingState
    let onFileDrop: (URL) -> Void

    @State private var isTargeted = false

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 16)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 2.5, dash: state.isProcessing ? [0] : [10, 6])
                        )
                        .foregroundColor(borderColor)
                )
                .shadow(color: .black.opacity(isTargeted ? 0.15 : 0.05), radius: isTargeted ? 12 : 4, y: 2)

            // Content
            VStack(spacing: 16) {
                if state.isProcessing {
                    processingContent
                } else if case .complete(let files) = state {
                    completedContent(files: files)
                } else if case .error(let message) = state {
                    errorContent(message: message)
                } else {
                    idleContent
                }
            }
            .padding(40)
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
        .animation(.easeInOut(duration: 0.2), value: isTargeted)
        .animation(.easeInOut(duration: 0.3), value: state)
    }

    // MARK: - Idle State

    private var idleContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.zipper")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(isTargeted ? .accentColor : .secondary)
                .scaleEffect(isTargeted ? 1.15 : 1.0)

            Text("Drop RAML ZIP here")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.primary)

            Text("or click to browse")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                Text("Accepts .zip files containing RAML specifications")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
            .padding(.top, 4)
        }
        .onTapGesture {
            browseForFile()
        }
    }

    // MARK: - Processing State

    private var processingContent: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.3)
                .progressViewStyle(.circular)

            Text(state.statusMessage)
                .font(.headline)
                .foregroundColor(.primary)

            // Step indicators
            HStack(spacing: 24) {
                StepIndicator(label: "Extract", isActive: state == .extracting, isComplete: isStepComplete(.extracting))
                StepIndicator(label: "Parse", isActive: state == .parsing, isComplete: isStepComplete(.parsing))
                StepIndicator(label: "Generate", isActive: state == .generating, isComplete: isStepComplete(.generating))
                StepIndicator(label: "PDF", isActive: state == .creatingPDF, isComplete: isStepComplete(.creatingPDF))
            }
        }
    }

    // MARK: - Complete State

    private func completedContent(files: OutputFiles) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("Documents Generated")
                .font(.title3)
                .fontWeight(.medium)

            // File listing
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .foregroundColor(.blue)
                    Text(files.markdownURL.lastPathComponent)
                        .font(.subheadline)
                    Spacer()
                    Button {
                        NSWorkspace.shared.open(files.markdownURL)
                    } label: {
                        Text("Open")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let pdfURL = files.pdfURL {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.richtext")
                            .foregroundColor(.red)
                        Text(pdfURL.lastPathComponent)
                            .font(.subheadline)
                        Spacer()
                        Button {
                            NSWorkspace.shared.open(pdfURL)
                        } label: {
                            Text("Open")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text("PDF generation failed -- use Pandoc on the .md file")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 8)

            HStack(spacing: 12) {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([files.markdownURL])
                }
                .buttonStyle(.bordered)

                Button("Process Another") {
                    state = .idle
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Error State

    private func errorContent(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("Processing Failed")
                .font(.title3)
                .fontWeight(.medium)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                state = .idle
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
    }

    // MARK: - Appearance Helpers

    private var backgroundColor: Color {
        if isTargeted {
            return Color.accentColor.opacity(0.08)
        }
        if case .error = state {
            return Color.orange.opacity(0.04)
        }
        if case .complete = state {
            return Color.green.opacity(0.04)
        }
        return Color(nsColor: .controlBackgroundColor).opacity(0.5)
    }

    private var borderColor: Color {
        if isTargeted {
            return .accentColor
        }
        if case .error = state {
            return .orange.opacity(0.5)
        }
        if case .complete = state {
            return .green.opacity(0.5)
        }
        return .secondary.opacity(0.3)
    }

    private func isStepComplete(_ step: ProcessingState) -> Bool {
        let order: [ProcessingState] = [.extracting, .parsing, .generating, .creatingPDF]
        guard let stepIndex = order.firstIndex(of: step),
              let currentIndex = order.firstIndex(of: state) else { return false }
        return stepIndex < currentIndex
    }

    // MARK: - File Handling

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !state.isProcessing else { return false }

        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url") { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      url.pathExtension.lowercased() == "zip" else { return }

                DispatchQueue.main.async {
                    onFileDrop(url)
                }
            }
        }
        return true
    }

    private func browseForFile() {
        guard !state.isProcessing else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "zip")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Select RAML ZIP File"
        panel.message = "Choose a .zip file containing a RAML specification"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                onFileDrop(url)
            }
        }
    }
}

// MARK: - Step Indicator

struct StepIndicator: View {
    let label: String
    let isActive: Bool
    let isComplete: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(fillColor)
                    .frame(width: 24, height: 24)

                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                } else if isActive {
                    Circle()
                        .fill(.white)
                        .frame(width: 8, height: 8)
                }
            }

            Text(label)
                .font(.caption2)
                .foregroundColor(isActive || isComplete ? .primary : .secondary)
        }
    }

    private var fillColor: Color {
        if isComplete { return .green }
        if isActive { return .accentColor }
        return Color.secondary.opacity(0.2)
    }
}

// MARK: - Preview

#Preview {
    DropZoneView(state: .constant(.idle)) { _ in }
        .frame(width: 500, height: 300)
        .padding()
}
