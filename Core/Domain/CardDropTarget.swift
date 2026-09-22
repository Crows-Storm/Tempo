import CoreGraphics
import Foundation

struct CardFrame: Equatable, Sendable {
    var id: String
    var minY: CGFloat
    var height: CGFloat

    var midY: CGFloat { minY + height / 2 }
}

enum CardDropTarget {
    static func beforeID(
        y: CGFloat,
        frames: [CardFrame],
        draggingID: String?,
        holdingBefore: String?,
        holdingThisColumn: Bool,
        gap: CGFloat
    ) -> String? {
        let usable = frames
            .filter { $0.id != draggingID && $0.height > 1 }
            .sorted { $0.minY < $1.minY }

        if holdingThisColumn {
            if let id = holdingBefore, let frame = usable.first(where: { $0.id == id }) {
                let top = frame.minY - gap
                if y >= top && y < frame.midY {
                    return id
                }
            } else if holdingBefore == nil, let last = usable.last, y >= last.midY {
                return nil
            }
        }

        for frame in usable where y < frame.midY {
            return frame.id
        }
        return nil
    }

    static func showsPlaceholder(draggingID: String?, probeListID: String?, columnID: String) -> Bool {
        draggingID != nil && probeListID == columnID
    }
}
