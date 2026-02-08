#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate_icon.swift <output-png>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let canvasSize = NSSize(width: 1024, height: 1024)

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> NSColor {
    NSColor(deviceRed: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: a)
}

func interpolate(_ c1: NSColor, _ c2: NSColor, _ t: CGFloat) -> NSColor {
    let p1 = c1.usingColorSpace(.deviceRGB) ?? c1
    let p2 = c2.usingColorSpace(.deviceRGB) ?? c2
    return NSColor(
        deviceRed: p1.redComponent + (p2.redComponent - p1.redComponent) * t,
        green: p1.greenComponent + (p2.greenComponent - p1.greenComponent) * t,
        blue: p1.blueComponent + (p2.blueComponent - p1.blueComponent) * t,
        alpha: p1.alphaComponent + (p2.alphaComponent - p1.alphaComponent) * t
    )
}

let palette: [(CGFloat, NSColor)] = [
    (0.00, rgba(247, 201, 72)),
    (0.18, rgba(245, 165, 66)),
    (0.42, rgba(232, 94, 138)),
    (0.70, rgba(70, 119, 232)),
    (0.88, rgba(178, 107, 225)),
    (1.00, rgba(247, 201, 72)),
]

func gradientColor(at t: CGFloat) -> NSColor {
    for index in 0..<(palette.count - 1) {
        let (startT, startColor) = palette[index]
        let (endT, endColor) = palette[index + 1]
        if t >= startT && t <= endT {
            let span = max(endT - startT, 0.0001)
            return interpolate(startColor, endColor, (t - startT) / span)
        }
    }
    return palette.last!.1
}

guard
    let bitmapRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvasSize.width),
        pixelsHigh: Int(canvasSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ),
    let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmapRep)
else {
    fputs("Failed to create graphics context\n", stderr)
    exit(1)
}
let ctx = graphicsContext.cgContext

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext
defer { NSGraphicsContext.restoreGraphicsState() }

ctx.setShouldAntialias(true)
ctx.setAllowsAntialiasing(true)
ctx.clear(CGRect(origin: .zero, size: canvasSize))

let center = CGPoint(x: canvasSize.width / 2.0, y: canvasSize.height / 2.0 + 16.0)
let ringRadius: CGFloat = 255.0
let ringThickness: CGFloat = 76.0

let shadowRect = CGRect(x: center.x - 220.0, y: center.y - 300.0, width: 440.0, height: 34.0)
let shadowPath = NSBezierPath(ovalIn: shadowRect)
rgba(0, 0, 0, 0.10).setFill()
shadowPath.fill()

let faceRect = CGRect(x: center.x - 196.0, y: center.y - 196.0, width: 392.0, height: 392.0)
let facePath = NSBezierPath(ovalIn: faceRect)
let faceGradient = NSGradient(colors: [rgba(251, 251, 251), rgba(233, 233, 236)])!
faceGradient.draw(in: facePath, relativeCenterPosition: NSZeroPoint)

let segmentCount = 300
for segment in 0..<segmentCount {
    let t0 = CGFloat(segment) / CGFloat(segmentCount)
    let t1 = CGFloat(segment + 1) / CGFloat(segmentCount)
    let start = CGFloat(-45.0) + 360.0 * t0
    let end = CGFloat(-45.0) + 360.0 * t1

    let arc = NSBezierPath()
    arc.appendArc(withCenter: center, radius: ringRadius, startAngle: start, endAngle: end, clockwise: false)
    arc.lineWidth = ringThickness
    arc.lineCapStyle = .round
    gradientColor(at: (t0 + t1) / 2.0).setStroke()
    arc.stroke()
}

let rimPath = NSBezierPath(ovalIn: CGRect(
    x: center.x - (ringRadius - ringThickness / 2.0),
    y: center.y - (ringRadius - ringThickness / 2.0),
    width: 2.0 * (ringRadius - ringThickness / 2.0),
    height: 2.0 * (ringRadius - ringThickness / 2.0)
))
rimPath.lineWidth = 2.0
rgba(255, 255, 255, 0.75).setStroke()
rimPath.stroke()

let crownRect = CGRect(x: center.x - 56.0, y: center.y + 248.0, width: 112.0, height: 40.0)
let crownPath = NSBezierPath(roundedRect: crownRect, xRadius: 16.0, yRadius: 16.0)
let crownGradient = NSGradient(colors: [rgba(247, 201, 72), rgba(237, 169, 52)])!
crownGradient.draw(in: crownPath, angle: -90.0)

let stemRect = CGRect(x: center.x - 28.0, y: center.y + 220.0, width: 56.0, height: 28.0)
let stemPath = NSBezierPath(roundedRect: stemRect, xRadius: 8.0, yRadius: 8.0)
rgba(236, 173, 66).setFill()
stemPath.fill()

for angle in stride(from: 90.0, through: 450.0, by: 90.0) {
    let radians = angle * .pi / 180.0
    let x = center.x + cos(radians) * 148.0
    let y = center.y + sin(radians) * 148.0
    let horizontal = abs(sin(radians)) < 0.001
    let tickRect: CGRect
    if horizontal {
        tickRect = CGRect(x: x - 11.0, y: y - 2.5, width: 22.0, height: 5.0)
    } else {
        tickRect = CGRect(x: x - 2.5, y: y - 11.0, width: 5.0, height: 22.0)
    }
    let tick = NSBezierPath(roundedRect: tickRect, xRadius: 2.5, yRadius: 2.5)
    rgba(196, 199, 208).setFill()
    tick.fill()
}

let checkPath = NSBezierPath()
checkPath.move(to: CGPoint(x: center.x - 44.0, y: center.y + 12.0))
checkPath.line(to: CGPoint(x: center.x - 2.0, y: center.y - 26.0))
checkPath.line(to: CGPoint(x: center.x + 106.0, y: center.y + 70.0))
checkPath.lineCapStyle = .round
checkPath.lineJoinStyle = .round
checkPath.lineWidth = 34.0
let checkGradient = NSGradient(colors: [rgba(67, 127, 224), rgba(43, 80, 191)])!
checkGradient.draw(in: checkPath, angle: 10.0)

let highlight = NSBezierPath()
highlight.appendArc(withCenter: center, radius: ringRadius + 4.0, startAngle: 20.0, endAngle: 62.0, clockwise: false)
highlight.lineWidth = 26.0
highlight.lineCapStyle = .round
rgba(255, 255, 255, 0.25).setStroke()
highlight.stroke()

for rayOffset in [0.0, 26.0, 52.0] {
    let ray = NSBezierPath()
    ray.move(to: CGPoint(x: center.x + 138.0 + rayOffset, y: center.y + 254.0))
    ray.line(to: CGPoint(x: center.x + 154.0 + rayOffset, y: center.y + 296.0))
    ray.lineWidth = 12.0
    ray.lineCapStyle = .round
    rgba(247, 201, 72, 0.95).setStroke()
    ray.stroke()
}

guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}

try pngData.write(to: outputURL, options: .atomic)
print("Wrote \(outputURL.path)")
