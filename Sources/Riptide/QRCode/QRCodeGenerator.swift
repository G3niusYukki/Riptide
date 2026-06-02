import AppKit
import CoreImage

/// Generates black-on-white QR codes as NSImage.
/// Wraps Apple's CIQRCodeGenerator. The output `size` is the longest edge
/// in points (1× scale); upscale as needed for retina displays.
public enum QRCodeGenerator {
    /// Returns nil on encoder error (empty string, encoding overflow, etc.).
    public static func generate(text: String, size: CGFloat) -> NSImage? {
        guard !text.isEmpty,
              let data = text.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")  // M = ~15% error correction
        guard let output = filter.outputImage else { return nil }
        let extent = output.extent
        guard extent.width > 0 else { return nil }
        let scale = size / extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }
}
