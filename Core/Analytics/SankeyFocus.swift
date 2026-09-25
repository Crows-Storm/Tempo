import CoreGraphics
import Foundation

enum SankeyHit: Equatable, Sendable {
    case node(id: String, label: String, seconds: Double)
    case link(id: String, label: String, seconds: Double)

    var id: String {
        switch self {
        case let .node(id, _, _): id
        case let .link(id, _, _): id
        }
    }

    var label: String {
        switch self {
        case let .node(_, label, _): label
        case let .link(_, label, _): label
        }
    }

    var seconds: Double {
        switch self {
        case let .node(_, _, seconds): seconds
        case let .link(_, _, seconds): seconds
        }
    }
}

enum SankeyFocus {
    static func hit(
        at point: CGPoint,
        nodes: [SankeyPlacedNode],
        links: [SankeyPlacedLink]
    ) -> SankeyHit? {
        if let node = nodes.first(where: { hitFrame(for: $0).contains(point) }) {
            return .node(id: node.id, label: node.label, seconds: node.seconds)
        }
        for link in links.reversed() {
            if ribbonPath(link).contains(point, using: .winding, transform: .identity) {
                return .link(
                    id: link.id,
                    label: "\(link.sourceLabel) → \(link.targetLabel)",
                    seconds: link.seconds
                )
            }
        }
        return nil
    }

    static func relatedIDs(to hit: SankeyHit, links: [SankeyPlacedLink]) -> Set<String> {
        switch hit {
        case let .node(id, _, _):
            return flow(from: id, links: links)
        case let .link(id, _, _):
            guard let link = links.first(where: { $0.id == id }) else { return [id] }
            var keep = flow(downstreamFrom: link.target, upstreamFrom: link.source, links: links)
            keep.insert(id)
            keep.insert(link.source)
            keep.insert(link.target)
            return keep
        }
    }

    static func hitFrame(for node: SankeyPlacedNode) -> CGRect {
        let pad: CGFloat = 3
        if node.column == 0 {
            return CGRect(
                x: node.frame.minX - SankeyLayout.labelWidth,
                y: node.frame.minY - pad,
                width: node.frame.width + SankeyLayout.labelWidth,
                height: node.frame.height + pad * 2
            )
        }
        return CGRect(
            x: node.frame.minX,
            y: node.frame.minY - pad,
            width: node.frame.width + SankeyLayout.labelWidth,
            height: node.frame.height + pad * 2
        )
    }

    static func ribbonPath(_ link: SankeyPlacedLink) -> CGPath {
        let path = CGMutablePath()
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
        return path
    }

    private static func flow(from nodeID: String, links: [SankeyPlacedLink]) -> Set<String> {
        flow(downstreamFrom: nodeID, upstreamFrom: nodeID, links: links)
    }

    private static func flow(
        downstreamFrom: String,
        upstreamFrom: String,
        links: [SankeyPlacedLink]
    ) -> Set<String> {
        var keep: Set<String> = [downstreamFrom, upstreamFrom]
        var frontier = [downstreamFrom]
        while !frontier.isEmpty {
            var next: [String] = []
            for link in links where frontier.contains(link.source) {
                keep.insert(link.id)
                if keep.insert(link.target).inserted {
                    next.append(link.target)
                }
            }
            frontier = next
        }
        frontier = [upstreamFrom]
        while !frontier.isEmpty {
            var next: [String] = []
            for link in links where frontier.contains(link.target) {
                keep.insert(link.id)
                if keep.insert(link.source).inserted {
                    next.append(link.source)
                }
            }
            frontier = next
        }
        return keep
    }
}
