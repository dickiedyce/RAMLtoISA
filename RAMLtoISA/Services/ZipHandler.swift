import Foundation
import ZIPFoundation

/// Handles ZIP file extraction and RAML file discovery
final class ZipHandler {

    /// Extracts a ZIP file to a temporary directory and locates the main RAML file
    /// - Parameter zipURL: URL to the .zip file
    /// - Returns: Tuple of (temp directory URL, main RAML file URL)
    static func extractAndFindRAML(zipURL: URL) throws -> (tempDir: URL, ramlFile: URL) {
        let fileManager = FileManager.default

        // Create a unique temp directory
        let tempBase = fileManager.temporaryDirectory
        let tempDir = tempBase.appendingPathComponent("raml-to-isa-\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Extract the ZIP
        try fileManager.unzipItem(at: zipURL, to: tempDir)

        // Find api.raml - check root and one level deep
        let ramlFile = try findRAMLFile(in: tempDir)

        return (tempDir, ramlFile)
    }

    /// Searches for the main RAML file in the extracted directory
    private static func findRAMLFile(in directory: URL) throws -> URL {
        let fileManager = FileManager.default

        // Priority 1: api.raml at root
        let rootRAML = directory.appendingPathComponent("api.raml")
        if fileManager.fileExists(atPath: rootRAML.path) {
            return rootRAML
        }

        // Priority 2: api.raml one directory down (common in zip archives)
        if let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) {
            for item in contents {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                    let nestedRAML = item.appendingPathComponent("api.raml")
                    if fileManager.fileExists(atPath: nestedRAML.path) {
                        return nestedRAML
                    }
                }
            }
        }

        // Priority 3: Any .raml file at root
        if let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            if let raml = contents.first(where: { $0.pathExtension.lowercased() == "raml" }) {
                return raml
            }

            // Priority 4: Any .raml file one level down
            for item in contents {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                    if let subContents = try? fileManager.contentsOfDirectory(at: item, includingPropertiesForKeys: nil),
                       let raml = subContents.first(where: { $0.pathExtension.lowercased() == "raml" }) {
                        return raml
                    }
                }
            }
        }

        throw ZipHandlerError.noRAMLFound
    }

    /// Cleans up a temporary directory
    static func cleanup(tempDir: URL) {
        try? FileManager.default.removeItem(at: tempDir)
    }
}

enum ZipHandlerError: LocalizedError {
    case noRAMLFound
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noRAMLFound: return "No .raml file found in the ZIP archive"
        case .extractionFailed(let msg): return "ZIP extraction failed: \(msg)"
        }
    }
}
