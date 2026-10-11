import AppKit

let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
func render(size: Int, file: String) throws {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    let background = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 214, yRadius: 214)
    NSGradient(starting: NSColor(calibratedRed: 0.12, green: 0.28, blue: 0.38, alpha: 1), ending: NSColor(calibratedRed: 0.04, green: 0.11, blue: 0.18, alpha: 1))!.draw(in: background, angle: -60)
    NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 310, y: 390, width: 230, height: 390), xRadius: 115, yRadius: 115).fill()
    let cradle = NSBezierPath(); cradle.move(to: NSPoint(x: 235, y: 530)); cradle.line(to: NSPoint(x: 235, y: 470))
    cradle.curve(to: NSPoint(x: 615, y: 470), controlPoint1: NSPoint(x: 235, y: 210), controlPoint2: NSPoint(x: 615, y: 210))
    cradle.line(to: NSPoint(x: 615, y: 530)); cradle.lineWidth = 48; cradle.lineCapStyle = .round
    NSColor(calibratedWhite: 0.97, alpha: 1).setStroke(); cradle.stroke()
    let stand = NSBezierPath(); stand.move(to: NSPoint(x: 425, y: 295)); stand.line(to: NSPoint(x: 425, y: 220)); stand.move(to: NSPoint(x: 330, y: 220)); stand.line(to: NSPoint(x: 520, y: 220)); stand.lineWidth = 48; stand.lineCapStyle = .round; stand.stroke()
    NSColor(calibratedRed: 0.53, green: 0.91, blue: 0.74, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 680, y: 435, width: 55, height: 240), xRadius: 20, yRadius: 20).fill()
    NSBezierPath(roundedRect: NSRect(x: 785, y: 435, width: 55, height: 240), xRadius: 20, yRadius: 20).fill()
    image.unlockFocus()
    guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data),
          let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not render icon") }
    try png.write(to: URL(fileURLWithPath: output).appendingPathComponent(file))
}
for points in [16, 32, 128, 256, 512] {
    try render(size: points, file: "icon_\(points)x\(points).png")
    try render(size: points * 2, file: "icon_\(points)x\(points)@2x.png")
}
