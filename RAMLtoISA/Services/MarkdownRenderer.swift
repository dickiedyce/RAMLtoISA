import Foundation

/// Converts ISA markdown to styled HTML for PDF rendering
final class MarkdownRenderer {

    /// Converts markdown content to a fully styled HTML document
    static func toHTML(_ markdown: String) -> String {
        let body = convertBody(markdown)

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        \(cssStyles)
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    // MARK: - Markdown Parsing

    private static func convertBody(_ markdown: String) -> String {
        var html = ""
        let lines = markdown.components(separatedBy: "\n")
        var i = 0
        var inTable = false
        var inCodeBlock = false
        var codeBlockContent = ""
        var codeBlockLang = ""
        var inList = false

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Code blocks (``` ... ```)
            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    // End code block
                    if codeBlockLang == "mermaid" {
                        html += "<div class=\"mermaid\">\n\(escapeHTML(codeBlockContent))</div>\n"
                    } else {
                        html += "<pre><code>\(escapeHTML(codeBlockContent))</code></pre>\n"
                    }
                    inCodeBlock = false
                    codeBlockContent = ""
                    codeBlockLang = ""
                } else {
                    // Start code block
                    if inList { html += "</ul>\n"; inList = false }
                    if inTable { html += "</tbody></table>\n"; inTable = false }
                    inCodeBlock = true
                    codeBlockLang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                i += 1
                continue
            }

            if inCodeBlock {
                codeBlockContent += line + "\n"
                i += 1
                continue
            }

            // Empty lines
            if trimmed.isEmpty {
                if inList { html += "</ul>\n"; inList = false }
                if inTable { html += "</tbody></table>\n"; inTable = false }
                i += 1
                continue
            }

            // Headers
            if trimmed.hasPrefix("#") {
                if inList { html += "</ul>\n"; inList = false }
                if inTable { html += "</tbody></table>\n"; inTable = false }
                let level = trimmed.prefix(while: { $0 == "#" }).count
                let text = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                html += "<h\(level)>\(inlineFormat(text))</h\(level)>\n"
                i += 1
                continue
            }

            // Tables
            if trimmed.hasPrefix("|") {
                if inList { html += "</ul>\n"; inList = false }

                if !inTable {
                    // Start table
                    inTable = true
                    let cells = parseTableRow(trimmed)

                    // Check if next line is separator
                    let nextIdx = i + 1
                    let isSeparatorNext = nextIdx < lines.count &&
                        lines[nextIdx].trimmingCharacters(in: .whitespaces).contains("---")

                    if isSeparatorNext {
                        html += "<table>\n<thead><tr>"
                        for cell in cells {
                            html += "<th>\(inlineFormat(cell))</th>"
                        }
                        html += "</tr></thead>\n<tbody>\n"
                        i += 2 // Skip header + separator
                        continue
                    } else {
                        html += "<table>\n<tbody>\n"
                    }
                }

                // Table row
                if !trimmed.contains("---") {
                    let cells = parseTableRow(trimmed)
                    html += "<tr>"
                    for cell in cells {
                        html += "<td>\(inlineFormat(cell))</td>"
                    }
                    html += "</tr>\n"
                }
                i += 1
                continue
            }

            // Unordered lists
            if trimmed.hasPrefix("- ") {
                if inTable { html += "</tbody></table>\n"; inTable = false }
                if !inList {
                    html += "<ul>\n"
                    inList = true
                }
                let text = String(trimmed.dropFirst(2))
                html += "<li>\(inlineFormat(text))</li>\n"
                i += 1
                continue
            }

            // Paragraph text
            if inList { html += "</ul>\n"; inList = false }
            if inTable { html += "</tbody></table>\n"; inTable = false }
            html += "<p>\(inlineFormat(trimmed))</p>\n"
            i += 1
        }

        // Close any open elements
        if inList { html += "</ul>\n" }
        if inTable { html += "</tbody></table>\n" }

