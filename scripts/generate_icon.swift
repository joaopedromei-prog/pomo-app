#!/usr/bin/swift
import AppKit
import CoreGraphics

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func renderIcon(size: Int) -> NSImage {
    let dim = CGFloat(size)
    let img = NSImage(size: NSSize(width: dim, height: dim))
    img.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext

    // White rounded rect background
    let radius = dim * 0.22
    let bgPath = CGMutablePath()
    bgPath.addRoundedRect(in: CGRect(x: 0, y: 0, width: dim, height: dim),
                          cornerWidth: radius, cornerHeight: radius)
    ctx.setFillColor(CGColor.white)
    ctx.addPath(bgPath)
    ctx.fillPath()

    // Black ring
    let center = CGPoint(x: dim / 2, y: dim / 2)
    let ringRadius = dim * 0.33
    let lineWidth = dim * 0.078
    ctx.setStrokeColor(CGColor.black)
    ctx.setLineWidth(lineWidth)
    ctx.addArc(center: center, radius: ringRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    // Small filled dot at top (12 o'clock) — marks start of progress
    let dotRadius = lineWidth * 0.5
    let dotCenter = CGPoint(x: dim / 2, y: dim / 2 + ringRadius)
    ctx.setFillColor(CGColor.black)
    ctx.addArc(center: dotCenter, radius: dotRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.fillPath()

    img.unlockFocus()
    return img
}

// Create iconset directory
let iconsetPath = "\(outputDir)/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

for size in sizes {
    let img = renderIcon(size: size)
    guard let tiff = img.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed at size \(size)")
        continue
    }
    let filename = "\(iconsetPath)/icon_\(size)x\(size).png"
    try! png.write(to: URL(fileURLWithPath: filename))

    // @2x version (retina) for sizes up to 512
    if size <= 512 {
        let img2x = renderIcon(size: size * 2)
        guard let tiff2x = img2x.tiffRepresentation,
              let bitmap2x = NSBitmapImageRep(data: tiff2x),
              let png2x = bitmap2x.representation(using: .png, properties: [:]) else { continue }
        let filename2x = "\(iconsetPath)/icon_\(size)x\(size)@2x.png"
        try! png2x.write(to: URL(fileURLWithPath: filename2x))
    }
    print("Generated \(size)x\(size)")
}

// Convert iconset to icns
let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", iconsetPath, "-o", "\(outputDir)/AppIcon.icns"]
task.launch()
task.waitUntilExit()

if task.terminationStatus == 0 {
    print("AppIcon.icns created successfully.")
} else {
    print("iconutil failed. Check iconset at \(iconsetPath)")
}
