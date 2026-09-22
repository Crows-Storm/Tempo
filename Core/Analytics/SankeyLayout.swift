import CoreGraphics
import Foundation

struct SankeyPlacedNode: Equatable, Sendable, Identifiable {
    var id: String
    var label: String
    var column: Int
    var seconds: Double
    var frame: CGRect
}

struct SankeyPlacedLink: Equatable, Sendable, Identifiable {
    var id: String
    var source: String
    var target: String
    var sourceLabel: String
    var targetLabel: String
    var seconds: Double
    var distracted: Bool
    var colorKey: String
    var x0: CGFloat
    var y0: CGFloat
    var h0: CGFloat
    var x1: CGFloat
    var y1: CGFloat
    var h1: CGFloat
}

enum SankeyLayout {
    static let nodeWidth: CGFloat = 14
    static let labelWidth: CGFloat = 112
    static let minNode: CGFloat = 18
    static let spacing: CGFloat = 8
    static let verticalPad: CGFloat = 6

    static func place(_ diagram: SankeyDiagram, in size: CGSize) -> (nodes: [SankeyPlacedNode], links: [SankeyPlacedLink]) {
        guard size.width > 1, size.height > 1, !diagram.nodes.isEmpty else { return ([], []) }
        let plotLeft = labelWidth
        let plotRight = max(plotLeft + nodeWidth * 3, size.width - labelWidth)
        let xs: [CGFloat] = [
            plotLeft,
            plotLeft + (plotRight - plotLeft - nodeWidth) / 2,
            plotRight - nodeWidth
        ]
        let innerH = max(1, size.height - verticalPad * 2)

        var placed: [String: SankeyPlacedNode] = [:]
        for column in 0...2 {
            let nodes = diagram.nodes.filter { $0.column == column }
            guard !nodes.isEmpty else { continue }
            let total = nodes.reduce(0) { $0 + $1.seconds }
            let gaps = spacing * CGFloat(max(0, nodes.count - 1))
            let minTotal = minNode * CGFloat(nodes.count) + gaps
            let scale = minTotal > innerH ? innerH / minTotal : 1
            let usedMin = minNode * scale
            let usedGap = spacing * scale
            let leftover = max(0, innerH - usedMin * CGFloat(nodes.count) - usedGap * CGFloat(max(0, nodes.count - 1)))
            var y = verticalPad
            for node in nodes {
                let share = total > 0 ? node.seconds / total : 1 / Double(nodes.count)
                let height = usedMin + leftover * share
                placed[node.id] = SankeyPlacedNode(
                    id: node.id,
                    label: node.label,
                    column: column,
                    seconds: node.seconds,
                    frame: CGRect(x: xs[column], y: y, width: nodeWidth, height: height)
                )
                y += height + usedGap
            }
        }

        var sourceY: [String: CGFloat] = [:]
        var targetY: [String: CGFloat] = [:]
        for node in placed.values {
            sourceY[node.id] = node.frame.minY
            targetY[node.id] = node.frame.minY
        }

        let links = diagram.links.sorted { lhs, rhs in
            let ly = placed[lhs.source]?.frame.minY ?? 0
            let ry = placed[rhs.source]?.frame.minY ?? 0
            if ly != ry { return ly < ry }
            return (placed[lhs.target]?.frame.minY ?? 0) < (placed[rhs.target]?.frame.minY ?? 0)
        }

        var ribbons: [SankeyPlacedLink] = []
        for link in links {
            guard let source = placed[link.source], let target = placed[link.target] else { continue }
            let h0 = source.seconds > 0 ? source.frame.height * (link.seconds / source.seconds) : 0
            let h1 = target.seconds > 0 ? target.frame.height * (link.seconds / target.seconds) : 0
            let y0 = sourceY[source.id] ?? source.frame.minY
            let y1 = targetY[target.id] ?? target.frame.minY
            sourceY[source.id] = y0 + h0
            targetY[target.id] = y1 + h1
            let colorKey: String
            if source.column == 0 {
                colorKey = source.label
            } else if link.distracted || link.target == SankeyFlow.distractedID {
                colorKey = SankeyFlow.distractedID
            } else {
                colorKey = SankeyFlow.focusedID
            }
            ribbons.append(
                SankeyPlacedLink(
                    id: link.id,
                    source: source.id,
                    target: target.id,
                    sourceLabel: source.label,
                    targetLabel: target.label,
                    seconds: link.seconds,
                    distracted: link.distracted,
                    colorKey: colorKey,
                    x0: source.frame.maxX,
                    y0: y0,
                    h0: max(1, h0),
                    x1: target.frame.minX,
                    y1: y1,
                    h1: max(1, h1)
                )
            )
        }
        return (Array(placed.values), ribbons)
    }
}
