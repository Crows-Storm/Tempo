import AppKit
import SwiftUI

enum MenuBarIcon {
    struct Signature: Equatable {
        var minutes: Int
        var eighths: Int
        var running: Bool
        var phase: FocusPhase
        var dark: Bool
    }

    static func signature(
        remaining: TimeInterval,
        progress: Double,
        running: Bool,
        phase: FocusPhase,
        dark: Bool
    ) -> Signature {
        Signature(
            minutes: max(0, Int(ceil(remaining / 60))),
            eighths: min(8, max(0, Int((progress * 8).rounded()))),
            running: running,
            phase: phase,
            dark: dark
        )
    }

    static func image(_ signature: Signature) -> NSImage {
        let side: CGFloat = 18
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pixels = max(18, Int((side * scale).rounded()))
        let image = NSImage(size: NSSize(width: side, height: side))
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return image
        }
        representation.size = NSSize(width: side, height: side)
        image.addRepresentation(representation)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
        let appearance = NSAppearance(named: signature.dark ? .darkAqua : .aqua) ?? .currentDrawing()
        appearance.performAsCurrentDrawingAppearance {
            draw(signature, in: NSRect(x: 0, y: 0, width: side, height: side))
        }
        NSGraphicsContext.restoreGraphicsState()
        image.isTemplate = false
        return image
    }

    private static func draw(_ signature: Signature, in rect: NSRect) {
        let tint: NSColor = signature.phase == .focus ? .systemRed : .systemYellow
        let track = NSColor.separatorColor.withAlphaComponent(0.7)
        let inset = rect.insetBy(dx: 1.5, dy: 1.5)
        let path = NSBezierPath(ovalIn: inset)
        track.setStroke()
        path.lineWidth = 1.6
        path.stroke()
        let progress = Double(signature.eighths) / 8
        if progress > 0 {
            let arc = NSBezierPath()
            arc.appendArc(
                withCenter: NSPoint(x: rect.midX, y: rect.midY),
                radius: rect.width / 2 - 1.5,
                startAngle: 90,
                endAngle: 90 - CGFloat(progress) * 360,
                clockwise: true
            )
            tint.setStroke()
            arc.lineWidth = 1.8
            arc.lineCapStyle = .round
            arc.stroke()
        }
        let text = String(signature.minutes) as NSString
        let font = NSFont.monospacedDigitSystemFont(ofSize: signature.minutes >= 100 ? 5 : 7, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: signature.running ? tint : NSColor.secondaryLabelColor
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attributes
        )
    }
}

@MainActor
final class MenuBarController: NSObject {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var model: AppModel?
    private var shown = MenuBarIcon.Signature(minutes: -1, eighths: -1, running: false, phase: .focus, dark: false)
    private var appearanceObserver: NSKeyValueObservation?

    func install(model: AppModel) {
        self.model = model
        guard statusItem == nil else {
            refreshTitle()
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.attach()
        }
    }

    func refreshTitle() {
        guard let model, let button = statusItem?.button else { return }
        let next = MenuBarIcon.signature(
            remaining: model.remaining(),
            progress: model.clock.progress(at: .now, durations: model.durations),
            running: model.clock.runState == .running,
            phase: model.clock.phase,
            dark: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        )
        guard next != shown else { return }
        shown = next
        button.image = MenuBarIcon.image(next)
        button.setAccessibilityLabel(PhaseCopy.spokenTitle(model.clock.phase))
        button.setAccessibilityValue(TempoFormat.spoken(model.remaining()))
    }

    private func attach() {
        guard statusItem == nil, let model else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.target = self
            button.action = #selector(togglePopover)
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 236, height: 168)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPanel(model: model).tempoChrome(model)
        )
        statusItem = item
        self.popover = popover
        appearanceObserver = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in
                self?.shown.minutes = -1
                self?.refreshTitle()
            }
        }
        refreshTitle()
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        refreshTitle()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }
}

enum MiniTimerLayout {
    static let identifier = NSUserInterfaceItemIdentifier("tempo.main")
    static let size = CGSize(width: 336, height: 148)

    static func compactFrame(from full: CGRect, size: CGSize = Self.size) -> CGRect {
        CGRect(
            x: full.origin.x,
            y: full.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}

@MainActor
final class MiniTimerController {
    static let shared = MiniTimerController()

    private struct Snapshot {
        var frame: NSRect
        var level: NSWindow.Level
        var collectionBehavior: NSWindow.CollectionBehavior
        var minSize: NSSize
        var maxSize: NSSize
        var styleMask: NSWindow.StyleMask
        var titlebarAppearsTransparent: Bool
        var isMovableByWindowBackground: Bool
        var titleVisibility: NSWindow.TitleVisibility
    }

    private var snapshot: Snapshot?

    func toggle(model: AppModel) {
        guard let window = Self.mainWindow() else { return }
        if model.isMiniTimer {
            restore(window, model: model)
        } else {
            compact(window, model: model)
        }
    }

    private func compact(_ window: NSWindow, model: AppModel) {
        let saved = Snapshot(
            frame: window.frame,
            level: window.level,
            collectionBehavior: window.collectionBehavior,
            minSize: window.minSize,
            maxSize: window.maxSize,
            styleMask: window.styleMask,
            titlebarAppearsTransparent: window.titlebarAppearsTransparent,
            isMovableByWindowBackground: window.isMovableByWindowBackground,
            titleVisibility: window.titleVisibility
        )
        snapshot = saved
        model.isMiniTimer = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.styleMask.remove(.resizable)
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.makeKeyAndOrderFront(nil)
        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        DispatchQueue.main.async {
            let frame = MiniTimerLayout.compactFrame(from: saved.frame)
            window.setFrame(frame, display: true, animate: animate)
            window.minSize = frame.size
            window.maxSize = frame.size
        }
    }

    private func restore(_ window: NSWindow, model: AppModel) {
        let saved = snapshot
        snapshot = nil
        model.isMiniTimer = false
        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        DispatchQueue.main.async {
            if let saved {
                window.styleMask = saved.styleMask
                window.minSize = saved.minSize
                window.maxSize = saved.maxSize
                window.level = saved.level
                window.collectionBehavior = saved.collectionBehavior
                window.titlebarAppearsTransparent = saved.titlebarAppearsTransparent
                window.isMovableByWindowBackground = saved.isMovableByWindowBackground
                window.titleVisibility = saved.titleVisibility
                window.standardWindowButton(.zoomButton)?.isEnabled = true
                window.setFrame(saved.frame, display: true, animate: animate)
            }
            window.makeKeyAndOrderFront(nil)
        }
    }

    private static func mainWindow() -> NSWindow? {
        if let window = NSApp.keyWindow, window.identifier == MiniTimerLayout.identifier {
            return window
        }
        if let window = NSApp.mainWindow, window.identifier == MiniTimerLayout.identifier {
            return window
        }
        return NSApp.windows.first { $0.identifier == MiniTimerLayout.identifier }
    }
}

struct MainWindowConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.identifier = MiniTimerLayout.identifier
            window.delegate = context.coordinator
            window.styleMask.insert(.fullSizeContentView)
            window.toolbarStyle = .unified
            window.titlebarSeparatorStyle = .automatic
            window.backgroundColor = .windowBackgroundColor
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.identifier = MiniTimerLayout.identifier
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            sender.orderOut(nil)
            return false
        }
    }
}
