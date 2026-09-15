import SwiftUI

/// Songbird's optical-disc mark. Its two sparse groove arcs can rotate while a
/// physical disc is active, while the rim and hub remain stationary and crisp.
public struct AudioCDIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let color: Color
    private let isRotating: Bool

    public init(color: Color = .primary, isRotating: Bool = false) {
        self.color = color
        self.isRotating = isRotating
    }

    public var body: some View {
        let animatesGrooves = isRotating && !reduceMotion

        TimelineView(
            .animation(minimumInterval: 1 / 30, paused: !animatesGrooves)
        ) { timeline in
            Canvas { context, size in
                drawDisc(
                    in: &context,
                    size: size,
                    grooveRotation: animatesGrooves ? rotation(at: timeline.date) : 0
                )
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func drawDisc(
        in context: inout GraphicsContext,
        size: CGSize,
        grooveRotation: Double
    ) {
        let side = min(size.width, size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let outerRadius = side * 0.44
        let grooveRadius = side * 0.33
        let hubRadius = side * 0.13
        let spindleRadius = side * 0.035
        let lineWidth = max(1, side * 0.065)
        let stroke = StrokeStyle(
            lineWidth: lineWidth,
            lineCap: .round,
            lineJoin: .round
        )

        context.stroke(
            Path(ellipseIn: circle(center: center, radius: outerRadius)),
            with: .color(color),
            style: stroke
        )
        context.stroke(
            Path(ellipseIn: circle(center: center, radius: hubRadius)),
            with: .color(color),
            style: stroke
        )
        context.fill(
            Path(ellipseIn: circle(center: center, radius: spindleRadius)),
            with: .color(color)
        )

        for startDegrees in [180.0, 0.0] {
            var groove = Path()
            groove.addArc(
                center: center,
                radius: grooveRadius,
                startAngle: .degrees(startDegrees + grooveRotation),
                endAngle: .degrees(startDegrees + 90 + grooveRotation),
                clockwise: false
            )
            context.stroke(groove, with: .color(color), style: stroke)
        }
    }

    private func rotation(at date: Date) -> Double {
        let revolutionDuration = 4.0
        let progress = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: revolutionDuration) / revolutionDuration
        return progress * 360
    }

    private func circle(center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
    }
}
