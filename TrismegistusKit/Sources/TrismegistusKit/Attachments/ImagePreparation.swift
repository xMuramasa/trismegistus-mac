#if canImport(ImageIO)
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns any image file's bytes into what the relay takes: longest edge at most 2048 px; PNG stays PNG while it is at
/// most 2 MiB, else JPEG 0.85; other formats (HEIC, TIFF, WebP, BMP, …) become JPEG, or PNG when they have alpha; a GIF
/// is sent as is up to 2 MiB, else its first frame. Re-encoding drops the metadata (EXIF, GPS); the EXIF orientation
/// is applied first. Mac only (ImageIO).
public enum ImagePreparation {
    public enum Failure: Error, Equatable {
        case notAnImage, tooLarge

        /// The tray's words.
        public var message: String {
            switch self {
            case .notAnImage: "Not an image"
            case .tooLarge: "Too large"
            }
        }
    }

    public static let maxEdge = 2048
    public static let maxKeptBytes = 2 << 20
    public static let jpegQuality = 0.85

    public static func prepare(_ data: Data) throws(Failure) -> ImageUpload {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
            let type = CGImageSourceGetType(source).flatMap({ UTType($0 as String) }), type.conforms(to: .image)
        else { throw .notAnImage }

        if type.conforms(to: .gif), data.count <= maxKeptBytes, let size = pixelSize(source) {
            return ImageUpload(data: data, mime: "image/gif", width: size.width, height: size.height)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxEdge, pixelSize(source).map { max($0.width, $0.height) } ?? maxEdge),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw .notAnImage }
        let alpha = ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)

        if type.conforms(to: .png) || (alpha && !type.conforms(to: .jpeg)) {
            if let png = encode(image, as: .png), png.count <= maxKeptBytes || !type.conforms(to: .png) {
                return try checked(ImageUpload(data: png, mime: "image/png", width: image.width, height: image.height))
            }
        }
        guard let jpeg = encode(alpha ? flattened(image) ?? image : image, as: .jpeg) else { throw .notAnImage }
        return try checked(ImageUpload(data: jpeg, mime: "image/jpeg", width: image.width, height: image.height))
    }

    private static func checked(_ upload: ImageUpload) throws(Failure) -> ImageUpload {
        guard upload.data.count <= ImageUpload.maxMessageBytes else { throw .tooLarge }
        return upload
    }

    private static func pixelSize(_ source: CGImageSource) -> (width: Int, height: Int)? {
        let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        guard let w = p?[kCGImagePropertyPixelWidth] as? Int, let h = p?[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0
        else { return nil }
        return (w, h)
    }

    /// No properties passed: nothing of the source's metadata is written.
    private static func encode(_ image: CGImage, as type: UTType) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
        let props: [CFString: Any] = type == .jpeg ? [kCGImageDestinationLossyCompressionQuality: jpegQuality] : [:]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    /// On white: JPEG has no alpha, and ImageIO would turn transparent pixels black.
    private static func flattened(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }
}
#endif
