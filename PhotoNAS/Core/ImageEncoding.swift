import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

#if canImport(libwebp)
import libwebp
#endif

enum ImageEncoding {
    static var isWebPAvailable: Bool {
        #if canImport(libwebp)
        return true
        #else
        return false
        #endif
    }

    static func encode(image: CGImage, format: ThumbnailFormat, quality: Double) -> Data? {
        switch format {
        case .webp:
            if let data = encodeWebP(image, quality: quality) { return data }
            return encodeJPEG(image, quality: quality)
        case .jpeg:
            return encodeJPEG(image, quality: quality)
        }
    }

    /// 根据文件头判断真实编码格式（WebP 编码失败时回退 JPEG 也能正确返回类型）
    static func contentType(of data: Data, fallback: ThumbnailFormat) -> String {
        if data.count >= 12 {
            let header = [UInt8](data.prefix(4))
            if header == [0x52, 0x49, 0x46, 0x46] { return ThumbnailFormat.webp.contentType }
            if header[0] == 0xFF, header[1] == 0xD8 { return ThumbnailFormat.jpeg.contentType }
        }
        return fallback.contentType
    }

    static func encodeJPEG(_ image: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        let uti = UTType.jpeg.identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(output, uti, 1, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    static func encodeWebP(_ image: CGImage, quality: Double) -> Data? {
        #if canImport(libwebp)
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, width < 20000, height < 20000 else { return nil }

        let bytesPerRow = width * 4
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        guard let pixels = context.data else { return nil }

        var output: UnsafeMutablePointer<UInt8>? = nil
        let result = WebPEncodeRGBA(
            pixels.assumingMemoryBound(to: UInt8.self),
            Int32(width),
            Int32(height),
            Int32(bytesPerRow),
            Float(min(max(quality * 100, 1), 100)),
            &output
        )
        let byteCount = Int(result)
        guard byteCount > 0, let pointer = output else { return nil }
        defer { WebPFree(pointer) }
        return Data(bytes: pointer, count: byteCount)
        #else
        return nil
        #endif
    }
}
