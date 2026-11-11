// Serves the Boox virtual display, and only that display, over VNC: pixel for pixel, view-only.
// macOS Screen Sharing sends every display as one wide image, so it can't be used once the
// Boox is one of several desktops (extended layouts, or an external screen attached).
// Listens on 127.0.0.1 only (the Boox reaches it through `adb reverse`), asks for the password
// in ~/.local/state/boox-display/vnc-password, and never uses JPEG so text stays sharp.
// Needs Screen Recording permission; launchd starts it so the permission belongs to booxvnc.
import Cocoa
import ScreenCaptureKit

let displayName = "Boox Note Max"
let port: Int32 = 5901
let passwordFile = NSHomeDirectory() + "/.local/state/boox-display/vnc-password"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

guard let booxScreen = NSScreen.screens.first(where: { $0.localizedName == displayName }),
      let displayID = booxScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
      let mode = CGDisplayCopyDisplayMode(displayID)
else { fail("The \(displayName) display isn't connected.") }
let width = mode.pixelWidth, height = mode.pixelHeight  // pixels, not points: 1:1 with the panel

guard let password = try? String(contentsOfFile: passwordFile, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines), !password.isEmpty
else { fail("No password in \(passwordFile).") }

// --- VNC server --------------------------------------------------------------------------
var argc: Int32 = 1
var argv: [UnsafeMutablePointer<CChar>?] = [strdup("booxvnc"), nil]
guard let server = rfbGetScreen(&argc, &argv, Int32(width), Int32(height), 8, 3, 4) else { fail("rfbGetScreen failed.") }
let framebuffer = UnsafeMutablePointer<UInt32>.allocate(capacity: width * height)
framebuffer.initialize(repeating: 0, count: width * height)
server.pointee.frameBuffer = UnsafeMutableRawPointer(framebuffer).assumingMemoryBound(to: CChar.self)
// ScreenCaptureKit delivers BGRA; describe that as 32-bit little-endian RGB.
server.pointee.serverFormat.redShift = 16
server.pointee.serverFormat.greenShift = 8
server.pointee.serverFormat.blueShift = 0
server.pointee.desktopName = UnsafePointer(strdup("Mac (\(displayName))"))
server.pointee.port = port
server.pointee.ipv6port = 0                              // no IPv6 listener (it would bind every interface)
server.pointee.listenInterface = inet_addr("127.0.0.1")
server.pointee.alwaysShared = 1                          // a reconnecting viewer doesn't wait for the old one
let passwords = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: 2)
passwords[0] = strdup(password); passwords[1] = nil
server.pointee.authPasswdData = UnsafeMutableRawPointer(passwords)
server.pointee.passwordCheck = rfbCheckPasswordByList
server.pointee.cursor = nil                              // vnccursor draws the cursor into the display
server.pointee.ptrAddEvent = { _, _, _, _ in }           // view-only
server.pointee.kbdAddEvent = { _, _, _ in }
// Viewers ask for JPEG (AVNC does by default), and the Tight encoder then JPEG-compresses any
// area with many colours, anti-aliased text included. Turn it off before every update.
server.pointee.displayHook = { client in
    client?.pointee.turboQualityLevel = -1
    client?.pointee.tightQualityLevel = -1
}
booxvnc_init(server)
guard server.pointee.listenSock >= 0 else { fail("Can't listen on 127.0.0.1:\(port).") }
rfbRunEventLoop(server, -1, 1)  // serves clients on its own thread

// --- Capture -----------------------------------------------------------------------------
final class Capture: NSObject, SCStreamOutput, SCStreamDelegate {
    let server: rfbScreenInfoPtr, framebuffer: UnsafeMutablePointer<UInt32>
    init(server: rfbScreenInfoPtr, framebuffer: UnsafeMutablePointer<UInt32>) {
        self.server = server; self.framebuffer = framebuffer
    }

    // Copy only the rows that changed and mark only the changed columns, so the Boox (e-ink)
    // redraws as little as possible.
    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let info = (CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
              let status = info[.status] as? Int, SCFrameStatus(rawValue: status) == .complete,
              let pixels = buffer.imageBuffer,
              CVPixelBufferGetWidth(pixels) == width, CVPixelBufferGetHeight(pixels) == height
        else { return }
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels) else { return }
        let stride = CVPixelBufferGetBytesPerRow(pixels), rowBytes = width * 4, band = 16

        for top in Swift.stride(from: 0, to: height, by: band) {
            let bottom = min(top + band, height)
            var left = width, right = -1
            for y in top..<bottom {
                let src = (base + y * stride).assumingMemoryBound(to: UInt32.self)
                let dst = framebuffer + y * width
                if memcmp(src, dst, rowBytes) == 0 { continue }
                var a = 0; while a < width && src[a] == dst[a] { a += 1 }
                var b = width - 1; while b > a && src[b] == dst[b] { b -= 1 }
                left = min(left, a); right = max(right, b)
                dst.update(from: src, count: width)
            }
            if right >= 0 { rfbMarkRectAsModified(server, Int32(left), Int32(top), Int32(right + 1), Int32(bottom)) }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        fail("Capture stopped: \(error.localizedDescription)")
    }
}

if !CGPreflightScreenCaptureAccess() {
    CGRequestScreenCaptureAccess()  // shows the system prompt once
    fail("booxvnc needs Screen Recording permission: System Settings > Privacy & Security > "
         + "Screen & System Audio Recording > booxvnc, then switch layouts again.")
}

let capture = Capture(server: server, framebuffer: framebuffer)
var stream: SCStream?
SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
    guard let display = content?.displays.first(where: { $0.displayID == displayID }) else {
        fail("Can't capture the \(displayName) display: \(error?.localizedDescription ?? "not found").")
    }
    let config = SCStreamConfiguration()
    config.width = width
    config.height = height
    config.pixelFormat = kCVPixelFormatType_32BGRA
    config.showsCursor = false                                // vnccursor's cursor is captured instead
    config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
    config.queueDepth = 4
    let s = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: capture)
    do {
        try s.addStreamOutput(capture, type: .screen, sampleHandlerQueue: DispatchQueue(label: "booxvnc.capture"))
    } catch { fail("Can't capture: \(error.localizedDescription)") }
    s.startCapture { error in
        if let error { fail("Can't start capturing: \(error.localizedDescription)") }
        print("Serving \(displayName) (\(width)x\(height)) on 127.0.0.1:\(port)")
        fflush(stdout)
    }
    stream = s
}

// The Boox display going away (laptop mode, a new layout) ends this server; boox-screen
// starts a fresh one when it needs it.
NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                       object: nil, queue: .main) { _ in
    if !NSScreen.screens.contains(where: { $0.localizedName == displayName }) { exit(0) }
}
app.run()
