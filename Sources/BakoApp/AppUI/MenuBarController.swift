import AppKit

final class BakoAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = AppResources.bundle.url(forResource: "Bako-AppIcon-1024", withExtension: "png") {
            NSApp.applicationIconImage = NSImage(contentsOf: url)
        }
        MenuBarController.shared.install()
        DispatchQueue.main.async {
            NSApp.windows.filter(\.canBecomeMain).forEach { window in
                MenuBarController.shared.registerMainWindow(window)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MenuBarController.shared.showMainWindow()
        return true
    }
}

@MainActor
final class MenuBarController: NSObject {
    static let shared = MenuBarController()
    private var statusItem: NSStatusItem?
    private weak var mainWindow: NSWindow?
    private var closeInterceptor: WindowCloseInterceptor?

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = AppResources.bundle.image(forResource: "MenuBarIcon") {
            // This artwork reaches farther into its square than the mostly
            // monochrome system glyphs around it. A half-point size keeps its
            // rendered bounds on Retina displays at roughly 32 x 32 pixels,
            // matching their top edge and visual weight.
            image.size = NSSize(width: 17.5, height: 17.5)
            // Keep Bako's blue and pale-blue brand colors in both appearances.
            image.isTemplate = false
            item.button?.image = image
            item.button?.imagePosition = .imageOnly
        }
        statusItem = item
        refresh()
    }

    func registerMainWindow(_ window: NSWindow) {
        mainWindow = window
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        // Keep the SwiftUI window available after the user closes it so the
        // menu-bar command can bring the same window back.
        window.isReleasedWhenClosed = false

        if closeInterceptor?.window !== window {
            closeInterceptor?.restoreOriginalDelegate()
            let interceptor = WindowCloseInterceptor(window: window)
            closeInterceptor = interceptor
            window.delegate = interceptor
        }
    }

    func showMainWindow() {
        // Run after menu tracking has finished; otherwise AppKit can immediately
        // return focus to the status item and leave the window behind other apps.
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.mainWindow ?? NSApp.windows.first(where: \.canBecomeMain) else {
                return
            }
            self?.mainWindow = window
            window.isReleasedWhenClosed = false
            NSApp.unhide(nil)
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func refresh() {
        guard let statusItem else { return }
        let model = BakoModel.shared
        let menu = NSMenu()

        if model.groups.isEmpty {
            let empty = NSMenuItem(title: L10n.string("menu.no_groups"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for group in model.groups {
                let item = NSMenuItem(title: group.name, action: #selector(toggleGroup(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = group.id.uuidString
                item.state = group.isEnabled ? .on : .off
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let issues = model.skills.filter { [.brokenLink, .occupied].contains($0.health) }.count
        if issues > 0 {
            let issueItem = NSMenuItem(
                title: L10n.string("menu.issues", Int64(issues)),
                action: #selector(openApp), keyEquivalent: ""
            )
            issueItem.target = self
            menu.addItem(issueItem)
        }
        let openItem = NSMenuItem(title: L10n.string("menu.open"), action: #selector(openApp), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        let scanItem = NSMenuItem(title: L10n.string("menu.scan_scope"), action: #selector(scan), keyEquivalent: "")
        scanItem.target = self
        menu.addItem(scanItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: L10n.string("menu.quit"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    @objc private func toggleGroup(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let id = UUID(uuidString: value) else { return }
        BakoModel.shared.toggleGroup(id)
    }

    @objc private func openApp() {
        showMainWindow()
    }

    @objc private func scan() {
        BakoModel.shared.showScanSetup()
        openApp()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

/// SwiftUI tears down a WindowGroup scene when its NSWindow actually closes.
/// Intercept close and hide the window instead, while forwarding every other
/// delegate callback to SwiftUI's original delegate.
private final class WindowCloseInterceptor: NSObject, NSWindowDelegate {
    weak var window: NSWindow?
    private weak var originalDelegate: NSWindowDelegate?

    init(window: NSWindow) {
        self.window = window
        originalDelegate = window.delegate
        super.init()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Returning false keeps the SwiftUI scene alive. Hide only after AppKit
        // finishes processing that cancelled close, otherwise it orders the
        // window front again immediately.
        DispatchQueue.main.async { [weak sender] in
            sender?.orderOut(nil)
        }
        return false
    }

    func restoreOriginalDelegate() {
        guard let window, window.delegate === self else { return }
        window.delegate = originalDelegate
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || originalDelegate?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if originalDelegate?.responds(to: selector) == true {
            return originalDelegate
        }
        return super.forwardingTarget(for: selector)
    }
}
