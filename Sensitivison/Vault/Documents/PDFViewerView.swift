import SwiftUI
import PDFKit

struct PDFViewerView: UIViewRepresentable {
    let document: VaultDocument
    let vault: CryptoVault

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        if let data = FileManager.default.contents(atPath: document.encryptedFilePath),
           let decrypted = try? vault.decrypt(data),
           let pdfDoc = PDFDocument(data: decrypted) {
            pdfView.document = pdfDoc
        }
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
