import SwiftUI

enum MarkdownBlock {
    struct ListItem {
        var ordinal: Int
        var text: AttributedString
        var checked: Bool?
    }

    case heading(level: Int, text: AttributedString)
    case paragraph(AttributedString)
    case quote(AttributedString)
    case list(ordered: Bool, items: [ListItem])
    case code(String)
    case thematicBreak

    var testLabel: String {
        switch self {
        case let .heading(level, text):
            return "h\(level):\(String(text.characters))"
        case let .paragraph(text):
            return "p:\(String(text.characters))"
        case let .quote(text):
            return "q:\(String(text.characters))"
        case let .list(ordered, items):
            let body = items.map { item in
                let mark = item.checked.map { $0 ? "[x]" : "[ ]" } ?? ""
                return mark + String(item.text.characters)
            }.joined(separator: "|")
            return "\(ordered ? "ol" : "ul"):\(body)"
        case let .code(text):
            return "code:\(text)"
        case .thematicBreak:
            return "hr"
        }
    }
}

struct MarkdownPreview: View {
    var source: String
    var lineLimit: Int?
    var compact: Bool = false
    var onToggleTask: ((Int) -> Void)?

    var body: some View {
        let blocks = Self.blocks(from: source)
        let taskIndices = Self.taskIndices(in: blocks)
        let content = VStack(alignment: .leading, spacing: compact ? TempoSpacing.xxs : TempoSpacing.xs) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { offset, block in
                blockView(block, taskIndices: taskIndices[offset])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: onToggleTask == nil ? .combine : .contain)

        if let lineLimit {
            content
                .frame(maxHeight: CGFloat(lineLimit) * (compact ? 18 : 22), alignment: .top)
                .clipped()
        } else {
            content
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock, taskIndices: [Int?]) -> some View {
        switch block {
        case let .heading(level, text):
            styledText(resolved(text, heading: level))
        case let .paragraph(text):
            styledText(resolved(text))
        case let .quote(text):
            HStack(alignment: .top, spacing: TempoSpacing.xs) {
                Capsule()
                    .fill(TempoColor.separator)
                    .frame(width: 3)
                styledText(resolved(text))
            }
        case let .list(ordered, items):
            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                    HStack(alignment: .firstTextBaseline, spacing: TempoSpacing.xs) {
                        listMarker(item, ordered: ordered, taskIndex: taskIndices.indices.contains(offset) ? taskIndices[offset] : nil)
                        styledText(resolved(item.text))
                    }
                }
            }
        case let .code(text):
            Text(text)
                .font(.system(compact ? .caption : .callout, design: .monospaced))
                .foregroundStyle(TempoColor.label)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(TempoSpacing.xs)
                .background {
                    RoundedRectangle(cornerRadius: TempoRadius.control, style: .continuous)
                        .fill(.quaternary.opacity(0.4))
                }
        case .thematicBreak:
            Divider()
        }
    }

    @ViewBuilder
    private func styledText(_ text: AttributedString) -> some View {
        let view = Text(text)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        if compact {
            view
        } else {
            view.textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func listMarker(_ item: MarkdownBlock.ListItem, ordered: Bool, taskIndex: Int?) -> some View {
        if let checked = item.checked {
            let icon = Image(systemName: checked ? "checkmark.square.fill" : "square")
                .foregroundStyle(checked ? TempoColor.info : TempoColor.secondary)
            if let onToggleTask, let taskIndex {
                icon
                    .frame(minWidth: 16, minHeight: 16)
                    .contentShape(Rectangle())
                    .highPriorityGesture(TapGesture().onEnded {
                        onToggleTask(taskIndex)
                    })
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(Text(checked ? "Completed" : "Incomplete"))
                    .accessibilityHint(Text(checked ? "Marks the item incomplete." : "Marks the item complete."))
                    .accessibilityAction {
                        onToggleTask(taskIndex)
                    }
            } else {
                icon
                    .accessibilityLabel(Text(checked ? "Completed" : "Incomplete"))
            }
        } else if ordered {
            Text("\(item.ordinal).")
                .font(compact ? .callout : .body)
                .foregroundStyle(TempoColor.secondary)
                .monospacedDigit()
        } else {
            Text("•")
                .font(compact ? .callout : .body)
                .foregroundStyle(TempoColor.secondary)
        }
    }

    private func resolved(_ text: AttributedString, heading: Int? = nil) -> AttributedString {
        Self.resolved(text, compact: compact, heading: heading)
    }

    private static func taskIndices(in blocks: [MarkdownBlock]) -> [[Int?]] {
        var next = 0
        return blocks.map { block in
            guard case let .list(_, items) = block else { return [] }
            return items.map { item in
                guard item.checked != nil else { return nil }
                let index = next
                next += 1
                return index
            }
        }
    }

    static func blocks(from source: String) -> [MarkdownBlock] {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        let parsed = (try? AttributedString(markdown: trimmed, options: options)) ?? AttributedString(trimmed)

        var keys: [BlockKey] = []
        var texts: [AttributedString] = []
        for run in parsed.runs {
            let key = BlockKey(intent: run.presentationIntent)
            let piece = fragment(parsed, run)
            if keys.last == key {
                texts[texts.count - 1] += piece
            } else {
                keys.append(key)
                texts.append(piece)
            }
        }

        var blocks: [MarkdownBlock] = []
        for (key, text) in zip(keys, texts) {
            let next = block(key: key, text: text)
            if case let .list(ordered, items) = next,
               case let .list(previousOrdered, previousItems) = blocks.last,
               ordered == previousOrdered {
                blocks[blocks.count - 1] = .list(ordered: ordered, items: previousItems + items)
            } else {
                blocks.append(next)
            }
        }
        return blocks
    }

    private static func block(key: BlockKey, text: AttributedString) -> MarkdownBlock {
        switch key.kind {
        case let .heading(level):
            .heading(level: level, text: text)
        case .paragraph:
            .paragraph(text)
        case .quote:
            .quote(text)
        case let .listItem(ordered, _, _, ordinal):
            .list(ordered: ordered, items: [listItem(ordinal: ordinal, text: text)])
        case .code:
            .code(String(text.characters).trimmingCharacters(in: .newlines))
        case .thematicBreak:
            .thematicBreak
        }
    }

    private static func listItem(ordinal: Int, text: AttributedString) -> MarkdownBlock.ListItem {
        let raw = String(text.characters)
        guard raw.hasPrefix("[") else {
            return MarkdownBlock.ListItem(ordinal: ordinal, text: text, checked: nil)
        }
        let checked: Bool?
        let prefix: String
        if raw.hasPrefix("[x] ") || raw.hasPrefix("[X] ") {
            checked = true
            prefix = String(raw.prefix(4))
        } else if raw.hasPrefix("[x]") || raw.hasPrefix("[X]") {
            checked = true
            prefix = String(raw.prefix(3))
        } else if raw.hasPrefix("[ ] ") {
            checked = false
            prefix = String(raw.prefix(4))
        } else if raw.hasPrefix("[ ]") {
            checked = false
            prefix = String(raw.prefix(3))
        } else {
            return MarkdownBlock.ListItem(ordinal: ordinal, text: text, checked: nil)
        }
        return MarkdownBlock.ListItem(ordinal: ordinal, text: dropPrefix(text, count: prefix.count), checked: checked)
    }

    private static func dropPrefix(_ text: AttributedString, count: Int) -> AttributedString {
        guard count > 0 else { return text }
        let characters = text.characters
        guard let index = characters.index(characters.startIndex, offsetBy: count, limitedBy: characters.endIndex) else {
            return AttributedString()
        }
        return AttributedString(text[index...])
    }

    private static func fragment(_ parsed: AttributedString, _ run: AttributedString.Runs.Run) -> AttributedString {
        if let inline = run.inlinePresentationIntent, inline.contains(.softBreak) {
            return AttributedString("\n")
        }
        return AttributedString(parsed[run.range])
    }

    private static func resolved(_ text: AttributedString, compact: Bool, heading: Int?) -> AttributedString {
        var result = AttributedString()
        let baseFont = headingFont(heading, compact: compact)
        let color: Color = {
            if heading != nil { return TempoColor.label }
            return compact ? TempoColor.secondary : TempoColor.label
        }()
        for run in text.runs {
            var piece = AttributedString(text[run.range])
            let range = piece.startIndex..<piece.endIndex
            var font = baseFont
            if let inline = run.inlinePresentationIntent {
                if inline.contains(.code) {
                    font = font.monospaced()
                }
                if inline.contains(.stronglyEmphasized) {
                    font = font.bold()
                }
                if inline.contains(.emphasized) {
                    font = font.italic()
                }
                if inline.contains(.strikethrough) {
                    piece[range].strikethroughStyle = .single
                }
            }
            piece[range].font = font
            piece[range].foregroundColor = color
            if let link = run.link {
                piece[range].link = link
                piece[range].foregroundColor = TempoColor.info
                piece[range].underlineStyle = .single
            }
            result += piece
        }
        return result
    }

    private static func headingFont(_ level: Int?, compact: Bool) -> Font {
        switch level {
        case 1:
            compact ? .headline : .title3
        case 2:
            compact ? .subheadline.weight(.semibold) : .headline
        case .some:
            .subheadline.weight(.semibold)
        case nil:
            compact ? .callout : .body
        }
    }
}

private struct BlockKey: Equatable {
    enum Kind: Equatable {
        case heading(Int)
        case paragraph
        case quote
        case listItem(ordered: Bool, listID: Int, itemID: Int, ordinal: Int)
        case code
        case thematicBreak
    }

    var kind: Kind

    init(intent: PresentationIntent?) {
        guard let intent else {
            kind = .paragraph
            return
        }
        var heading: Int?
        var ordered: Bool?
        var listID: Int?
        var itemID: Int?
        var ordinal: Int?
        var isCode = false
        var isQuote = false
        var isBreak = false
        for component in intent.components {
            switch component.kind {
            case let .header(level):
                heading = level
            case .orderedList:
                ordered = true
                listID = component.identity
            case .unorderedList:
                ordered = false
                listID = component.identity
            case let .listItem(value):
                ordinal = value
                itemID = component.identity
            case .codeBlock:
                isCode = true
            case .blockQuote:
                isQuote = true
            case .thematicBreak:
                isBreak = true
            default:
                break
            }
        }
        if isBreak {
            kind = .thematicBreak
        } else if isCode {
            kind = .code
        } else if let heading {
            kind = .heading(heading)
        } else if let ordered, let listID, let itemID, let ordinal {
            kind = .listItem(ordered: ordered, listID: listID, itemID: itemID, ordinal: ordinal)
        } else if isQuote {
            kind = .quote
        } else {
            kind = .paragraph
        }
    }
}
