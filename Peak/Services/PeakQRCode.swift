import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Generates scannable QR images (black modules on white) via Core Image.
enum PeakQRCode {
    /// Encodes `payload` exactly — no truncation or URI wrapping.
    static func image(from payload: String, moduleScale: CGFloat = 12) -> UIImage? {
        guard !payload.isEmpty else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: moduleScale, y: moduleScale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
