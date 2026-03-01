import Foundation
import Yams

/// Parses RAML 1.0 and OpenAPI specifications into structured data
final class RAMLParser {

    private let fileURL: URL
    private var spec: [String: Any] = [:]
    private var endpoints: [Endpoint] = []
    private var requirements: [Requirement] = []
    private var securitySchemes: [String: SecurityScheme] = [:]

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    // MARK: - Include Placeholder

    /// Sentinel prefix used to mark !include paths in pre-processed YAML
    private static let includeSentinel = "__RAML_INCLUDE__:"

    // MARK: - Public

    func parse() throws -> ParsedSpec {
        let rawContent: String
        do {
            rawContent = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            // Fallback to Latin-1 if UTF-8 fails (rare but possible with ZIPFoundation)
            guard let latin1 = try? String(contentsOf: fileURL, encoding: .isoLatin1) else {
                throw RAMLParserError.fileNotFound("Cannot read: \(fileURL.path)")
            }
            print("[RAMLParser] Read root file with Latin-1 fallback")
            rawContent = latin1
        }
        let baseDir = fileURL.deletingLastPathComponent()

        // Pre-process: replace `!include <path>` with a placeholder string
        // so that Yams can parse without choking on the custom tag.
        let preprocessed = Self.preprocessIncludes(rawContent)

        // Parse with standard Yams (no custom tags)
        let loadResult: Any?
        do {
            loadResult = try Yams.load(yaml: preprocessed)
        } catch {
            let detail = Self.describeYamlError(error)
            print("[RAMLParser] Root YAML parse failed: \(detail)")
            print("[RAMLParser] First 5 lines of preprocessed content:")
            preprocessed.components(separatedBy: "\n").prefix(5).enumerated().forEach { i, line in
                print("  \(i+1): \(line)")
            }
            throw RAMLParserError.invalidYAML("YAML parse error: \(detail)")
        }

        guard let parsed = loadResult as? [String: Any] else {
            throw RAMLParserError.invalidYAML("Failed to parse YAML content as a mapping")
        }

        // Post-process: walk the tree and resolve include placeholders
        // (non-fatal — individual include failures are logged but don't abort)
        guard let resolved = resolveIncludes(in: parsed, baseDir: baseDir) as? [String: Any] else {
            throw RAMLParserError.invalidYAML("Root YAML element is not a mapping after include resolution")
        }

        self.spec = resolved

        let apiInfo = extractAPIInfo()
        extractSecuritySchemes()
        extractEndpoints()

        var info = apiInfo
        info.securitySchemes = securitySchemes

        return ParsedSpec(
            apiInfo: info,
            endpoints: endpoints,
            requirements: requirements
        )
    }

    // MARK: - Pre-processing

