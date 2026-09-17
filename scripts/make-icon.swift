import AppKit
import Foundation
let output = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedRed: 0.07, green: 0.075, blue: 0.08, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 30, y: 30, width: 964, height: 964), xRadius: 200, yRadius: 200).fill()
let font = NSFont(name: "Georgia-Bold", size: 820) ?? NSFont.boldSystemFont(ofSize: 820)
let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor(calibratedRed: 0.88, green: 0.43, blue: 0.19, alpha: 1),
    .strokeColor: NSColor(calibratedRed: 1, green: 0.65, blue: 0.34, alpha: 1),
    .strokeWidth: -1.0
]
let letter = NSAttributedString(string: "V", attributes: attributes)
let size = letter.size()
letter.draw(at: NSPoint(x: (1024 - size.width) / 2, y: (1024 - size.height) / 2 + 25))
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
