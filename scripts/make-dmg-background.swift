#!/usr/bin/env swift
import AppKit

guard CommandLine.arguments.count >= 2 else {
    fputs("usage: make-dmg-background.swift <png>\n", stderr)
    exit(1)
}

let scale: CGFloat = 2
let width: CGFloat = 620
let height: CGFloat = 400
let size = NSSize(width: width * scale, height: height * scale)
let image = NSImage(size: size)
image.lockFocus()
NSColor(srgbRed: 0.945, green: 0.957, blue: 0.973, alpha: 1).setFill()
NSBezierPath.fill(NSRect(origin: .zero, size: size))

let center = NSPoint(x: size.width * 0.5, y: size.height * 0.52)
let arm = 28 * scale
let path = NSBezierPath()
path.lineWidth = 6 * scale
path.lineCapStyle = .round
path.lineJoinStyle = .round
path.move(to: NSPoint(x: center.x - arm * 0.2, y: center.y + arm * 0.7))
path.line(to: NSPoint(x: center.x + arm * 0.65, y: center.y))
path.line(to: NSPoint(x: center.x - arm * 0.2, y: center.y - arm * 0.7))
NSColor(srgbRed: 0.62, green: 0.66, blue: 0.72, alpha: 1).setStroke()
path.stroke()
image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else {
    fputs("failed to encode PNG\n", stderr)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
