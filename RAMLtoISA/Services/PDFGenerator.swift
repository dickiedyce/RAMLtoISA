import Foundation
import AppKit
import WebKit

/// Generates PDF documents from HTML content using WKWebView + NSPrintOperation
/// for proper A4 multi-page output.
final class PDFGenerator: NSObject {

    private var webView: WKWebView?
    private var completion: ((Result<Data, Error>) -> Void)?
    private var timeoutWorkItem: DispatchWorkItem?
    private var outputURL: URL?

    /// Generates a PDF from markdown content
    func generatePDF(from markdown: String, to outputURL: URL, completion: @escaping (Result<Data, Error>) -> Void) {
        let html = MarkdownRenderer.toHTML(markdown)
        self.outputURL = outputURL
        generatePDFFromHTML(html, completion: completion)
    }

    /// Generates a PDF from HTML content
    private func generatePDFFromHTML(_ html: String, completion: @escaping (Result<Data, Error>) -> Void) {
        self.completion = completion

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let config = WKWebViewConfiguration()
            config.suppressesIncrementalRendering = true

            // A4 width in points for layout.  Height is generous so content
            // flows naturally — pagination is handled by the print operation.
            let a4Width: CGFloat = 595.28

            let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: a4Width, height: 842), configuration: config)
            wv.navigationDelegate = self
            self.webView = wv

            let timeout = DispatchWorkItem { [weak self] in
                self?.finishWithError(PDFGeneratorError.timeout)
            }
            self.timeoutWorkItem = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: timeout)

            wv.loadHTMLString(html, baseURL: nil)
        }
    }

    private func createPDF() {
        guard let webView, let outputURL else {
            finishWithError(PDFGeneratorError.noWebView)
            return
        }

        // A4 in points
        let pageWidth:  CGFloat = 595.28
        let pageHeight: CGFloat = 841.89

        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: pageWidth, height: pageHeight)
        printInfo.topMargin    = 56.69   // ~20mm
        printInfo.bottomMargin = 56.69
        printInfo.leftMargin   = 42.52   // ~15mm
        printInfo.rightMargin  = 42.52
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination   = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered   = false
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = outputURL

        let printOp = webView.printOperation(with: printInfo)
        printOp.showsPrintPanel = false
        printOp.showsProgressPanel = false

        printOp.runModal(for: NSWindow(), delegate: self,
                         didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
                         contextInfo: nil)
    }

    @objc private func printOperationDidRun(
        _ op: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?
    ) {
        timeoutWorkItem?.cancel()
        if success, let outputURL, let data = try? Data(contentsOf: outputURL) {
            completion?(.success(data))
        } else if success {
            // File was written by the print op; report success with empty data
            // (caller already has the URL)
            completion?(.success(Data()))
        } else {
            completion?(.failure(PDFGeneratorError.printFailed))
        }
        cleanup()
    }

    private func finishWithError(_ error: Error) {
        timeoutWorkItem?.cancel()
        completion?(.failure(error))
        cleanup()
    }

    private func cleanup() {
        webView?.navigationDelegate = nil
        webView = nil
        completion = nil
        timeoutWorkItem = nil
        outputURL = nil
    }
}

// MARK: - WKNavigationDelegate

extension PDFGenerator: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Allow layout to settle before printing
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.createPDF()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishWithError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishWithError(error)
    }
}

// MARK: - Errors

enum PDFGeneratorError: LocalizedError {
    case noWebView
    case timeout
    case printFailed

    var errorDescription: String? {
        switch self {
        case .noWebView: return "WebView not available for PDF rendering"
        case .timeout: return "PDF generation timed out"
        case .printFailed: return "Print-to-PDF operation failed"
        }
    }
}
