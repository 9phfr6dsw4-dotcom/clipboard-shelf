// CI-only fixture shaped like Clipboard Shelf's menu-bar UI: a square status item and a
// transient 430×500 NSPopover. It has no pasteboard access and no persistent state. After
// each click it writes the popover window frame, in top-left global coordinates, as
// "x|y|width|height" to the path given as its first argument; it quits after two minutes.
import AppKit

final class FixtureDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let controller = NSViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 430, height: 500))
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 430, height: 500)
        popover.contentViewController = controller
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "pause.circle.fill", accessibilityDescription: "Popover Fixture — recording paused")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { NSApp.terminate(nil) }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.reportPopoverFrame() }
    }

    private func reportPopoverFrame() {
        guard CommandLine.arguments.count > 1,
              let frame = popover.contentViewController?.view.window?.frame,
              let primary = NSScreen.screens.first else { return }
        let top = primary.frame.maxY - frame.maxY
        let line = "\(Int(frame.minX))|\(Int(top))|\(Int(frame.width))|\(Int(frame.height))\n"
        try? line.write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
    }
}

let application = NSApplication.shared
let fixtureDelegate = FixtureDelegate()
application.delegate = fixtureDelegate
application.run()
