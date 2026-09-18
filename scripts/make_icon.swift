// 生成 macOS 应用图标：裁掉源图白边，合成到 1024 画布的圆角方形（Apple 规范：824 主体 + 185 圆角）
// 用法：build/make_icon <源图路径> <输出 1024 PNG 路径>
import AppKit
import Foundation

guard CommandLine.arguments.count >= 3 else {
    fputs("用法: make_icon <source> <output>\n", stderr)
    exit(1)
}
let sourcePath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]

guard let sourceImage = NSImage(contentsOfFile: sourcePath),
      let sourceRep = NSBitmapImageRep(data: sourceImage.tiffRepresentation!) else {
    fputs("无法读取源图\n", stderr)
    exit(1)
}
let sw = sourceRep.pixelsWide
let sh = sourceRep.pixelsHigh

// 1. 扫描非白色像素的包围盒（每 4 像素采样加速）
var minX = sw, minY = sh, maxX = 0, maxY = 0
func isContent(_ x: Int, _ y: Int) -> Bool {
    guard let color = sourceRep.colorAt(x: x, y: y) else { return false }
    let white = color.brightnessComponent
    return white < 0.96
}
var y = 0
while y < sh {
    var x = 0
    while x < sw {
        if isContent(x, y) {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
        x += 4
    }
    y += 4
}
guard maxX > minX, maxY > minY else {
    fputs("未找到内容像素\n", stderr)
    exit(1)
}
// 采样步长 4，向四周扩 6 像素兜底
minX = max(0, minX - 6); minY = max(0, minY - 6)
maxX = min(sw, maxX + 6); maxY = min(sh, maxY + 6)
let cropW = maxX - minX
let cropH = maxY - minY
print("内容包围盒: \(cropW)x\(cropH) @(\(minX),\(minY))")

// 2. 合成 1024 画布
let canvas = 1024
let inset = 100                    // Apple 规范：四周留白 100
let body = canvas - inset * 2      // 主体 824
let cornerRadius: CGFloat = 185

let icon = NSImage(size: NSSize(width: canvas, height: canvas))
icon.lockFocus()

let bodyRect = NSRect(x: inset, y: inset, width: body, height: body)
NSColor.white.setFill()
NSBezierPath(roundedRect: bodyRect, xRadius: cornerRadius, yRadius: cornerRadius).fill()

// 细描边增强浅色 Dock 下的轮廓
NSColor(white: 0, alpha: 0.08).setStroke()
let border = NSBezierPath(roundedRect: bodyRect.insetBy(dx: 1.5, dy: 1.5),
                          xRadius: cornerRadius - 1.5, yRadius: cornerRadius - 1.5)
border.lineWidth = 3
border.stroke()

// 3. 居中绘制 T（约占主体宽度 66%）
let targetW = Double(body) * 0.66
let scale = targetW / Double(cropW)
let targetH = Double(cropH) * scale
let cropRect = NSRect(x: minX, y: sh - maxY, width: cropW, height: cropH)  // 翻转 y（AppKit 原点在左下）
guard let cropped = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil)?
    .cropping(to: CGRect(x: minX, y: minY, width: cropW, height: cropH)) else {
    fputs("裁剪失败\n", stderr)
    exit(1)
}
let drawX = (CGFloat(canvas) - CGFloat(targetW)) / 2
let drawY = (CGFloat(canvas) - CGFloat(targetH)) / 2
if let context = NSGraphicsContext.current?.cgContext {
    context.interpolationQuality = .high
    context.draw(cropped, in: CGRect(x: drawX, y: drawY, width: CGFloat(targetW), height: CGFloat(targetH)))
}

icon.unlockFocus()

guard let tiff = icon.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("PNG 编码失败\n", stderr)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outputPath))
print("图标已生成: \(outputPath)")
