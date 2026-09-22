import SwiftUI

struct SessionSankey: View {
    var diagram: SankeyDiagram

    var body: some View {
        let chart = SankeyFlow.compacted(diagram)
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("Attention flow")
                .font(.headline)
            if chart.nodes.isEmpty {
                Text("No window activity for this session.")
                    .foregroundStyle(TempoColor.secondary)
            } else {
                SankeyCanvas(diagram: chart)
                    .frame(height: height(for: chart))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Attention flow"))
                    .accessibilityValue(Text(summary(chart)))
            }
        }
    }

    private func height(for chart: SankeyDiagram) -> CGFloat {
        let densest = [0, 1, 2].map { column in
            chart.nodes.filter { $0.column == column }.count
        }.max() ?? 2
        return max(260, CGFloat(densest) * 36 + 20)
    }

    private func summary(_ chart: SankeyDiagram) -> String {
        chart.nodes
            .filter { $0.column == 0 || $0.column == 2 }
            .map { "\($0.label) \(TempoFormat.spoken($0.seconds))" }
            .joined(separator: ", ")
    }
}

private struct SankeyCanvas: View {
    var diagram: SankeyDiagram
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Canvas { context, size in
            let placed = SankeyLayout.place(diagram, in: size)
            for link in placed.links {
                var path = Path()
                let mid = (link.x0 + link.x1) / 2
                path.move(to: CGPoint(x: link.x0, y: link.y0))
                path.addCurve(
                    to: CGPoint(x: link.x1, y: link.y1),
                    control1: CGPoint(x: mid, y: link.y0),
                    control2: CGPoint(x: mid, y: link.y1)
                )
                path.addLine(to: CGPoint(x: link.x1, y: link.y1 + link.h1))
                path.addCurve(
                    to: CGPoint(x: link.x0, y: link.y0 + link.h0),
                    control1: CGPoint(x: mid, y: link.y1 + link.h1),
                    control2: CGPoint(x: mid, y: link.y0 + link.h0)
                )
                path.closeSubpath()
                context.fill(path, with: .color(color(for: link.colorKey).opacity(0.42)))
            }
            for node in placed.nodes {
                let rounded = Path(roundedRect: node.frame, cornerRadius: 3, style: .continuous)
                context.fill(rounded, with: .color(color(for: node)))
                if contrast == .increased {
                    context.stroke(rounded, with: .color(TempoColor.secondary), lineWidth: 0.5)
                }
                let resolved = context.resolve(
                    Text(node.label)
                        .font(.caption)
                        .foregroundStyle(TempoColor.secondary)
                )
                if node.column == 2 {
                    context.draw(resolved, at: CGPoint(x: node.frame.maxX + 8, y: node.frame.midY), anchor: .leading)
                } else {
                    context.draw(resolved, at: CGPoint(x: node.frame.minX - 8, y: node.frame.midY), anchor: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func color(for node: SankeyPlacedNode) -> Color {
        if node.id == SankeyFlow.focusedID { return TempoColor.focus }
        if node.id == SankeyFlow.distractedID { return Color(nsColor: .systemGray) }
        if node.column == 1 { return Color(nsColor: .systemPurple) }
        return TempoColor.app(node.label)
    }

    private func color(for key: String) -> Color {
        if key == SankeyFlow.focusedID { return TempoColor.focus }
        if key == SankeyFlow.distractedID { return Color(nsColor: .systemGray) }
        return TempoColor.app(key)
    }
}
