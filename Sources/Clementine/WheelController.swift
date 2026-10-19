import AppKit
import SwiftUI

@MainActor
final class WheelController {
    private let onSelect: (WheelItem, [URL]) -> Void
    private let model = WheelModel()
    private var panel: NSPanel?
    private var files: [URL] = []
    private var pendingClose: Task<Void, Never>?

    init(onSelect: @escaping (WheelItem, [URL]) -> Void) {
        self.onSelect = onSelect
    }

    // Tapping another modifier while the wheel is open swaps its items in place.
    func show(title: String, items: [WheelItem], files: [URL], at location: NSPoint) {
        assert(!items.isEmpty)
        pendingClose?.cancel()
        model.show(title: title, items: items)
        self.files = files

        guard panel == nil else { return }
        model.isOpen = false
        let size = WheelModel.canvas
        let frame = NSRect(x: location.x - size / 2, y: location.y - size / 2, width: size, height: size)
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = WheelDropView(
            model: model,
            onDrop: { [weak self] index in self?.select(index) },
            onEnd: { [weak self] in self?.close() }
        )
        panel.orderFrontRegardless()
        self.panel = panel
    }

    // A drop on a wedge reaches the panel after the mouse-up the drag monitor polls,
    // so closing immediately would pull the drop target away from under it.
    func dragEnded() {
        pendingClose?.cancel()
        pendingClose = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }

    private func select(_ index: Int) {
        onSelect(model.items[index], files)
    }

    private func close() {
        pendingClose?.cancel()
        pendingClose = nil
        panel?.orderOut(nil)
        panel = nil
        files = []
    }
}

private final class WheelDropView: NSView {
    private let model: WheelModel
    private let onDrop: (Int) -> Void
    private let onEnd: () -> Void
    private var dwellTarget: DwellTarget?
    private var dwell: Task<Void, Never>?

    private enum DwellTarget: Equatable {
        case item(Int)
        case centre
    }

    init(model: WheelModel, onDrop: @escaping (Int) -> Void, onEnd: @escaping () -> Void) {
        self.model = model
        self.onDrop = onDrop
        self.onEnd = onEnd
        let size = WheelModel.canvas
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))

        let hosting = NSHostingView(rootView: WheelView(model: model))
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // Matches SwiftUI's top-left origin so the model's hit test and the drawing agree.
    override var isFlipped: Bool { true }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        track(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        track(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        model.highlighted = nil
        rest(on: nil)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let index = model.index(at: convert(sender.draggingLocation, from: nil)), accepts(index) else { return false }
        onDrop(index)
        return true
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onEnd()
    }

    private func track(_ sender: NSDraggingInfo) -> NSDragOperation {
        let point = convert(sender.draggingLocation, from: nil)
        let index = model.index(at: point)
        model.highlighted = index
        rest(on: index.map(DwellTarget.item) ?? (WheelModel.isInCentre(point) ? .centre : nil))
        guard let index, accepts(index) else { return [] }
        return .copy
    }

    private func accepts(_ index: Int) -> Bool {
        if case .open = model.items[index].action { false } else { true }
    }

    // Like Finder's spring-loaded folders, since nothing can be clicked mid-drag: resting on an
    // item with a sub-wheel opens it, and resting on the centre goes back.
    private func rest(on target: DwellTarget?) {
        guard target != dwellTarget else { return }
        dwellTarget = target
        dwell?.cancel()
        let opens =
            switch target {
            case .item(let index): !accepts(index)
            case .centre: model.canGoBack
            case nil: false
            }
        guard opens, let target else { return }
        dwell = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            switch target {
            case .item(let index): model.open(index)
            case .centre: model.back()
            }
            dwellTarget = nil
        }
    }
}
