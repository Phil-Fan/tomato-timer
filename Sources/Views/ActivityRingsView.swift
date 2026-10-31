import SwiftUI

/// 一圈的目标完成情况。
struct ActivityRing: Identifiable {
    let id: String
    let color: Color
    /// 完成度，1 表示闭合；超过 1 也按闭合绘制。
    let progress: Double

    var isClosed: Bool { progress >= 1 }
}

/// Apple Watch 风格的多级活动圆环：每个目标一圈，颜色各自独立，达成即闭合。
struct ActivityRingsView<Center: View>: View {
    let rings: [ActivityRing]
    let size: CGFloat

    private let center: () -> Center

    @State private var appeared = false

    init(rings: [ActivityRing], size: CGFloat, @ViewBuilder center: @escaping () -> Center) {
        self.rings = rings
        self.size = size
        self.center = center
    }

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                ringView(ring, index: index)
            }

            center()
                .frame(width: holeDiameter + thickness * 0.6)
                .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .onAppear { appeared = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rings.count) 个目标，已闭合 \(closedCount) 个")
    }

    private var closedCount: Int {
        rings.filter(\.isClosed).count
    }

    // MARK: - 几何

    private var count: Int {
        max(1, rings.count)
    }

    private var margin: CGFloat {
        size * 0.022
    }

    /// 中心留白，保证百分比和分钟数放得下。
    private var holeDiameter: CGFloat {
        size * 0.42
    }

    /// 相邻两圈圆心之间的距离。
    private var step: CGFloat {
        let band = size / 2 - margin - holeDiameter / 2
        return max(1, band / CGFloat(count))
    }

    private var spacing: CGFloat {
        min(3.5, step * 0.24)
    }

    private var thickness: CGFloat {
        max(2.5, min(12, step - spacing))
    }

    private var outermostRadius: CGFloat {
        size / 2 - margin - thickness / 2
    }

    private func radius(at index: Int) -> CGFloat {
        outermostRadius - CGFloat(index) * step
    }

    // MARK: - 圆环

    private func ringView(_ ring: ActivityRing, index: Int) -> some View {
        let sweep = min(1, max(0, ring.progress))
        let radius = radius(at: index)
        let closed = ring.isClosed

        return ZStack {
            Circle()
                .stroke(ring.color.opacity(closed ? 0.22 : 0.16), lineWidth: thickness)

            Circle()
                .trim(from: 0, to: appeared ? sweep : 0)
                .stroke(
                    // 未闭合时从浅到深收尾，闭幕后整圈颜色均匀，接缝自然消失。
                    AngularGradient(
                        colors: closed
                            ? [ring.color, ring.color.opacity(0.88), ring.color]
                            : [ring.color.opacity(0.5), ring.color],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(closed ? 360 : max(1, 360 * sweep))
                    ),
                    style: StrokeStyle(lineWidth: thickness, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(
                    color: ring.color.opacity(closed ? 0.24 : 0.15),
                    radius: closed ? thickness * 0.25 : 1.5
                )
        }
        .frame(width: radius * 2, height: radius * 2)
        .animation(.easeOut(duration: 0.75).delay(Double(index) * 0.06), value: appeared)
        .animation(.easeOut(duration: 0.4), value: sweep)
    }
}
