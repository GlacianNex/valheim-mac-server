import AppKit
import Foundation
let output = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedRed: 0.035, green: 0.09, blue: 0.15, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 30, y: 30, width: 964, height: 964), xRadius: 200, yRadius: 200).fill()
let teal = NSColor(calibratedRed: 0.24, green: 0.84, blue: 0.73, alpha: 1)
for y in [230, 395, 560] {
    NSColor(calibratedRed: 0.12, green: 0.26, blue: 0.34, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 220, y: y, width: 584, height: 115), xRadius: 26, yRadius: 26).fill()
    teal.setFill(); NSBezierPath(ovalIn: NSRect(x: 258, y: y + 37, width: 40, height: 40)).fill()
    NSColor.white.withAlphaComponent(0.8).setFill()
    NSBezierPath(roundedRect: NSRect(x: 350, y: y + 45, width: 380, height: 24), xRadius: 12, yRadius: 12).fill()
}
let mountain = NSBezierPath(); mountain.move(to: NSPoint(x: 260, y: 750)); mountain.line(to: NSPoint(x: 390, y: 850)); mountain.line(to: NSPoint(x: 490, y: 775)); mountain.line(to: NSPoint(x: 620, y: 900)); mountain.line(to: NSPoint(x: 765, y: 750))
mountain.lineWidth = 32; mountain.lineJoinStyle = .round; mountain.lineCapStyle = .round; teal.setStroke(); mountain.stroke()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
