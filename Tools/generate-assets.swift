#!/usr/bin/env swift
// Original artwork. Regeneration uses only the macOS SDK; normal builds use the checked-in PNGs.
import AppKit
import CryptoKit

let assets = URL(fileURLWithPath: #filePath).standardizedFileURL
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Assets")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

func color(_ rgb: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
            green: CGFloat((rgb >> 8) & 255) / 255,
            blue: CGFloat(rgb & 255) / 255, alpha: alpha)
}
let ink = color(0xEDF3FB), navy = color(0x111B2C), cyan = color(0x75D8DA)

func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
         _ fill: NSColor, radius: CGFloat = 0) {
    fill.setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h),
                 xRadius: radius, yRadius: radius).fill()
}
func polygon(_ points: [NSPoint], _ fill: NSColor) {
    let path = NSBezierPath()
    path.move(to: points[0])
    for point in points.dropFirst() { path.line(to: point) }
    path.close(); fill.setFill(); path.fill()
}
func triangle(_ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ fill: NSColor) {
    polygon([NSPoint(x: x, y: y), NSPoint(x: x, y: y + size),
             NSPoint(x: x + size * 0.8, y: y + size / 2)], fill)
}
func label(_ text: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ fill: NSColor) {
    (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: fill
    ])
}

// All symbols are built on a 100-point grid from basic geometric shapes.
func symbol(_ kind: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ fill: NSColor = cyan) {
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: x, yBy: y); transform.scale(by: size / 100); transform.concat()
    switch kind {
    case "film":
        box(15, 15, 70, 70, fill, radius: 7)
        box(25, 33, 50, 34, navy, radius: 2)
        for offset in [25, 43, 61] {
            box(CGFloat(offset), 21, 11, 7, navy, radius: 1)
            box(CGFloat(offset), 72, 11, 7, navy, radius: 1)
        }
        triangle(44, 40, 20, fill)
    case "tv":
        box(10, 25, 80, 59, fill, radius: 7)
        box(16, 31, 68, 47, navy, radius: 3)
        box(45, 15, 10, 12, fill); box(28, 12, 44, 5, fill, radius: 2)
        triangle(43, 42, 25, fill)
    case "grid":
        for x in [16, 54] { for y in [16, 54] {
            box(CGFloat(x), CGFloat(y), 30, 30, fill, radius: 5)
        } }
    case "folder":
        polygon([NSPoint(x: 12, y: 20), NSPoint(x: 88, y: 20),
                 NSPoint(x: 88, y: 71), NSPoint(x: 46, y: 71),
                 NSPoint(x: 38, y: 81), NSPoint(x: 12, y: 81)], fill)
        box(18, 26, 64, 36, navy, radius: 2)
    case "error":
        fill.setFill(); NSBezierPath(ovalIn: NSRect(x: 14, y: 14, width: 72, height: 72)).fill()
        box(45, 43, 10, 29, navy, radius: 3); box(45, 28, 10, 10, navy, radius: 5)
    default:
        box(12, 24, 76, 55, fill, radius: 6)
        box(18, 30, 64, 43, navy, radius: 2)
        triangle(42, 39, 26, fill)
        box(24, 15, 52, 4, fill, radius: 2)
    }
    NSGraphicsContext.restoreGraphicsState()
}

var manifest: [[String: Any]] = []
func render(_ file: String, _ width: Int, _ height: Int, _ drawing: () -> Void) throws {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width,
        pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Cannot allocate artwork bitmap")
    }
    bitmap.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    context.cgContext.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.shouldAntialias = true
    drawing()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("PNG encoding failed for \(file)")
    }
    try png.write(to: assets.appendingPathComponent(file), options: .atomic)
    // Check the encoded result, rather than only the drawing canvas.
    guard let decoded = NSBitmapImageRep(data: png),
          decoded.pixelsWide == width, decoded.pixelsHigh == height else {
        fatalError("PNG dimension self-check failed for \(file)")
    }
    manifest.append(["file": file, "width": width, "height": height,
        "sha256": SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined(),
        "source": "Tools/generate-assets.swift",
        "provenance": "Original programmatic artwork for this independent client; no vendor artwork.",
        "license": "MIT"])
}

for (file, light) in [("login-pad-dark.png", false), ("login-pad-light.png", true),
                       ("media-login-pad.png", false)] {
    try render(file, 1024, 768) {
        let bottom = light ? color(0xE7EFF3) : color(0x101827)
        let top = light ? color(0xF6F9FB) : color(0x233950)
        NSGradient(starting: bottom, ending: top)!.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 768), angle: 90)
        let line = light ? color(0x456578, 0.07) : color(0x99DCE1, 0.055)
        for x in stride(from: 0, to: 1024, by: 64) { box(CGFloat(x), 0, 1, 768, line) }
        for y in stride(from: 0, to: 768, by: 64) { box(0, CGFloat(y), 1024, 1, line) }
        let beam = light ? color(0x7DACBE, 0.10) : color(0x87D9DD, 0.045)
        polygon([NSPoint(x: 1000, y: 100), NSPoint(x: 64, y: 270), NSPoint(x: 64, y: 680)], beam)
        box(62, 270, 3, 410, line)
        symbol("screen", 810, 68, 120, light ? color(0x83A9B6, 0.25) : color(0x76B3C0, 0.25))
    }
}

for (file, size) in [("Icon-50.png", 50), ("Icon-72.png", 72), ("brand-mark.png", 78)] {
    try render(file, size, size) {
        box(0, 0, CGFloat(size), CGFloat(size), navy, radius: CGFloat(size) * 0.2)
        symbol("screen", 0, 0, CGFloat(size))
    }
}

for (file, width, light) in [("brand-wordmark-dark.png", 186, false),
                            ("brand-wordmark-light.png", 187, true)] {
    try render(file, width, 42) {
        symbol("screen", 0, 1, 38, light ? color(0x346D80) : cyan)
        label("NAS CINEMA", 43, 18, 16, light ? navy : ink)
        label("FNTV iPad client", 44, 5, 8, light ? color(0x4A6075) : color(0xB1C3D7))
    }
}

for (file, kind) in [("poster-placeholder.png", "screen"), ("media-error.png", "error"),
                     ("empty-folder.png", "folder")] {
    try render(file, 105, 105) {
        box(0, 0, 105, 105, color(0x1A2639))
        symbol(kind, 12, 12, 81, color(0xA5BBCE))
    }
}

for (file, kind, width) in [("library-movie.png", "film", 40), ("library-tv.png", "tv", 42),
                            ("library-mix.png", "grid", 40), ("library-other.png", "folder", 40)] {
    try render(file, width, 40) { symbol(kind, CGFloat(width - 40) / 2, 0, 40) }
}

for (file, kind, title) in [("entry-all.png", "grid", "ALL MEDIA"),
                           ("entry-film.png", "film", "FILMS"), ("entry-tv.png", "tv", "TV")] {
    try render(file, 164, 75) {
        box(0, 0, 164, 75, color(0x25354B), radius: 10)
        symbol(kind, 5, 10, 54)
        label(title, 65, 30, 12, ink)
    }
}

precondition(manifest.count == 18 && Set(manifest.map { $0["file"] as! String }).count == 18,
             "Asset inventory self-check failed")
let json = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
try (json + Data([10])).write(to: assets.appendingPathComponent("manifest.json"), options: .atomic)
print("Generated and checked \(manifest.count) original PNGs and Assets/manifest.json.")
