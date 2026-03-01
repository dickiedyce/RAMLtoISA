import SwiftUI

/// Main content view of the RAML to ISA application
struct ContentView: View {
    @State private var processingState: ProcessingState = .idle
    @State private var recentFiles: [RecentFile] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            // Main drop zone
            DropZoneView(state: $processingState) { url in
                processFile(url: url)
            }
            .padding(24)

            // Recent files section
            if !recentFiles.isEmpty {
                Divider()
                recentFilesSection
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("RAML to ISA")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Generate Integration Solution Architecture documents from RAML specifications")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // App icon / badge
            Image(systemName: "doc.text.fill")
                .font(.title)
                .foregroundColor(.accentColor)
        }
    }

    // MARK: - Recent Files

    private var recentFilesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            ForEach(recentFiles.prefix(3)) { file in
                HStack {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(file.inputName)
                        .font(.subheadline)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text(file.outputName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    if let url = file.outputURL {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Image(systemName: "arrow.up.forward.square")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    }
                }
            }
        }
    }

    // MARK: - Processing

    private func processFile(url: URL) {
        let settings = SettingsView.current
        DocumentPipeline.process(
            zipURL: url,
            settings: settings,
            onStateChange: { newState in
                processingState = newState
            },
            completion: { finalState in
                processingState = finalState

                if case .complete(let files) = finalState {
                    let recent = RecentFile(
                        inputName: url.lastPathComponent,
                        outputName: files.pdfURL?.lastPathComponent ?? files.markdownURL.lastPathComponent,
                        outputURL: files.pdfURL ?? files.markdownURL,
                        date: Date()
                    )
                    recentFiles.insert(recent, at: 0)
                    if recentFiles.count > 5 {
                        recentFiles = Array(recentFiles.prefix(5))
                    }
                }
            }
        )
    }
}

// MARK: - Recent File Model

struct RecentFile: Identifiable {
    let id = UUID()
    let inputName: String
    let outputName: String
    let outputURL: URL?
    let date: Date
}

// MARK: - Preview

#Preview {
    ContentView()
        .frame(width: 600, height: 500)
}