    /// Replaces `!include <path>` with `"__RAML_INCLUDE__:<path>"` in raw YAML
    /// so that Yams treats it as a plain string instead of an unknown tag.
    /// Also sanitises tab characters which are illegal in YAML indentation.
    private static func preprocessIncludes(_ yaml: String) -> String {
        // 1. Replace tabs with spaces (YAML forbids tab indentation, but RAML
        //    files in the wild sometimes contain stray tabs)
        var sanitised = yaml.replacingOccurrences(of: "\t", with: "  ")

        // 2. Match: !include <path>  (path continues to end of line)
        let pattern = "!include\\s+(.+?)\\s*$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            return sanitised
        }
        let range = NSRange(sanitised.startIndex..., in: sanitised)
        return regex.stringByReplacingMatches(
            in: sanitised,
            range: range,
            withTemplate: "\"\(includeSentinel)$1\""
        )
    }

    // MARK: - Include Resolution

    /// Recursively walks the parsed YAML tree and resolves include placeholders.
    /// Failures in individual includes are logged and replaced with a placeholder
    /// so that one broken file doesn't abort the entire parse.
    private func resolveIncludes(in value: Any, baseDir: URL) -> Any {
        if let str = value as? String, str.hasPrefix(Self.includeSentinel) {
            let path = String(str.dropFirst(Self.includeSentinel.count))
            do {
                return try resolveIncludeFile(path, baseDir: baseDir)
            } catch {
                print("[RAMLParser] Warning: Failed to resolve include '\(path)': \(error)")
                return "[Include error: \(path)]"
            }
        }
        if let dict = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, val) in dict {
                result[key] = resolveIncludes(in: val, baseDir: baseDir)
            }
            return result
        }
        if let arr = value as? [Any] {
            return arr.map { resolveIncludes(in: $0, baseDir: baseDir) }
        }
        return value
    }

    /// Loads an included file, parsing YAML/JSON/text as appropriate
    private func resolveIncludeFile(_ path: String, baseDir: URL) throws -> Any {
        let includeURL = baseDir.appendingPathComponent(path)

        guard FileManager.default.fileExists(atPath: includeURL.path) else {
            print("[RAMLParser] Include file not found: \(path) (resolved: \(includeURL.path))")
            return "[Include not found: \(path)]"
        }

        let content: String
        do {
            content = try String(contentsOf: includeURL, encoding: .utf8)
        } catch {
            // Try Latin-1 as fallback for files with non-UTF8 encoding
            guard let latin1 = try? String(contentsOf: includeURL, encoding: .isoLatin1) else {
                print("[RAMLParser] Cannot read file: \(path)")
                return "[Unreadable: \(path)]"
            }
            print("[RAMLParser] Read \(path) with Latin-1 fallback")
            return latin1
        }

        let ext = includeURL.pathExtension.lowercased()

        if ext == "raml" || ext == "yaml" || ext == "yml" {
            let preprocessed = Self.preprocessIncludes(content)
            do {
                if let parsed = try Yams.load(yaml: preprocessed) {
                    return resolveIncludes(in: parsed, baseDir: includeURL.deletingLastPathComponent())
                }
            } catch {
                print("[RAMLParser] YAML parse failed for \(path): \(Self.describeYamlError(error))")
            }
            return content
        } else if ext == "json" {
            if let data = content.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) {
                return json
            }
            return content
        } else {
            // Raw content (markdown, text, etc.)
            return content
        }
    }

    /// Extracts a human-readable description from a Yams error
    private static func describeYamlError(_ error: Error) -> String {
        let desc = "\(error)"
        // Yams errors include context, problem, line, column
        if desc.contains("line") || desc.contains("column") {
            return desc
        }
        return error.localizedDescription
    }

    // MARK: - API Info Extraction

    private func extractAPIInfo() -> APIInfo {
        let info = spec["info"] as? [String: Any] ?? [:]
        let folderMeta = extractFolderMetadata()

        let title = (info["title"] as? String)
            ?? (spec["title"] as? String)
            ?? folderMeta.name
            ?? "API"

        let version = (info["version"] as? String)
            ?? (spec["version"] as? String)
            ?? folderMeta.version
            ?? "1.0"

        let description = (info["description"] as? String)
            ?? (spec["description"] as? String)
            ?? ""

        return APIInfo(title: title, version: version, description: description)
    }

    private func extractFolderMetadata() -> (name: String?, version: String?) {
        let folderName = fileURL.deletingLastPathComponent().lastPathComponent

        let patterns: [String] = [
            "^(.+?)-(v?\\d+\\.\\d+\\.\\d+)(-raml)?$",
            "^(.+?)-(v?\\d+\\.\\d+)(-raml)?$",
            "^(.+?)-(v?\\d+)(-raml)?$",
            "^(.+?)-raml-(v?\\d+\\.\\d+\\.\\d+)$",
            "^(.+?)-raml-(v?\\d+\\.\\d+)$",
            "^(.+?)-raml-(v?\\d+)$",
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: folderName, range: NSRange(folderName.startIndex..., in: folderName)) {
                let name = match.range(at: 1).location != NSNotFound
                    ? String(folderName[Range(match.range(at: 1), in: folderName)!])
                    : nil
                let version = match.range(at: 2).location != NSNotFound
                    ? String(folderName[Range(match.range(at: 2), in: folderName)!])
                    : nil
                return (name, version)
            }
        }

        return (nil, nil)
    }

    // MARK: - Security Schemes

    private func extractSecuritySchemes() {
        // OpenAPI format
        if let components = spec["components"] as? [String: Any],
           let schemes = components["securitySchemes"] as? [String: Any] {
            for (name, def) in schemes {
                guard let schemeDef = def as? [String: Any] else { continue }
                securitySchemes[name] = SecurityScheme(
                    type: schemeDef["type"] as? String ?? "",
                    scheme: schemeDef["scheme"] as? String ?? "",
                    description: schemeDef["description"] as? String ?? ""
                )
            }
        }

        // RAML format
        if let securedBy = spec["securedBy"] {
            let schemeStr: String
            if let arr = securedBy as? [Any] {
                schemeStr = arr.compactMap { "\($0)" }.joined(separator: ", ")
            } else {
                schemeStr = "\(securedBy)"
            }
            securitySchemes["default"] = SecurityScheme(
                type: "RAML Security",
                scheme: schemeStr,
                description: "RAML security scheme"
            )
        }
    }

    // MARK: - Endpoint Extraction

    private func extractEndpoints() {
        let globalSecurity = spec["security"] as? [[String: Any]] ?? []

        // OpenAPI format: paths object
        if let paths = spec["paths"] as? [String: Any], !paths.isEmpty {
            for (path, pathItem) in paths {
                guard let methods = pathItem as? [String: Any] else { continue }
                for (method, operation) in methods {
                    let m = method.lowercased()
                    guard ["get", "post", "put", "delete", "patch"].contains(m),
                          let op = operation as? [String: Any] else { continue }
                    let endpoint = buildOpenAPIEndpoint(path: path, method: m.uppercased(), operation: op, globalSecurity: globalSecurity)
                    endpoints.append(endpoint)
                }
            }
        } else {
            // RAML 1.0 format: top-level keys starting with /
            extractRAMLEndpoints(from: spec, basePath: "")
        }
    }

    private func extractRAMLEndpoints(from dict: [String: Any], basePath: String) {
        for (key, value) in dict {
            guard key.hasPrefix("/"), let resource = value as? [String: Any] else { continue }

            let fullPath = basePath + key

            // Check for HTTP methods
            for method in ["get", "post", "put", "delete", "patch"] {
                if let operation = resource[method] as? [String: Any] {
                    let endpoint = buildRAMLEndpoint(path: fullPath, method: method.uppercased(), operation: operation)
                    endpoints.append(endpoint)
                }
            }

            // Recursively process nested paths
            extractRAMLEndpoints(from: resource, basePath: fullPath)
        }
    }

    // MARK: - RAML Endpoint Builder

    private func buildRAMLEndpoint(path: String, method: String, operation: [String: Any]) -> Endpoint {
        let displayName = operation["displayName"] as? String ?? ""
        let description = operation["description"] as? String ?? ""

        // Extract requirements from description
        let reqs = extractRequirementsFromText(description)
        requirements.append(contentsOf: reqs)

        // Parameters
        var params: [APIParameter] = []

        if let queryParams = operation["queryParameters"] as? [String: Any] {
            for (name, def) in queryParams {
                let paramDef = def as? [String: Any] ?? [:]
                params.append(APIParameter(
                    name: name,
                    location: "query",
                    required: paramDef["required"] as? Bool ?? true,
                    schemaType: paramDef["type"] as? String ?? "string",
                    description: paramDef["description"] as? String ?? "",
                    example: paramDef["example"].map { "\($0)" },
                    minimum: paramDef["minimum"] as? Int,
                    maximum: paramDef["maximum"] as? Int
                ))
            }
        }

        if let uriParams = operation["uriParameters"] as? [String: Any] {
            for (name, def) in uriParams {
                let paramDef = def as? [String: Any] ?? [:]
                params.append(APIParameter(
                    name: name,
                    location: "path",
                    required: paramDef["required"] as? Bool ?? true,
                    schemaType: paramDef["type"] as? String ?? "string",
                    description: paramDef["description"] as? String ?? "",
                    example: paramDef["example"].map { "\($0)" },
                    minimum: nil,
                    maximum: nil
                ))
            }
        }

        // Responses
        var responses: [APIResponse] = []
        if let respDefs = operation["responses"] as? [String: Any] {
            for (statusCode, def) in respDefs {
                let respDef = def as? [String: Any] ?? [:]
                var contentType: String?
                if let body = respDef["body"] as? [String: Any] {
                    contentType = body.keys.first
                }
                responses.append(APIResponse(
                    statusCode: "\(statusCode)",
                    description: respDef["description"] as? String ?? "",
                    contentType: contentType
                ))
            }
        }

        // Security
        var secSchemes: [String] = []
        if let securedBy = operation["securedBy"] as? [Any] {
            secSchemes = securedBy.compactMap { "\($0)" }
        }

        return Endpoint(
            path: path,
            method: method,
            summary: displayName,
            description: description,
            parameters: params,
            responses: responses,
            requirements: reqs,
            securitySchemes: secSchemes
        )
    }

    // MARK: - OpenAPI Endpoint Builder

    private func buildOpenAPIEndpoint(path: String, method: String, operation: [String: Any], globalSecurity: [[String: Any]]) -> Endpoint {
        let summary = operation["summary"] as? String ?? ""
        let description = operation["description"] as? String ?? ""

        let reqs = extractRequirementsFromText(description)
        requirements.append(contentsOf: reqs)

        // Parameters
        let rawParams = operation["parameters"] as? [[String: Any]] ?? []
        let params = rawParams.map { param -> APIParameter in
            let schema = param["schema"] as? [String: Any] ?? [:]
            return APIParameter(
                name: param["name"] as? String ?? "",
                location: param["in"] as? String ?? "",
                required: param["required"] as? Bool ?? false,
                schemaType: schema["type"] as? String ?? "string",
                description: param["description"] as? String ?? "",
                example: (schema["example"]).map { "\($0)" },
                minimum: schema["minimum"] as? Int,
                maximum: schema["maximum"] as? Int
            )
        }

        // Responses
        var responses: [APIResponse] = []
        if let respDefs = operation["responses"] as? [String: Any] {
            for (statusCode, def) in respDefs {
                let respDef = def as? [String: Any] ?? [:]
                let content = respDef["content"] as? [String: Any] ?? [:]
                responses.append(APIResponse(
                    statusCode: "\(statusCode)",
                    description: respDef["description"] as? String ?? "",
                    contentType: content.keys.first
                ))
            }
        }

        // Security
        let security = operation["security"] as? [[String: Any]] ?? globalSecurity
        let secSchemes = security.flatMap { $0.keys }

        return Endpoint(
            path: path,
            method: method,
            summary: summary,
            description: description,
            parameters: params,
            responses: responses,
            requirements: reqs,
            securitySchemes: secSchemes
        )
    }

    // MARK: - Requirements Extraction

    private func extractRequirementsFromText(_ text: String) -> [Requirement] {
        guard !text.isEmpty else { return [] }

        var results: [Requirement] = []
        let lines = text.components(separatedBy: "\n")
        var inFRTable = false
        var inNFRTable = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.contains("Functional Requirements") {
                inFRTable = true
                inNFRTable = false
                continue
            }
            if trimmed.contains("Non-Functional Requirements") || trimmed.contains("Specific Non-Functional Requirements") {
                inFRTable = false
                inNFRTable = true
                continue
            }

            guard trimmed.hasPrefix("|") && trimmed.contains("|") else { continue }
            if trimmed.contains("---") { continue }

            let parts = trimmed
                .split(separator: "|", omittingEmptySubsequences: false)
                .dropFirst().dropLast()
                .map { $0.trimmingCharacters(in: .whitespaces) }

            let skipValues: Set<String> = ["#", "ID", "Use Case", "Category"]
            guard let first = parts.first, !skipValues.contains(first) else { continue }

            if inFRTable && parts.count >= 4 {
                results.append(Requirement(
                    reqId: parts[0],
                    reqType: .functional,
                    useCase: parts[1],
                    description: parts[2],
                    acceptanceCriteria: parts[3]
                ))
            }

            if inNFRTable && parts.count >= 3 {
                results.append(Requirement(
                    reqId: parts[0],
                    reqType: .nonFunctional,
                    useCase: parts.count > 1 ? parts[1] : "",
                    description: parts.count > 2 ? parts[2] : "",
                    acceptanceCriteria: ""
                ))
            }
        }

        return results
    }
}

// MARK: - Errors

enum RAMLParserError: LocalizedError {
    case invalidYAML(String)
    case fileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidYAML(let msg): return "Invalid YAML: \(msg)"
        case .fileNotFound(let path): return "File not found: \(path)"
        }
    }
}
