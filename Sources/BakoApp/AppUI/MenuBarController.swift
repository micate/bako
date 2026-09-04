import AppKit

final class BakoAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
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
            image.size = NSSize(width: 18, height: 18)
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
            // Accessory apps stay alive in the menu bar but do not appear in
            // the Dock. Restore the regular policy before presenting a window
            // so AppKit can activate Bako normally again.
            NSApp.setActivationPolicy(.regular)
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
    private weak var originalDelegate: (NSObject & NSWindowDelegate)?

    init(window: NSWindow) {
        self.window = window
        originalDelegate = window.delegate as? (NSObject & NSWindowDelegate)
        super.init()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Returning false keeps the SwiftUI scene alive. Hide only after AppKit
        // finishes processing that cancelled close, otherwise it orders the
        // window front again immediately.
        DispatchQueue.main.async { [weak sender] in
            sender?.orderOut(nil)
            // Keep the process and status item running while removing Bako
            // from both the Dock and the Command-Tab application switcher.
            NSApp.setActivationPolicy(.accessory)
        }
        return false
    }

    func restoreOriginalDelegate() {
        guard let window, window.delegate === self else { return }
        window.delegate = originalDelegate
    }

    override func responds(to selector: Selector!) -> Bool {
        let originalDelegateResponds: Bool = originalDelegate?.responds(to: selector) ?? false
        return super.responds(to: selector) || originalDelegateResponds
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        let originalDelegateResponds: Bool = originalDelegate?.responds(to: selector) ?? false
        if originalDelegateResponds {
            return originalDelegate
        }
        return super.forwardingTarget(for: selector)
    }
}
