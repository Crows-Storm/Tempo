import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let sourceURL = root.appendingPathComponent("Tempo-icon.png")

guard let source = NSImage(contentsOf: sourceURL),
      let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("missing Tempo-icon.png\n", stderr)
    exit(1)
}

let width = cg.width
let height = cg.height
guard let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else {
    fputs("icon pixels unavailable\n", stderr)
    exit(1)
}
let stride = cg.bytesPerRow
let samples = max(cg.bitsPerPixel / 8, 1)

func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
    let offset = y * stride + x * samples
    return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
}

let corners = [pixel(0, 0), pixel(width - 1, 0), pixel(0, height - 1), pixel(width - 1, height - 1)]
let background = (
    r: corners.reduce(0) { $0 + $1.r } / 4,
    g: corners.reduce(0) { $0 + $1.g } / 4,
    b: corners.reduce(0) { $0 + $1.b } / 4
)
let threshold = 18
func isContent(_ x: Int, _ y: Int) -> Bool {
    let color = pixel(x, y)
    return abs(color.r - background.r) > threshold
        || abs(color.g - background.g) > threshold
        || abs(color.b - background.b) > threshold
}

var minX = width, minY = height, maxX = 0, maxY = 0
for y in 0..<height {
    for x in 0..<width where isContent(x, y) {
        minX = min(minX, x)
        minY = min(minY, y)
        maxX = max(maxX, x)
        maxY = max(maxY, y)
    }
}
guard maxX > minX, maxY > minY else {
    fputs("icon bounds not found\n", stderr)
    exit(1)
}

let pad = Int(Double(max(maxX - minX, maxY - minY)) * 0.04)
minX = max(0, minX - pad)
minY = max(0, minY - pad)
maxX = min(width - 1, maxX + pad)
maxY = min(height - 1, maxY + pad)
let boxW = maxX - minX + 1
let boxH = maxY - minY + 1
let side = max(boxW, boxH)
var originX = minX - (side - boxW) / 2
var originY = minY - (side - boxH) / 2
originX = max(0, min(originX, width - side))
originY = max(0, min(originY, height - side))
let crop = CGRect(x: originX, y: originY, width: side, height: side)
guard let cropped = cg.cropping(to: crop) else {
    fputs("crop failed\n", stderr)
    exit(1)
}

func png(from image: CGImage, size: Int) throws -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "TempoIcon", code: 1)
    }
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSImage(cgImage: image, size: NSSize(width: size, height: size)).draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: .zero,
        operation: .copy,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "TempoIcon", code: 2)
    }
    return data
}

let composerDir = root.appendingPathComponent("App/AppIcon.icon/Assets")
try FileManager.default.createDirectory(at: composerDir, withIntermediateDirectories: true)
try png(from: cropped, size: 1024).write(to: composerDir.appendingPathComponent("Tempo-icon.png"))
print("wrote \(side)x\(side) crop from \(width)x\(height) into \(composerDir.path)")
