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
                    .frame(maxWidth: .infinity)
                    .frame(height: height(for: chart))
                    .clipped()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Attention flow"))
                    .accessibilityValue(Text(summary(chart)))
                if !chart.nodes.contains(where: { $0.column == 1 }) {
                    Text("No window titles. Allow Accessibility in Settings to record the front window.")
                        .font(.caption)
                        .foregroundStyle(TempoColor.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
    @State private var hoverPoint: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let placed = SankeyLayout.place(diagram, in: geo.size)
            let hit = hoverPoint.flatMap {
                SankeyFocus.hit(at: $0, nodes: placed.nodes, links: placed.links)
            }
            let keep = hit.map { SankeyFocus.relatedIDs(to: $0, links: placed.links) }
            Canvas { context, size in
                let drawn = size == geo.size ? placed : SankeyLayout.place(diagram, in: size)
                draw(context: &context, placed: drawn, keep: keep)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case let .active(point):
                    hoverPoint = point
                case .ended:
                    hoverPoint = nil
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let hit {
                    Text("\(hit.label) · \(TempoFormat.minutesValue(hit.seconds))")
                        .font(.caption)
                        .foregroundStyle(TempoColor.label)
                        .lineLimit(2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func draw(
        context: inout GraphicsContext,
        placed: (nodes: [SankeyPlacedNode], links: [SankeyPlacedLink]),
        keep: Set<String>?
    ) {
        let dimming = keep != nil
        for link in placed.links {
            let on = keep?.contains(link.id) ?? true
            let path = Path(SankeyFocus.ribbonPath(link))
            context.fill(
                path,
                with: .color(color(for: link.colorKey).opacity(on ? (dimming ? 0.78 : 0.42) : 0.08))
            )
        }
        for node in placed.nodes {
            let on = keep?.contains(node.id) ?? true
            let rounded = Path(roundedRect: node.frame, cornerRadius: 3, style: .continuous)
            context.fill(rounded, with: .color(color(for: node).opacity(on ? 1 : 0.18)))
            if contrast == .increased {
                context.stroke(rounded, with: .color(TempoColor.secondary), lineWidth: 0.5)
            }
            let resolved = context.resolve(
                Text(node.label)
                    .font(.caption.weight(on && dimming ? .semibold : .regular))
                    .foregroundStyle(on ? TempoColor.label : TempoColor.secondary.opacity(0.45))
            )
            if node.column == 0 {
                context.draw(resolved, at: CGPoint(x: node.frame.minX - 8, y: node.frame.midY), anchor: .trailing)
            } else {
                context.draw(resolved, at: CGPoint(x: node.frame.maxX + 8, y: node.frame.midY), anchor: .leading)
            }
        }
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
