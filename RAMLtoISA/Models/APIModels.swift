import Foundation
@_exported import RAMLParserKit

// MARK: - Output Files

struct OutputFiles: Equatable {
    let markdownURL: URL
    let pdfURL: URL?
    let directory: URL
}

// MARK: - Processing State

enum ProcessingState: Equatable {
    case idle
    case extracting
    case parsing
    case generating
    case creatingPDF
    case complete(OutputFiles)
    case error(String)

    static func == (lhs: ProcessingState, rhs: ProcessingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.extracting, .extracting),
             (.parsing, .parsing), (.generating, .generating),
             (.creatingPDF, .creatingPDF):
            return true
        case (.complete(let a), .complete(let b)):
            return a == b
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }

    var statusMessage: String {
        switch self {
        case .idle: return "Drop a RAML .zip file to get started"
        case .extracting: return "Extracting ZIP archive..."
        case .parsing: return "Parsing RAML specification..."
        case .generating: return "Generating ISA document..."
        case .creatingPDF: return "Creating PDF..."
        case .complete: return "Documents generated successfully!"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var isProcessing: Bool {
        switch self {
        case .extracting, .parsing, .generating, .creatingPDF: return true
        default: return false
        }
    }
}
