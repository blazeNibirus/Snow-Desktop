import AppKit
let outputDirectory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = CGFloat(size)
    NSColor(calibratedRed: 0.10, green: 0.22, blue: 0.35, alpha: 1).setFill()
    NSBezierPath(roundedRect: CGRect(x: s * 0.05, y: s * 0.05, width: s * 0.9, height: s * 0.9), xRadius: s * 0.2, yRadius: s * 0.2).fill()
    NSColor(calibratedRed: 0.88, green: 0.96, blue: 1, alpha: 1).setStroke()
    let path = NSBezierPath(); path.lineWidth = s * 0.035; path.lineCapStyle = .round; path.lineJoinStyle = .round
    for i in 0..<6 {
        let angle = CGFloat(i) * .pi / 3
        func point(_ distance: CGFloat, _ offset: CGFloat = 0) -> CGPoint {
            CGPoint(x: s / 2 + cos(angle + offset) * s * distance, y: s / 2 + sin(angle + offset) * s * distance)
        }
        path.move(to: point(0)); path.line(to: point(0.31))
        for sign in [-1.0, 1.0] {
            path.move(to: point(0.19));
            let base = point(0.19)
            path.line(to: CGPoint(x: base.x + cos(angle + CGFloat(sign) * .pi / 3) * s * 0.105,
                                 y: base.y + sin(angle + CGFloat(sign) * .pi / 3) * s * 0.105))
        }
    }
    path.stroke(); image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let data = bitmap.representation(using: .png, properties: [:])!
    let names: [String]
    switch size {
    case 16: names = ["icon_16x16.png"]
    case 32: names = ["icon_16x16@2x.png", "icon_32x32.png"]
    case 64: names = ["icon_32x32@2x.png"]
    case 128: names = ["icon_128x128.png"]
    case 256: names = ["icon_128x128@2x.png", "icon_256x256.png"]
    case 512: names = ["icon_256x256@2x.png", "icon_512x512.png"]
    default: names = ["icon_512x512@2x.png"]
    }
    for name in names { try data.write(to: URL(fileURLWithPath: outputDirectory).appendingPathComponent(name)) }
}
