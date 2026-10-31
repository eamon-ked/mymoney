import AppKit

let shots = CommandLine.arguments[1], out = CommandLine.arguments[2]
let W = 1320.0, H = 2868.0
func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func serif(_ size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .semibold)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: size) ?? base
}
let pages: [(String, String, String)] = [
    ("home", "Know what's safe\nto spend", "After bills, savings and your budget"),
    ("accounts", "Every account\nat a glance", "Cash, savings, cards and loans"),
    ("budget", "Give your money\na plan", "Set a budget and see what's left"),
    ("bills", "Never miss\na bill", "A reminder before each one is due"),
    ("people", "Split bills\nwith friends", "See who owes you, and who you owe"),
    ("forecast", "See the weeks\nahead", "Your balance, day by day"),
    ("reports", "Know where\nit went", "Clear monthly reports"),
    ("ask", "Ask about\nyour money", "Answers worked out on your iPhone"),
]
let statusStrip = NSImage(contentsOfFile: "\(shots)/home.png")!
for (i, (name, title, subtitle)) in pages.enumerated() {
    guard let shot = NSImage(contentsOfFile: "\(shots)/\(name).png") else { print("missing \(name)"); continue }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx.cgContext, flipped: true)
    let cg = ctx.cgContext
    cg.translateBy(x: 0, y: H); cg.scaleBy(x: 1, y: -1)

    // Deep green, a little lighter at the top
    NSGradient(colors: [color(0x4A5E46), color(0x2F4636), color(0x22362B)])!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

    let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineHeightMultiple = 0.95
    let t = NSAttributedString(string: title, attributes: [.font: serif(118), .foregroundColor: color(0xF7F3E8), .paragraphStyle: para, .kern: -1.5])
    t.draw(with: NSRect(x: 60, y: 170, width: W - 120, height: 300), options: [.usesLineFragmentOrigin])
    let sub = NSMutableParagraphStyle(); sub.alignment = .center
    NSAttributedString(string: subtitle, attributes: [.font: NSFont.systemFont(ofSize: 50, weight: .regular), .foregroundColor: color(0xD9CDB0), .paragraphStyle: sub])
        .draw(with: NSRect(x: 60, y: 470, width: W - 120, height: 80), options: [.usesLineFragmentOrigin])

    // The phone: a graphite bezel round the screen, running off the bottom
    let scale = 0.80, sw = W * scale, sh = H * scale, sx = (W - sw) / 2, sy = 640.0, bezel = 22.0
    let body = NSBezierPath(roundedRect: NSRect(x: sx - bezel, y: sy - bezel, width: sw + bezel * 2, height: sh + bezel * 2), xRadius: 150, yRadius: 150)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = color(0x000000, 0.35); shadow.shadowBlurRadius = 60; shadow.shadowOffset = NSSize(width: 0, height: 30)
    shadow.set(); color(0x1B1E1A).setFill(); body.fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    color(0x6B6F66, 0.6).setStroke(); body.lineWidth = 3; body.stroke()
    NSGraphicsContext.current?.saveGraphicsState()
    let screen = NSRect(x: sx, y: sy, width: sw, height: sh)
    NSBezierPath(roundedRect: screen, xRadius: 130, yRadius: 130).addClip()
    shot.draw(in: screen, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
    if name == "people" {
        // Scrolled content sits under the status bar; put the plain one back
        let strip = 190.0
        statusStrip.draw(in: NSRect(x: sx, y: sy, width: sw, height: strip * scale),
                         from: NSRect(x: 0, y: H - strip, width: W, height: strip), operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
    }
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGraphicsContext.current = nil
    let file = "\(out)/\(String(format: "%02d", i + 1))-\(name).png"
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: file))
    print(file)
}
