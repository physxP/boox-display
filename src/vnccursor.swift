// Draws a high-contrast cursor in a click-through window that follows the mouse,
// so screen captures that omit the hardware cursor (e.g. macOS VNC) still show it.
import Cocoa

let size: CGFloat = 28

final class CursorView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let p = NSBezierPath()
        // Arrow pointing up-left; view is flipped so (0,0) is the tip.
        p.move(to: NSPoint(x: 2, y: 2))
        p.line(to: NSPoint(x: 2, y: 22))
        p.line(to: NSPoint(x: 7.5, y: 17))
        p.line(to: NSPoint(x: 11.5, y: 26))
        p.line(to: NSPoint(x: 15, y: 24.5))
        p.line(to: NSPoint(x: 11, y: 15.5))
        p.line(to: NSPoint(x: 18, y: 15.5))
        p.close()
        p.lineWidth = 2
        p.lineJoinStyle = .round
        NSColor.white.setStroke(); p.stroke()
        NSColor.black.setFill(); p.fill()
    }
    override var isFlipped: Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                   styleMask: .borderless, backing: .buffered, defer: false)
win.isOpaque = false
win.backgroundColor = .clear
win.hasShadow = false
win.ignoresMouseEvents = true
win.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
win.contentView = CursorView(frame: NSRect(x: 0, y: 0, width: size, height: size))
win.orderFrontRegardless()

// Only draw while the Boox virtual display exists (Boox screen mode); otherwise the
// real cursor is visible and this one would just be a duplicate.
func booxActive() -> Bool { NSScreen.screens.contains { $0.localizedName == "Boox Note Max" } }
var shown = booxActive()
if !shown { win.orderOut(nil) }
NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                       object: nil, queue: .main) { _ in
    shown = booxActive()
    if shown { win.orderFrontRegardless() } else { win.orderOut(nil) }
}

var last = NSPoint(x: -1, y: -1)
Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
    guard shown else { return }
    let m = NSEvent.mouseLocation
    if m != last {
        last = m
        win.setFrameOrigin(NSPoint(x: m.x - 2, y: m.y - size + 2))
    }
}
app.run()
