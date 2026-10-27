import AppKit

let size = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()

let glyph = "拼" as NSString
let font = NSFont(name: "Songti SC Bold", size: 560) ?? NSFont.systemFont(ofSize: 560, weight: .bold)
let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor(red: 0xFD / 255, green: 0xFC / 255, blue: 0xFC / 255, alpha: 1),
]
let glyphSize = glyph.size(withAttributes: attributes)
glyph.draw(at: NSPoint(x: (CGFloat(size) - glyphSize.width) / 2, y: (CGFloat(size) - glyphSize.height) / 2 + 70),
           withAttributes: attributes)

let underline = NSBezierPath()
underline.move(to: NSPoint(x: 312, y: 180))
underline.line(to: NSPoint(x: 712, y: 180))
underline.lineWidth = 22
underline.setLineDash([22, 26], count: 2, phase: 0)
underline.lineCapStyle = .round
NSColor(red: 0xE8 / 255, green: 0x82 / 255, blue: 0x6D / 255, alpha: 1).setStroke()
underline.stroke()
NSGraphicsContext.restoreGraphicsState()

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
