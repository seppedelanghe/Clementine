import SwiftUI

enum WheelAction: Hashable {
    case convert(OutputFormat)
    case placeholder
}

struct WheelItem: Hashable {
    let title: String
    let symbol: String
    let action: WheelAction
}

@MainActor
@Observable
final class WheelModel {
    nonisolated static let diameter: CGFloat = 280
    nonisolated static let innerRadius: CGFloat = 50

    var title = ""
    var items: [WheelItem] = []
    var highlighted: Int?

    // Angles are measured clockwise from 12 o'clock; wedge 0 is centred on it.
    nonisolated static func wedgeWidth(count: Int) -> Double {
        2 * .pi / Double(count)
    }

    nonisolated static func point(angle: Double, radius: CGFloat, center: CGPoint) -> CGPoint {
        CGPoint(x: center.x + radius * sin(angle), y: center.y - radius * cos(angle))
    }

    // `point` is in top-left-origin coordinates of the wheel's square.
    func index(at point: CGPoint) -> Int? {
        guard !items.isEmpty else { return nil }
        let dx = point.x - Self.diameter / 2
        let dy = point.y - Self.diameter / 2
        let distance = hypot(dx, dy)
        guard distance >= Self.innerRadius, distance <= Self.diameter / 2 else { return nil }

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
        let center = CGPoint(x: WheelModel.diameter / 2, y: WheelModel.diameter / 2)
        let labelRadius = (WheelModel.diameter / 2 + WheelModel.innerRadius) / 2

        ZStack {
            ForEach(Array(model.items.enumerated()), id: \.offset) { index, item in
                let isHighlighted = index == model.highlighted
                Wedge(index: index, count: count)
                    .fill(isHighlighted ? Color.accentColor : Color(nsColor: .windowBackgroundColor))
                Wedge(index: index, count: count)
                    .stroke(Color(nsColor: .separatorColor))
                VStack(spacing: 4) {
                    Image(systemName: item.symbol)
                    Text(item.title)
                        .font(.caption)
                }
                .foregroundStyle(isHighlighted ? Color.white : Color.primary)
                .position(
                    WheelModel.point(
                        angle: Double(index) * WheelModel.wedgeWidth(count: count),
                        radius: labelRadius,
                        center: center
                    )
                )
            }
            Text(model.highlighted.map { model.items[$0].title } ?? model.title)
                .font(.headline)
                .position(center)
        }
        .frame(width: WheelModel.diameter, height: WheelModel.diameter)
    }
}

private struct Wedge: Shape {
    let index: Int
    let count: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let width = WheelModel.wedgeWidth(count: count)
        let middle = Double(index) * width
        // SwiftUI measures from 3 o'clock, a quarter turn before the wheel's 12 o'clock origin.
        let start = Angle(radians: middle - width / 2 - .pi / 2)
        let end = Angle(radians: middle + width / 2 - .pi / 2)

        var path = Path()
        path.addArc(center: center, radius: rect.width / 2, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: WheelModel.innerRadius, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}
