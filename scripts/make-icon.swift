import AppKit

let output = CommandLine.arguments[1]
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))

image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else {
    exit(1)
}
context.clear(CGRect(x: 0, y: 0, width: size, height: size))

let inset: CGFloat = 88
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let background = NSBezierPath(roundedRect: rect, xRadius: 210, yRadius: 210)
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.97, green: 0.35, blue: 0.27, alpha: 1),
    NSColor(srgbRed: 0.72, green: 0.10, blue: 0.10, alpha: 1),
])!
gradient.draw(in: background, angle: -90)

let center = NSPoint(x: size / 2, y: size / 2)
let radius: CGFloat = 250
let lineWidth: CGFloat = 76

func strokeArc(from: CGFloat, to: CGFloat, color: NSColor) {
    let path = NSBezierPath()
    path.appendArc(withCenter: center, radius: radius, startAngle: from, endAngle: to, clockwise: true)
    path.lineWidth = lineWidth
    path.lineCapStyle = .round
    color.setStroke()
    path.stroke()
}

// 轨道
strokeArc(from: 0, to: 360, color: NSColor.white.withAlphaComponent(0.22))
// 从顶部顺时针 270°
strokeArc(from: 90, to: -180, color: .white)

// 中心数字
let text = "45" as NSString
let font = NSFont.systemFont(ofSize: 200, weight: .bold)
let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
]
let textSize = text.size(withAttributes: attributes)
text.draw(
    at: NSPoint(
        x: center.x - textSize.width / 2,
        y: center.y - textSize.height / 2 + 4
    ),
    withAttributes: attributes
)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    exit(1)
}

try png.write(to: URL(fileURLWithPath: output))
