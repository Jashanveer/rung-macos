#if os(macOS)
import AppKit
import Combine
import SwiftUI

/// macOS-only NSStatusItem that mirrors the active focus session in the menu
/// bar: shows the phase icon + remaining mm:ss while a session is running,
/// disappears when no session is active. Clicking the item raises the app
/// and re-presents the immersive view so the user can get back without
/// hunting through windows.
@MainActor
final class FocusStatusBarController {
    static let shared = FocusStatusBarController()

    private var statusItem: NSStatusItem?
    private var bag: Set<AnyCancellable> = []
    private var hasInstalled = false

    private init() {}

    /// Install the status item (idempotent). Call once at app launch from
    /// `RungApp.applicationDidFinishLaunching`. The item is hidden until a
    /// session starts so the menu bar stays clean for users who never use
    /// focus mode.
    func install() {
        guard !hasInstalled else { return }
        hasInstalled = true

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.button?.target = self
        item.button?.action = #selector(handleClick)
        item.isVisible = false

        observeController()
        refresh(from: FocusController.shared)
    }

    /// Tear down. Symmetric with `install()`; mostly here for tests, the
    /// production app keeps the item alive for the process lifetime.
    func uninstall() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        bag.removeAll()
        hasInstalled = false
    }

    // MARK: - Private

    private func observeController() {
        let controller = FocusController.shared

        controller.$session
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh(from: controller) }
            .store(in: &bag)

        controller.$remaining
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh(from: controller) }
            .store(in: &bag)
    }

    private func refresh(from controller: FocusController) {
        guard let item = statusItem, let button = item.button else { return }
        guard let session = controller.session else {
            item.isVisible = false
            button.title = ""
            button.image = nil
            return
        }

        let total = max(0, Int(controller.remaining.rounded()))
        let m = total / 60
        let s = total % 60
        let label = String(format: " %02d:%02d", m, s)

        let symbolName: String
        switch session.phase {
        case .focus:      symbolName = "bolt.fill"
        case .shortBreak: symbolName = "cup.and.saucer.fill"
        case .longBreak:  symbolName = "leaf.fill"
        }

        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: session.phase.label)
        button.image = image?.withSymbolConfiguration(configuration)
        button.imagePosition = .imageLeading
        button.title = label
        item.isVisible = true
    }

    @objc private func handleClick() {
        // Bring the app forward and re-present the immersive view. If a
        // session is active but the immersive overlay was dismissed, this
        // is the way back.
        NSApp.activate(ignoringOtherApps: true)
        FocusController.shared.isImmersivePresented = true
    }
}
#endif
