import AppKit

// DMG window is 540×380 points; we render at 2x (1080×760 pixels) for Retina
// crisp. We use NSBitmapImageRep directly (rather than NSImage.lockFocus)
// because lockFocus on a Retina display silently produces a 2x backing store,
// which makes the output PNG 2160×1520 — Finder then reads the 144-DPI metadata
// and shows only the upper-left quarter in the 540×380pt window.
//
// Drawing here happens in pixel coordinates (1080×760), bottom-left origin.

let W = 1080
let H = 760

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: W, pixelsHigh: H,
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let bounds = NSRect(x: 0, y: 0, width: W, height: H)

// Cream gradient background
let bg = NSGradient(colors: [
    NSColor(red: 0.99, green: 0.96, blue: 0.92, alpha: 1.0),
    NSColor(red: 0.96, green: 0.91, blue: 0.85, alpha: 1.0),
])!
bg.draw(in: bounds, angle: -90)

// Title — pulled down toward the icon row to close the gap.
let titleFont = NSFont.systemFont(ofSize: 40, weight: .semibold)
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: titleFont,
    .foregroundColor: NSColor(red: 0.32, green: 0.18, blue: 0.10, alpha: 1.0),
]
let title = NSAttributedString(string: "Claude Clipboard Cleaner", attributes: titleAttrs)
let titleSize = title.size()
let titleX = (CGFloat(W) - titleSize.width) / 2
let titleY = CGFloat(H) - 130 - titleSize.height
title.draw(at: NSPoint(x: titleX, y: titleY))

// Bottom block: two instruction lines. Finder shaves ~28pt (=56px) off the
// bottom of the window for the title bar that's inside the AppleScript
// bounds, so both lines have to live above y ~= 60px.
let subFont = NSFont.systemFont(ofSize: 26, weight: .regular)
let subAttrs: [NSAttributedString.Key: Any] = [
    .font: subFont,
    .foregroundColor: NSColor(red: 0.50, green: 0.38, blue: 0.30, alpha: 1.0),
]
let sub = NSAttributedString(string: "Drag the app into your Applications folder",
                             attributes: subAttrs)
let subSize = sub.size()
let subX = (CGFloat(W) - subSize.width) / 2
let subY: CGFloat = 160
sub.draw(at: NSPoint(x: subX, y: subY))

let noteFont = NSFont.systemFont(ofSize: 22, weight: .regular)
let noteAttrs: [NSAttributedString.Key: Any] = [
    .font: noteFont,
    .foregroundColor: NSColor(red: 0.55, green: 0.45, blue: 0.38, alpha: 1.0),
]
let note = NSAttributedString(
    string: "First launch: open from Applications by right-clicking → Open",
    attributes: noteAttrs)
let noteSize = note.size()
let noteX = (CGFloat(W) - noteSize.width) / 2
let noteY: CGFloat = 110
note.draw(at: NSPoint(x: noteX, y: noteY))

// Arrow showing the drag direction. Finder positions the app icon center at
// pixel x=280 and the Applications icon center at pixel x=800 (logical 140
// and 400 in the 540pt-wide window, scaled 2x). The icons are 96pt = 192px
// wide, so their edges are at x≈376 (app right edge) and x≈704 (Applications
// left edge). The arrow spans the gap between, centered vertically on the
// icons at y = 760 - 400 = 360 in bottom-left pixel coords.
let arrowY: CGFloat = 360
let arrowStartX: CGFloat = 420
let arrowEndX: CGFloat = 660

let arrowColor = NSColor(red: 0.82, green: 0.45, blue: 0.25, alpha: 0.90)
arrowColor.setStroke()
arrowColor.setFill()

let shaft = NSBezierPath()
shaft.lineWidth = 8
shaft.lineCapStyle = .round
shaft.move(to: NSPoint(x: arrowStartX, y: arrowY))
shaft.line(to: NSPoint(x: arrowEndX - 18, y: arrowY))
shaft.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: arrowEndX + 10, y: arrowY))
head.line(to: NSPoint(x: arrowEndX - 26, y: arrowY + 22))
head.line(to: NSPoint(x: arrowEndX - 26, y: arrowY - 22))
head.close()
head.fill()

NSGraphicsContext.restoreGraphicsState()

// Tag the bitmap with its logical point size (540×380) so the embedded DPI
// resolves to 144. Finder reads that and treats the 1080×760 pixel image as
// a 540×380 point image, which matches the DMG window bounds and fills it
// at native Retina resolution.
rep.size = NSSize(width: 540, height: 380)

if let png = rep.representation(using: .png, properties: [:]) {
    try! png.write(to: URL(fileURLWithPath: "build/dmg_background.png"))
    print("build/dmg_background.png (\(W)x\(H)px @ 144dpi)")
}
