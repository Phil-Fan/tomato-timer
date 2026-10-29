import AppKit

// 用法：swift scripts/make-icon.swift 输出.png
// 生成 1024×1024 的 App 图标 / Logo：番茄红圆角方块 + 白色进度环 + 播放三角。

let output = CommandLine.arguments[1]
let size: CGFloat = 1024
let center = NSPoint(x: size / 2, y: size / 2)

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else {
    exit(1)
}
context.clear(CGRect(x: 0, y: 0, width: size, height: size))

// 圆角底
let inset: CGFloat = 88
let tileRect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 210, yRadius: 210)
NSGradient(colors: [
    NSColor(srgbRed: 0.99, green: 0.42, blue: 0.30, alpha: 1),
    NSColor(srgbRed: 0.70, green: 0.09, blue: 0.08, alpha: 1),
])!.draw(in: tile, angle: -70)

// 顶部高光
NSGraphicsContext.saveGraphicsState()
tile.addClip()
NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.16),
    NSColor.white.withAlphaComponent(0),
])!.draw(
    in: NSRect(x: tileRect.minX, y: center.y, width: tileRect.width, height: tileRect.height / 2),
    angle: -90
)
NSGraphicsContext.restoreGraphicsState()

// 进度环
let arc = NSBezierPath()
arc.appendArc(
    withCenter: center,
    radius: 240,
    startAngle: 95,
    endAngle: -165,
    clockwise: true
)
arc.lineWidth = 84
arc.lineCapStyle = .round
NSColor.white.setStroke()
arc.stroke()

// 播放三角
let triangle = NSBezierPath()
let height: CGFloat = 172
let width: CGFloat = 150
let opticalOffset: CGFloat = 18
triangle.move(to: NSPoint(x: center.x - width / 2 + opticalOffset, y: center.y + height / 2))
triangle.line(to: NSPoint(x: center.x - width / 2 + opticalOffset, y: center.y - height / 2))
triangle.line(to: NSPoint(x: center.x + width / 2 + opticalOffset, y: center.y))
triangle.close()
triangle.lineJoinStyle = .round
triangle.lineWidth = 36
NSColor.white.setFill()
triangle.fill()
NSColor.white.setStroke()
triangle.stroke()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    exit(1)
}

try png.write(to: URL(fileURLWithPath: output))
