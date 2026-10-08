import AppKit
import Foundation
let output = CommandLine.arguments[1]
let size = 1024
let cgContext = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let context = NSGraphicsContext(cgContext: cgContext, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSGradient(starting: NSColor(red: 0.12, green: 0.10, blue: 0.25, alpha: 1), ending: NSColor(red: 0.51, green: 0.32, blue: 0.69, alpha: 1))!.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: 55)
let diamond = NSBezierPath()
diamond.move(to: NSPoint(x: 512, y: 878)); diamond.line(to: NSPoint(x: 878, y: 512)); diamond.line(to: NSPoint(x: 512, y: 146)); diamond.line(to: NSPoint(x: 146, y: 512)); diamond.close()
NSColor.white.withAlphaComponent(0.08).setFill(); diamond.fill()
NSColor.white.withAlphaComponent(0.25).setStroke(); diamond.lineWidth = 7; diamond.stroke()
let heights: [CGFloat] = [100, 180, 300, 430, 300, 180, 100]
for (i, height) in heights.enumerated() {
 let rect = NSRect(x: 285 + CGFloat(i) * 67, y: 512 - height / 2, width: 34, height: height)
 NSColor.white.withAlphaComponent(i == 3 ? 1 : 0.82).setFill()
 NSBezierPath(roundedRect: rect, xRadius: 17, yRadius: 17).fill()
}
NSGraphicsContext.restoreGraphicsState()
try NSBitmapImageRep(cgImage: cgContext.makeImage()!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
