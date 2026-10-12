// Menu bar item for the Boox setup: auto-switch toggle and manual mode switches.
import Cocoa

let home = FileManager.default.homeDirectoryForCurrentUser.path
let bin = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : home + "/projects/personal/boox-display/bin"
let autoOffFlag = home + "/.local/state/boox-display/auto-off"
let adb = home + "/Library/Android/sdk/platform-tools/adb"

@discardableResult
func run(_ path: String, _ args: [String] = [], wait: Bool = false) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return -1 }
    if wait { p.waitUntilExit(); return p.terminationStatus }
    return 0
}

final class Menu: NSObject, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let menu = NSMenu()
    let auto = NSMenuItem(title: "Switch to Boox when plugged in", action: #selector(toggleAuto), keyEquivalent: "")
    let screen = NSMenuItem(title: "Use Boox as screen", action: #selector(screenMode), keyEquivalent: "")
    let laptop = NSMenuItem(title: "Use laptop", action: #selector(laptopMode), keyEquivalent: "")
    let control = NSMenuItem(title: "Control Boox with keyboard & trackpad", action: #selector(toggleControl), keyEquivalent: "")

    override init() {
        super.init()
        item.button?.image = NSImage(systemSymbolName: "rectangle.portrait.on.rectangle.portrait", accessibilityDescription: "Boox")
        for i in [auto, screen, laptop, control] { i.target = self }
        menu.addItem(auto)
        menu.addItem(.separator())
        menu.addItem(screen)
        menu.addItem(laptop)
        menu.addItem(.separator())
        menu.addItem(control)
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        refresh()
    }

    func refresh() {
        let autoOn = !FileManager.default.fileExists(atPath: autoOffFlag)
        let plugged = run(adb, ["get-state"], wait: true) == 0
        let controlling = run("/usr/bin/pgrep", ["-xq", "scrcpy"], wait: true) == 0
        auto.state = autoOn ? .on : .off
        item.button?.appearsDisabled = !autoOn
        screen.isEnabled = plugged
        control.isEnabled = plugged || controlling
        control.title = controlling ? "Stop controlling Boox" : "Control Boox with keyboard & trackpad"
    }
    func menuWillOpen(_ menu: NSMenu) { refresh() }

    @objc func toggleAuto() {
        let on = FileManager.default.fileExists(atPath: autoOffFlag)
        run(bin + "/boox-auto", [on ? "on" : "off"])
    }
    @objc func screenMode() { run(bin + "/boox-screen") }
    @objc func laptopMode() { run(bin + "/boox-laptop") }
    @objc func toggleControl() {
        if run("/usr/bin/pgrep", ["-xq", "scrcpy"], wait: true) == 0 {
            run("/usr/bin/pkill", ["-9", "-x", "scrcpy"])  // scrcpy ignores TERM/INT on macOS
        } else {
            run(bin + "/boox-control")
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let menuController = Menu()
app.run()
