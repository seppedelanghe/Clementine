import AppKit

enum Wheel {
    case convert
    case actions
}

struct DragTrigger {
    let wheel: Wheel
    let files: [URL]
    let location: NSPoint
}

@MainActor
final class DragMonitor {
    private let bindings: [Wheel: NSEvent.ModifierFlags]
    private let onTrigger: (DragTrigger) -> Void
    private let onDragEnd: () -> Void
    private let dragPasteboard = NSPasteboard(name: .drag)
    private var seenChangeCount = 0
    private var draggedFiles: [URL] = []
    private var heldModifiers: NSEvent.ModifierFlags = []
    private var modifierPoll: Timer?

    init(
        bindings: [Wheel: NSEvent.ModifierFlags],
        onTrigger: @escaping (DragTrigger) -> Void,
        onDragEnd: @escaping () -> Void
    ) {
        self.bindings = bindings
        self.onTrigger = onTrigger
        self.onDragEnd = onDragEnd
    }

    func start() {
        // Only mouse events: a global flagsChanged monitor would need Accessibility permission,
        // so modifiers are polled while a drag is in progress instead.
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDown() }
        }
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDragged() }
        }
    }

    private func mouseDown() {
        seenChangeCount = dragPasteboard.changeCount
    }

    // The source app writes the drag pasteboard when its drag session begins, so a changed
    // count after mouse down means a drag started.
    private func mouseDragged() {
        guard draggedFiles.isEmpty, dragPasteboard.changeCount != seenChangeCount else { return }
        seenChangeCount = dragPasteboard.changeCount

        let urls = dragPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        guard let urls, !urls.isEmpty else { return }

        draggedFiles = urls
        heldModifiers = currentModifiers()
        modifierPoll = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        // Polled rather than monitored: the source app may swallow the mouse up that ends its drag.
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            endDrag()
            return
        }

        let current = currentModifiers()
        let pressed = current.subtracting(heldModifiers)
        heldModifiers = current
        for (wheel, flags) in bindings where pressed.contains(flags) {
            onTrigger(DragTrigger(wheel: wheel, files: draggedFiles, location: NSEvent.mouseLocation))
        }
    }

    private func endDrag() {
        modifierPoll?.invalidate()
        modifierPoll = nil
        draggedFiles = []
        onDragEnd()
    }

    private func currentModifiers() -> NSEvent.ModifierFlags {
        NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
    }
}
