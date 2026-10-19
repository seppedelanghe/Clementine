import SwiftUI

enum WheelAction: Hashable {
    case convert(OutputFormat)
    case quickAction(QuickAction)
    case shrink(Shrink.Option)
    // Resting on the item swaps the wheel to these; dropping on it does nothing.
    case open([WheelItem])
}

struct WheelItem: Hashable {
    let title: String
    // Only where items differ in kind; formats are told apart by their names.
    let symbol: String?
    let action: WheelAction
}

@MainActor
@Observable
final class WheelModel {
    nonisolated static let diameter: CGFloat = 280
    // Wide enough to keep the dragged file's preview off the segments.
    nonisolated static let innerRadius: CGFloat = 56
    // Room around the ring for the title above it and the hovered segment moving out.
    nonisolated static let margin: CGFloat = 44
    nonisolated static let canvas = diameter + 2 * margin
    nonisolated static let nudge: CGFloat = 6

    private(set) var title = ""
    private(set) var items: [WheelItem] = []
    var highlighted: Int?
    var isOpen = false
    // The levels a sub-wheel was opened from, innermost last.
    private var parents: [(title: String, items: [WheelItem])] = []

    var canGoBack: Bool { !parents.isEmpty }

    func show(title: String, items: [WheelItem]) {
        self.title = title
        self.items = items
        highlighted = nil
        parents = []
    }

    func open(_ index: Int) {
        guard case .open(let children) = items[index].action else { preconditionFailure("\(items[index].title) has no sub-wheel") }
        parents.append((title, items))
        title = items[index].title
        items = children
        highlighted = nil
    }

    func back() {
        let parent = parents.removeLast()
        title = parent.title
        items = parent.items
        highlighted = nil
    }

    // Angles are measured clockwise from 12 o'clock; wedge 0 is centred on it.
    nonisolated static func wedgeWidth(count: Int) -> Double {
        2 * .pi / Double(count)
    }

    nonisolated static func point(angle: Double, radius: CGFloat, center: CGPoint) -> CGPoint {
        CGPoint(x: center.x + radius * sin(angle), y: center.y - radius * cos(angle))
    }

    // `point` is in top-left-origin coordinates of the canvas.
    nonisolated static func isInCentre(_ point: CGPoint) -> Bool {
        hypot(point.x - canvas / 2, point.y - canvas / 2) < innerRadius
    }

    // The gaps between segments count towards their neighbours, so a drop never falls through.
    func index(at point: CGPoint) -> Int? {
        guard !items.isEmpty else { return nil }
        let dx = point.x - Self.canvas / 2
        let dy = point.y - Self.canvas / 2
        let distance = hypot(dx, dy)
        guard distance >= Self.innerRadius, distance <= Self.diameter / 2 + Self.nudge else { return nil }

        let width = Self.wedgeWidth(count: items.count)
        var angle = atan2(dx, -dy)
        if angle < 0 { angle += 2 * .pi }
        let shifted = (angle + width / 2).truncatingRemainder(dividingBy: 2 * .pi)
        return Int(shifted / width) % items.count
    }
}

struct WheelView: View {
    let model: WheelModel

    var body: some View {
        let count = model.items.count
        let center = CGPoint(x: WheelModel.canvas / 2, y: WheelModel.canvas / 2)
        let labelRadius = (WheelModel.diameter / 2 + WheelModel.innerRadius) / 2

        ZStack {
            ForEach(Array(model.items.enumerated()), id: \.offset) { index, item in
                let isHighlighted = index == model.highlighted
                let angle = Double(index) * WheelModel.wedgeWidth(count: count)
                let nudge = isHighlighted ? WheelModel.nudge : 0
                let segment = Segment(index: index, count: count)
                ZStack {
                    Backdrop()
                        .clipShape(segment)
                    segment
                        .fill(Color.accentColor)
                        .opacity(isHighlighted ? 1 : 0)
                    segment
                        .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                    VStack(spacing: 3) {
                        if let symbol = item.symbol {
                            Image(systemName: symbol)
                                .font(.system(size: 16))
                        }
                        Text(item.title)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(isHighlighted ? Color.white : Color.primary)
                    .position(WheelModel.point(angle: angle, radius: labelRadius, center: center))
                }
                .offset(x: nudge * sin(angle), y: -nudge * cos(angle))
            }
            if model.canGoBack {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .position(center)
            }
            // Above the ring rather than in its centre, where the dragged file's preview covers it.
            Text(model.highlighted.map { model.items[$0].title } ?? model.title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Backdrop().clipShape(Capsule()))
                .overlay(Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
                .position(x: center.x, y: WheelModel.margin / 2 - 2)
        }
        .frame(width: WheelModel.canvas, height: WheelModel.canvas)
        .scaleEffect(model.isOpen ? 1 : 0.85)
        .opacity(model.isOpen ? 1 : 0)
        .animation(.spring(duration: 0.2), value: model.highlighted)
        .onAppear {
            withAnimation(.spring(duration: 0.3, bounce: 0.3)) { model.isOpen = true }
        }
    }
}

// SwiftUI's materials follow the window's active state, and the wheel's panel is never active,
// so they would always look dimmed.
private struct Backdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

// A ring segment with an even gap to its neighbours and rounded corners.
private struct Segment: Shape {
    let index: Int
    let count: Int
    private let gap: CGFloat = 4
    private let corner: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let width = WheelModel.wedgeWidth(count: count)
        // SwiftUI measures from 3 o'clock, a quarter turn before the wheel's 12 o'clock origin.
        let middle = Double(index) * width - .pi / 2
        // Drawn shrunk by the corner radius, then grown back by stroking with round joins.
        let outer = WheelModel.diameter / 2 - corner
        let inner = WheelModel.innerRadius + corner
        let halfGap = count > 1 ? gap / 2 + corner : 0
        // The angle that leaves `halfGap` between the edge and the dividing line, at each radius.
        let outerInset = asin(halfGap / outer)
        let innerInset = asin(halfGap / inner)

        var path = Path()
        path.addArc(
            center: center,
            radius: outer,
            startAngle: .radians(middle - width / 2 + outerInset),
            endAngle: .radians(middle + width / 2 - outerInset),
            clockwise: false
        )
        path.addArc(
            center: center,
            radius: inner,
            startAngle: .radians(middle + width / 2 - innerInset),
            endAngle: .radians(middle - width / 2 + innerInset),
            clockwise: true
        )
        path.closeSubpath()
        let shape = path.cgPath
        let rounding = shape.copy(strokingWithWidth: corner * 2, lineCap: .round, lineJoin: .round, miterLimit: 10)
        return Path(shape.union(rounding))
    }
}
