#!/usr/bin/env swift
// Renders the app icon into Shared/AppIcon.icon, the Icon Composer file both apps use. macOS 26 and iOS 26 switch
// icons for dark mode only through such a file: the ground is a fill per appearance, the waveform a layer on top,
// lit as glass by the system, which also makes the tinted and clear versions from it.
//
// Usage (from the repo root): swift scripts/make_icons.swift

import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

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

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1) }

func srgb(_ r: Int, _ g: Int, _ b: Int) -> String {
    String(format: "srgb:%.5f,%.5f,%.5f,1.00000", Double(r) / 255, Double(g) / 255, Double(b) / 255)
}

/// A waveform of five bars in speaker colours on a clear ground, deep enough for the teal to hold up on white.
func drawBars(in rect: CGRect) {
    let violet = color(132, 84, 224)
    let orange = color(236, 132, 50)
    let teal = color(28, 170, 152)
    let bars: [(CGFloat, NSColor)] = [(0.30, violet), (0.62, violet), (0.86, orange), (0.52, teal), (0.34, teal)]
    let barWidth = rect.width * 0.076
    let gap = rect.width * 0.048
    let total = CGFloat(bars.count) * barWidth + CGFloat(bars.count - 1) * gap
    var x = rect.midX - total / 2
    for (height, c) in bars {
        let h = rect.height * height * 0.62
        c.setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: rect.midY - h / 2, width: barWidth, height: h),
                     xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        x += barWidth + gap
    }
}

let iconFile = root.appendingPathComponent("Shared/AppIcon.icon")
try? FileManager.default.removeItem(at: iconFile)
try FileManager.default.createDirectory(at: iconFile.appendingPathComponent("Assets"), withIntermediateDirectories: true)
try png(size: 1024) { drawBars(in: $0) }.write(to: iconFile.appendingPathComponent("Assets/bars.png"))

let icon: [String: Any] = [
    "fill-specializations": [
        ["value": ["linear-gradient": [srgb(255, 255, 255), srgb(236, 237, 242)]]],
        ["appearance": "dark", "value": ["linear-gradient": [srgb(44, 46, 56), srgb(18, 18, 24)]]],
    ],
    "groups": [[
        "layers": [[
            "name": "bars",
            "image-name": "bars.png",
        ]],
        "shadow": ["kind": "neutral", "opacity": 0.5],
        "translucency": ["enabled": true, "value": 0.4],
    ]],
    "supported-platforms": ["squares": "shared"],
]
try JSONSerialization.data(withJSONObject: icon, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconFile.appendingPathComponent("icon.json"))
print("Wrote \(iconFile.path)")
