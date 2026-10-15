import AppKit
import CoreText

// 原生輸入來源尺寸：22×16 pt。黑色圓角鍵帽＋透明「中」，由系統按外觀染色。
let output = CommandLine.arguments.dropFirst().first ?? "build/InputMenuTemplate.tiff"
let size = NSSize(width: 22, height: 16)
let image = NSImage(size: size)
let text = NSAttributedString(string: "中", attributes: [
    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
    .foregroundColor: NSColor.black,
])
let line = CTLineCreateWithAttributedString(text)
let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)

for scale in [1, 2] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 22 * scale,
                              pixelsHigh: 16 * scale, bitsPerSample: 8, samplesPerPixel: 4,
                              hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
    let context = CGContext(data: rep.bitmapData, width: rep.pixelsWide,
                            height: rep.pixelsHigh, bitsPerComponent: 8,
                            bytesPerRow: rep.bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    context.setFillColor(NSColor.black.cgColor)
    context.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size),
                          cornerWidth: 4.5, cornerHeight: 4.5, transform: nil))
    context.fillPath()
    context.setBlendMode(.destinationOut)
    context.textPosition = CGPoint(x: (size.width - bounds.width) / 2 - bounds.minX,
                                   y: (size.height - bounds.height) / 2 - bounds.minY)
    CTLineDraw(line, context)
    rep.size = size
    image.addRepresentation(rep)
}
try image.tiffRepresentation!.write(to: URL(fileURLWithPath: output))
print("Menu icon: \(output) (22×16 pt, 1×/2×)")
