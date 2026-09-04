import SwiftUI

@main
struct BakoApplication: App {
    @NSApplicationDelegateAdaptor(BakoAppDelegate.self) private var appDelegate
    @StateObject private var model = BakoModel.shared
    @StateObject private var updateController = UpdateController()

    var body: some Scene {
        WindowGroup("Bako") {
            MainWindowView()
                .environmentObject(model)
                .environmentObject(updateController)
                .frame(minWidth: 900, minHeight: 580)
                .background(MainWindowRegistrationView())
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .appInfo) {
                Button(L10n.string("menu.check_updates"), action: updateController.checkForUpdates)
                    .disabled(!updateController.canCheckForUpdates)
                Button(L10n.string("menu.scan_scope")) { model.showScanSetup() }
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}

/// Registers the actual SwiftUI window once its AppKit view is attached. This
/// avoids relying on launch timing when restoring a window from the menu bar.
private struct MainWindowRegistrationView: NSViewRepresentable {
    func makeNSView(context: Context) -> RegistrationView {
        RegistrationView()
    }

    func updateNSView(_ nsView: RegistrationView, context: Context) {}

    final class RegistrationView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            MenuBarController.shared.registerMainWindow(window)
        }
    }
}
