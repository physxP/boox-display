// Menu bar item for the Boox setup: connection status, auto-switch toggle and mode switches.
// USB modes appear when the Boox is plugged in, Wi-Fi modes when it's found on the network.
import Cocoa

let home = FileManager.default.homeDirectoryForCurrentUser.path
let bin = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : home + "/projects/personal/boox-display/bin"
let state = home + "/.local/state/boox-display"
// adb: $ADB, else the Android SDK's, else Homebrew's (Apple Silicon or Intel).
let adb: String = {
    let fm = FileManager.default
    if let env = ProcessInfo.processInfo.environment["ADB"], !env.isEmpty { return env }
    for p in [home + "/Library/Android/sdk/platform-tools/adb", "/opt/homebrew/bin/adb", "/usr/local/bin/adb"]
        where fm.isExecutableFile(atPath: p) { return p }
    return home + "/Library/Android/sdk/platform-tools/adb"
}()
// adb model name of the Boox (same as BOOX_MODEL in bin/lib.sh).
let model = ProcessInfo.processInfo.environment["BOOX_MODEL"] ?? "NoteMax"

@discardableResult
func run(_ path: String, _ args: [String] = [], wait: Bool = false) -> (status: Int32, output: String) {
    let p = Process(), out = Pipe()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    p.standardOutput = wait ? out : FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return (-1, "") }
    guard wait else { return (0, "") }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
}

final class Menu: NSObject, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let menu = NSMenu()
    let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let auto = NSMenuItem(title: "Switch to Boox when plugged in", action: #selector(toggleAuto), keyEquivalent: "")
    let screenUSB = NSMenuItem(title: "Use Boox as screen", action: #selector(screenUSBMode), keyEquivalent: "")
    let screenWifi = NSMenuItem(title: "Use Boox as screen over Wi-Fi", action: #selector(screenWifiMode), keyEquivalent: "")
    let laptop = NSMenuItem(title: "Use laptop", action: #selector(laptopMode), keyEquivalent: "")
    let controlUSB = NSMenuItem(title: "Control Boox with keyboard & trackpad", action: #selector(controlUSBMode), keyEquivalent: "")
    let controlWifi = NSMenuItem(title: "Control Boox over Wi-Fi", action: #selector(controlWifiMode), keyEquivalent: "")
    let stop = NSMenuItem(title: "Stop controlling Boox", action: #selector(stopControl), keyEquivalent: "")

    override init() {
        super.init()
        item.button?.image = NSImage(systemSymbolName: "rectangle.portrait.on.rectangle.portrait", accessibilityDescription: "Boox")
        status.isEnabled = false
        for i in [auto, screenUSB, screenWifi, laptop, controlUSB, controlWifi, stop] { i.target = self }
        for i in [status, .separator(), screenUSB, screenWifi, laptop, .separator(),
                  controlUSB, controlWifi, stop, .separator(), auto] { menu.addItem(i) }
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        refresh()
    }

    func refresh() {
        let devices = run(adb, ["devices", "-l"], wait: true).output.split(separator: "\n")
        let boox = devices.filter { $0.contains("model:" + model) && $0.split(separator: " ").dropFirst().first == "device" }
        let usb = boox.contains { $0.contains(" usb:") }
        let wifi = boox.contains { $0.first?.isNumber == true }
        let controlling = run("/usr/bin/pgrep", ["-xq", "scrcpy"], wait: true).status == 0
        let mode = (try? String(contentsOfFile: state + "/mode", encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "laptop"
        let autoOn = !FileManager.default.fileExists(atPath: state + "/auto-off")

        let link = usb && wifi ? "USB and Wi-Fi" : usb ? "USB" : wifi ? "Wi-Fi" : nil
        status.title = link.map { "Boox connected (\($0))" } ?? "Boox not found"
        screenUSB.isHidden = !usb
        screenWifi.isHidden = !wifi
        controlUSB.isHidden = !usb || controlling
        controlWifi.isHidden = !wifi || controlling
        stop.isHidden = !controlling
        screenUSB.state = mode == "screen-usb" ? .on : .off
        screenWifi.state = mode == "screen-wifi" ? .on : .off
        laptop.state = mode == "laptop" ? .on : .off
        auto.state = autoOn ? .on : .off
        item.button?.appearsDisabled = link == nil
    }
    func menuWillOpen(_ menu: NSMenu) { refresh() }

    @objc func toggleAuto() {
        let off = FileManager.default.fileExists(atPath: state + "/auto-off")
        run(bin + "/boox-auto", [off ? "on" : "off"])
    }
    @objc func screenUSBMode() { run(bin + "/boox-screen") }
    @objc func screenWifiMode() { run(bin + "/boox-screen", ["--wifi"]) }
    @objc func laptopMode() { run(bin + "/boox-laptop") }
    @objc func controlUSBMode() { run(bin + "/boox-control") }
    @objc func controlWifiMode() { run(bin + "/boox-control", ["--wifi"]) }
    @objc func stopControl() { run("/usr/bin/pkill", ["-9", "-x", "scrcpy"]) }  // scrcpy ignores TERM/INT on macOS
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let menuController = Menu()
app.run()
