// Exits as soon as the Mac pointer moves more than a few points from where it is now.
// While scrcpy holds the mouse for the Boox, the Mac pointer is frozen; when right ⌘
// releases it, the pointer moves again.
import Cocoa
let start = NSEvent.mouseLocation
while true {
    let m = NSEvent.mouseLocation
    if hypot(m.x - start.x, m.y - start.y) > 4 { exit(0) }
    usleep(200_000)
}
