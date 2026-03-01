import Foundation

// MARK: - API Parameter

struct APIParameter: Identifiable, Codable {
    let id = UUID()
    let name: String
    let location: String      // query, path, header
    let required: Bool
    let schemaType: String
    let description: String
    let example: String?
    let minimum: Int?
    let maximum: Int?

    enum CodingKeys: String, CodingKey {
        case name, location, required, schemaType, description, example, minimum, maximum
    }
}

// MARK: - API Response

struct APIResponse: Identifiable, Codable {
    let id = UUID()
    let statusCode: String
    let description: String
    let contentType: String?

    enum CodingKeys: String, CodingKey {
        case statusCode, description, contentType
    }
}

// MARK: - Requirement

struct Requirement: Identifiable, Codable {
    let id = UUID()
    let reqId: String
    let reqType: RequirementType
    let useCase: String
    let description: String
    let acceptanceCriteria: String

    enum CodingKeys: String, CodingKey {
        case reqId, reqType, useCase, description, acceptanceCriteria
    }
}

enum RequirementType: String, Codable {
    case functional = "FR"
    case nonFunctional = "NFR"
}

// MARK: - Endpoint

struct Endpoint: Identifiable, Codable {
    let id = UUID()
    let path: String
    let method: String
    let summary: String
    let description: String
    let parameters: [APIParameter]
    let responses: [APIResponse]
    let requirements: [Requirement]
    let securitySchemes: [String]

    enum CodingKeys: String, CodingKey {
        case path, method, summary, description, parameters, responses, requirements, securitySchemes
    }
}

// MARK: - API Info

struct APIInfo: Codable {
    var title: String
    var version: String
    var description: String
    var securitySchemes: [String: SecurityScheme]

    init(title: String = "API", version: String = "1.0", description: String = "", securitySchemes: [String: SecurityScheme] = [:]) {
        self.title = title
        self.version = version
        self.description = description
        self.securitySchemes = securitySchemes
    }
}

struct SecurityScheme: Codable {
    let type: String
    let scheme: String
    let description: String
}

// MARK: - Parsed Specification

struct ParsedSpec {
    let apiInfo: APIInfo
    let endpoints: [Endpoint]
    let requirements: [Requirement]
}

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
