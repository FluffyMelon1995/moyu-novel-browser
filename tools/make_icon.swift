// 生成一个指南针风格的 App 图标：swiftc make_icon.swift -o make_icon && ./make_icon out.iconset
import Cocoa

let dir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)

    let inset = s * 100 / 1024
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    NSGradient(starting: .white, ending: NSColor(white: 0.9, alpha: 1))!
        .draw(in: NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225), angle: -90)

    let dial = rect.insetBy(dx: rect.width * 0.08, dy: rect.width * 0.08)
    NSGradient(starting: NSColor(calibratedRed: 0.38, green: 0.80, blue: 1, alpha: 1),
               ending: NSColor(calibratedRed: 0.05, green: 0.40, blue: 0.95, alpha: 1))!
        .draw(in: NSBezierPath(ovalIn: dial), angle: -90)

    let c = NSPoint(x: dial.midX, y: dial.midY)
    let r = dial.width / 2
    NSColor.white.withAlphaComponent(0.9).setStroke()
    for i in 0..<60 {
        let a = CGFloat(i) / 60 * 2 * .pi
        let inner = r * (i % 5 == 0 ? 0.80 : 0.87)
        let p = NSBezierPath()
        p.lineWidth = s * (i % 5 == 0 ? 0.006 : 0.003)
        p.move(to: NSPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner))
        p.line(to: NSPoint(x: c.x + cos(a) * r * 0.93, y: c.y + sin(a) * r * 0.93))
        p.stroke()
    }

    let t = NSAffineTransform()
    t.translateX(by: c.x, yBy: c.y)
    t.rotate(byDegrees: -40)
    let len = r * 0.72, w = r * 0.11
    for (tip, color) in [(len, NSColor(calibratedRed: 1, green: 0.23, blue: 0.19, alpha: 1)), (-len, NSColor.white)] {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 0, y: tip))
        p.line(to: NSPoint(x: -w, y: 0))
        p.line(to: NSPoint(x: w, y: 0))
        p.close()
        p.transform(using: t as AffineTransform)
        color.setFill()
        p.fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(dir)/icon_\(name).png"))
}