        return html
    }

    // MARK: - Inline Formatting

    private static func inlineFormat(_ text: String) -> String {
        var result = escapeHTML(text)

        // Bold: **text**
        result = result.replacingOccurrences(
            of: "\\*\\*(.+?)\\*\\*",
            with: "<strong>$1</strong>",
            options: .regularExpression
        )

        // Italic: *text*
        result = result.replacingOccurrences(
            of: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)",
            with: "<em>$1</em>",
            options: .regularExpression
        )

        // Inline code: `text`
        result = result.replacingOccurrences(
            of: "`(.+?)`",
            with: "<code>$1</code>",
            options: .regularExpression
        )

        return result
    }

    // MARK: - Helpers

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func parseTableRow(_ row: String) -> [String] {
        row.split(separator: "|", omittingEmptySubsequences: false)
            .dropFirst().dropLast()
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - CSS

    private static let cssStyles = """
    * {
        box-sizing: border-box;
    }

    html, body {
        margin: 0;
        padding: 0;
    }

    body {
        font-family: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', Helvetica, Arial, sans-serif;
        font-size: 11pt;
        line-height: 1.6;
        color: #1d1d1f;
        padding: 0;  /* margins handled by NSPrintInfo */
    }

    h1 {
        font-size: 22pt;
        font-weight: 700;
        color: #1d1d1f;
        border-bottom: 3px solid #0071e3;
        padding-bottom: 8px;
        margin-top: 0;
        margin-bottom: 16px;
        page-break-after: avoid;
    }

    h2 {
        font-size: 17pt;
        font-weight: 600;
        color: #1d1d1f;
        margin-top: 28px;
        margin-bottom: 12px;
        border-bottom: 1px solid #d2d2d7;
        padding-bottom: 6px;
        page-break-after: avoid;
    }

    h3 {
        font-size: 14pt;
        font-weight: 600;
        color: #333;
        margin-top: 22px;
        margin-bottom: 10px;
        page-break-after: avoid;
    }

    h4 {
        font-size: 12pt;
        font-weight: 600;
        color: #444;
        margin-top: 18px;
        margin-bottom: 8px;
        page-break-after: avoid;
    }

    p {
        margin: 6px 0;
        page-break-inside: avoid;
    }

    ul {
        margin: 6px 0;
        padding-left: 24px;
    }

    li {
        margin: 3px 0;
    }

    table {
        width: 100%;
        border-collapse: collapse;
        margin: 12px 0;
        font-size: 10pt;
        page-break-inside: auto;
    }

    thead {
        background-color: #f5f5f7;
    }

    th {
        text-align: left;
        padding: 8px 10px;
        border: 1px solid #d2d2d7;
        font-weight: 600;
        color: #1d1d1f;
        white-space: nowrap;
    }

    td {
        padding: 6px 10px;
        border: 1px solid #d2d2d7;
        vertical-align: top;
        word-break: break-word;
    }

    tr {
        page-break-inside: avoid;
    }

    tr:nth-child(even) {
        background-color: #fafafa;
    }

    code {
        background-color: #f5f5f7;
        padding: 2px 6px;
        border-radius: 4px;
        font-family: 'SF Mono', Menlo, Monaco, monospace;
        font-size: 9.5pt;
        color: #d63384;
        word-break: break-all;
    }

    pre {
        background-color: #f5f5f7;
        padding: 14px;
        border-radius: 8px;
        overflow-x: hidden;
        overflow-wrap: break-word;
        white-space: pre-wrap;
        margin: 12px 0;
        border: 1px solid #e5e5ea;
        page-break-inside: avoid;
    }

    pre code {
        background: none;
        padding: 0;
        color: #1d1d1f;
        font-size: 9pt;
        word-break: break-all;
    }

    strong {
        font-weight: 600;
    }

    .mermaid {
        text-align: center;
        margin: 16px 0;
        page-break-inside: avoid;
        background-color: #f5f5f7;
        padding: 12px;
        border-radius: 8px;
        border: 1px solid #e5e5ea;
        font-family: 'SF Mono', Menlo, Monaco, monospace;
        font-size: 9pt;
        white-space: pre-wrap;
        text-align: left;
        color: #666;
    }

    .mermaid svg {
        max-width: 100%;
    }
    """
}
