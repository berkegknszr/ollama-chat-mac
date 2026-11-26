import AppKit
let s: CGFloat = 1024
let img = NSImage(size: NSSize(width: s, height: s))
img.lockFocus()
let path = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 0.30, green: 0.45, blue: 0.98, alpha: 1), NSColor(red: 0.60, green: 0.32, blue: 0.92, alpha: 1)])!.draw(in: path, angle: -60)
let cfg = NSImage.SymbolConfiguration(pointSize: 380, weight: .semibold).applying(.init(paletteColors: [.white]))
if let sym = NSImage(systemSymbolName: "bubble.left.and.bubble.right.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
    let z = sym.size
    sym.draw(in: NSRect(x: (s - z.width) / 2, y: (s - z.height) / 2, width: z.width, height: z.height))
}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
