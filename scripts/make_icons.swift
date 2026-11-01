#!/usr/bin/env swift
// Renders the app icon into Murmur/Assets.xcassets (Mac) and MurmurMobile/Assets.xcassets (iPhone and iPad).
//
// Usage (from the repo root): swift scripts/make_icons.swift

import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
var assets = root.appendingPathComponent("Murmur/Assets.xcassets")

func png(size: Int, draw: (CGRect) -> Void) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func write(_ data: Data, _ path: String) throws {
    let url = assets.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

func writeJSON(_ object: Any, _ path: String) throws {
    try write(JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]), path)
}

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1) }

func drawAppIcon(in rect: CGRect) { drawIcon(in: rect, fullBleed: false) }

/// `fullBleed`: iOS masks the corners itself, so the body fills the square.
func drawIcon(in rect: CGRect, fullBleed: Bool) {
    let s = rect.width
    // macOS icon grid: 824/1024 body with ~185/1024 corner radius.
    let body = fullBleed ? rect : rect.insetBy(dx: s * 100 / 1024, dy: s * 100 / 1024)
    let bodyPath = fullBleed ? NSBezierPath(rect: body) : NSBezierPath(roundedRect: body, xRadius: s * 185 / 1024, yRadius: s * 185 / 1024)
    NSGradient(starting: color(44, 46, 56), ending: color(18, 18, 24))!.draw(in: bodyPath, angle: -90)

    // A waveform of five bars in speaker colors.
    let bars: [(CGFloat, NSColor)] = [
        (0.30, color(150, 104, 235)), (0.62, color(150, 104, 235)), (0.86, color(240, 149, 74)),
        (0.52, color(52, 195, 176)), (0.34, color(52, 195, 176)),
    ]
    let barWidth = body.width * (fullBleed ? 0.076 : 0.095)
    let gap = body.width * (fullBleed ? 0.048 : 0.06)
    let total = CGFloat(bars.count) * barWidth + CGFloat(bars.count - 1) * gap
    var x = body.midX - total / 2
    for (height, c) in bars {
        let h = body.height * height * (fullBleed ? 0.62 : 0.78)
        let r = NSRect(x: x, y: body.midY - h / 2, width: barWidth, height: h)
        c.setFill()
        NSBezierPath(roundedRect: r, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        x += barWidth + gap
    }
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try write(png(size: pixels, draw: drawAppIcon), "AppIcon.appiconset/\(name)")
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
try writeJSON(["images": images, "info": ["author": "xcode", "version": 1]], "AppIcon.appiconset/Contents.json")
try writeJSON(["info": ["author": "xcode", "version": 1]], "Contents.json")
print("Wrote \(assets.path)")

// iPhone and iPad: one 1024 px image, no transparency.
assets = root.appendingPathComponent("MurmurMobile/Assets.xcassets")
try write(png(size: 1024) { drawIcon(in: $0, fullBleed: true) }, "AppIcon.appiconset/icon_ios.png")
try writeJSON(["images": [["idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "icon_ios.png"]],
               "info": ["author": "xcode", "version": 1]], "AppIcon.appiconset/Contents.json")
try writeJSON(["info": ["author": "xcode", "version": 1]], "Contents.json")
print("Wrote \(assets.path)")
