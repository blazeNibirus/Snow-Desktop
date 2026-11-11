import AppKit
import QuartzCore

@main struct RenderProbe {
    static func main() throws {
        _ = NSApplication.shared
        let width = 400, height = 300
        let engine = SnowEngine(width: Double(width), height: Double(height))
        let cover = SnowRect(x: 40, y: 60, width: 80, height: 35)
        engine.updateSurfaces([SurfaceDescriptor(id: 1, x: 40, y: 100, width: 300,
            occluders: [cover])], elapsed: 0.1)
        engine.piles[1]!.heights = Array(repeating: 13, count: engine.piles[1]!.heights.count)
        engine.addParticle(Particle(x: 200, y: 150, radius: 3))
        engine.addParticle(Particle(x: 20, y: 70, radius: 3))
        let view = SnowView(frame: CGRect(x: 0, y: 0, width: width, height: height), engine: engine)
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        view.particleOccluders = [SnowRect(x: 40, y: 100, width: 300, height: 160), cover]
        view.updateVisibilityMask(); view.render(); view.render()
        CATransaction.flush()
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
        view.layer!.render(in: context)
        let image = context.makeImage()!
        let bitmap = NSBitmapImageRep(cgImage: image)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        // Core Animation's model-layer coordinates are used directly in the bitmap buffer.
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        func alpha(_ x: Int, _ y: Int) -> UInt8 { bytes[(y * width + x) * 4 + 3] }
        let samples = [(20,70),(200,150),(200,95),(350,95),(41,95),(60,90),(60,98)]
        print(samples.map { "\($0):\(alpha($0.0,$0.1))" }.joined(separator: " "))
        precondition(alpha(200, 150) == 0, "Flakes must not render inside a window")
        precondition(alpha(350, 95) == 0, "A bank cannot extend beyond the right edge")
        precondition(alpha(41, 95) == 0, "Physical edges must have a smooth tapered cap")
        precondition(alpha(60, 90) == 0, "Front window must hide only its intersection")
        precondition(alpha(60, 98) > 0, "Exposed lower portion of a bank must remain visible")
        precondition(alpha(200, 95) > 0, "Snow must remain visible above the window")
        precondition(alpha(20, 70) > 0, "Snow must remain visible outside windows")
        print("PASS rendering: no flakes inside windows, finite bank bounds, round caps, partial occlusion")
    }
}
