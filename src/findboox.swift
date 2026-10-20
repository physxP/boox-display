// findboox <serial> [timeout-seconds]
// Finds the Boox on the local network by its wireless-debugging advertisement
// (_adb-tls-connect._tcp, named "adb-<serial>-...") and prints "ip:port".
// Exits 1 if it isn't found in time.
import Foundation

let serial = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
let timeout = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2]) ?? 3 : 3

final class Finder: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    let browser = NetServiceBrowser()
    var resolving: [NetService] = []

    func start() {
        browser.delegate = self
        browser.searchForServices(ofType: "_adb-tls-connect._tcp.", inDomain: "local.")
    }
    func netServiceBrowser(_ b: NetServiceBrowser, didFind s: NetService, moreComing: Bool) {
        guard s.name.hasPrefix("adb-\(serial)-") else { return }
        s.delegate = self
        resolving.append(s)
        s.resolve(withTimeout: timeout)
    }
    func netServiceDidResolveAddress(_ s: NetService) {
        for data in s.addresses ?? [] {
            data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                let sa = raw.bindMemory(to: sockaddr.self).baseAddress!
                guard sa.pointee.sa_family == sa_family_t(AF_INET) else { return }
                var addr = raw.bindMemory(to: sockaddr_in.self).baseAddress!.pointee.sin_addr
                var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN))
                print("\(String(cString: buf)):\(s.port)")
                exit(0)
            }
        }
    }
}

let finder = Finder()
finder.start()
RunLoop.main.run(until: Date(timeIntervalSinceNow: timeout))
exit(1)
