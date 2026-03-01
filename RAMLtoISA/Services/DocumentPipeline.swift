import Foundation
import AppKit

/// Configuration for ISA document generation
struct ISASettings {
    var architectName: String = "<architect.email@company.com>"
    var includeEndpoints: Bool = true
    var includeDiagrams: Bool = true
    var includeRequirements: Bool = true
}

/// Orchestrates the full pipeline: ZIP -> RAML -> ISA Markdown + PDF
final class DocumentPipeline {

    /// Process a ZIP file containing a RAML specification and produce markdown + PDF
    static func process(
        zipURL: URL,
        settings: ISASettings = ISASettings(),
        onStateChange: @escaping (ProcessingState) -> Void,
        completion: @escaping (ProcessingState) -> Void
    ) {
        var tempDir: URL?

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Step 1: Extract ZIP
                DispatchQueue.main.async { onStateChange(.extracting) }
                let (extractedDir, ramlFile) = try ZipHandler.extractAndFindRAML(zipURL: zipURL)
                tempDir = extractedDir

                // Step 2: Parse RAML
                DispatchQueue.main.async { onStateChange(.parsing) }
                let parser = RAMLParser(fileURL: ramlFile)
                let spec = try parser.parse()

                // Step 3: Generate ISA markdown
                DispatchQueue.main.async { onStateChange(.generating) }
                let generator = ISAGenerator(
                    apiInfo: spec.apiInfo,
                    endpoints: spec.endpoints,
                    requirements: spec.requirements,
                    architect: settings.architectName
                )
                let markdown = generator.generateMarkdown()

                // Determine output filenames
                let baseName = suggestedBaseName(from: zipURL, apiInfo: spec.apiInfo)

                // Step 4: Present save dialog for the output directory/files
                DispatchQueue.main.async {
                    presentSaveDialog(baseName: baseName) { saveURL in
                        guard let saveURL else {
                            if let dir = tempDir { ZipHandler.cleanup(tempDir: dir) }
                            completion(.idle)
                            return
                        }

                        // Save markdown immediately
                        let mdURL = saveURL.deletingPathExtension().appendingPathExtension("md")
                        let pdfURL = saveURL.deletingPathExtension().appendingPathExtension("pdf")
                        let outputDir = saveURL.deletingLastPathComponent()

                        do {
                            try markdown.write(to: mdURL, atomically: true, encoding: .utf8)
                        } catch {
                            if let dir = tempDir { ZipHandler.cleanup(tempDir: dir) }
                            completion(.error("Failed to write markdown: \(error.localizedDescription)"))
                            return
                        }

                        // Step 5: Generate PDF
                        onStateChange(.creatingPDF)

                        let pdfGen = PDFGenerator()
                        pdfGen.generatePDF(from: markdown, to: pdfURL) { [pdfGen] result in
                            _ = pdfGen // prevent premature deallocation
                            if let dir = tempDir { ZipHandler.cleanup(tempDir: dir) }

                            switch result {
                            case .success:
                                completion(.complete(OutputFiles(
                                    markdownURL: mdURL,
                                    pdfURL: pdfURL,
                                    directory: outputDir
                                )))

                            case .failure:
                                // PDF generation failed, but markdown is still saved
                                completion(.complete(OutputFiles(
                                    markdownURL: mdURL,
                                    pdfURL: nil,
                                    directory: outputDir
                                )))
                            }
                        }
                    }
                }

            } catch {
                if let dir = tempDir { ZipHandler.cleanup(tempDir: dir) }
                // Surface detailed error — localizedDescription often loses context
                let detail: String
                if let ramlErr = error as? RAMLParserError {
                    detail = ramlErr.errorDescription ?? "\(ramlErr)"
                } else {
                    let full = "\(error)"
                    // Prefer the full debug representation when localizedDescription is vague
                    detail = full.count > error.localizedDescription.count ? full : error.localizedDescription
                }
                DispatchQueue.main.async {
                    completion(.error(detail))
                }
            }
        }
    }

    // MARK: - Helpers

    private static func suggestedBaseName(from zipURL: URL, apiInfo: APIInfo) -> String {
        let baseName = zipURL.deletingPathExtension().lastPathComponent
        let cleanName = baseName
            .replacingOccurrences(of: "-raml", with: "")
            .replacingOccurrences(of: "(?i)-v?\\d+\\.\\d+\\.\\d+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?i)-v?\\d+\\.\\d+", with: "", options: .regularExpression)
        return "\(cleanName)_ISA"
    }

    private static func presentSaveDialog(baseName: String, completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Save ISA Documents"
        panel.message = "Choose a folder. \(baseName).md and \(baseName).pdf will be created there."
        panel.prompt = "Save Here"

        panel.begin { response in
            if response == .OK, let dir = panel.url {
                let pdfURL = dir.appendingPathComponent("\(baseName).pdf")
                completion(pdfURL)
            } else {
                completion(nil)
            }
        }
    }
}
