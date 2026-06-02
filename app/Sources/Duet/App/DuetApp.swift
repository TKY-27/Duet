import AppKit
import SwiftUI

@main
@MainActor
struct DuetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: AppStore

    init() {
        let store = AppStore()
        _store = StateObject(wrappedValue: store)
        AppDelegate.store = store
    }

    var body: some Scene {
        WindowGroup("Duet") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 980, minHeight: 680)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button(L10n.reconnectHub(AppLanguage.systemDefault)) {
                    store.connect()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var store: AppStore?
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Self.store?.start()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateNow }
        isTerminating = true

        Task {
            await Self.store?.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
    }
}
