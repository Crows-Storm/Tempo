import Foundation

enum MarkdownTasks {
    static func toggle(in source: String, at index: Int) -> String {
        guard index >= 0 else { return source }
        let taskLine = /^( *)([-*+]|\d+[.)]) (\[[ xX]\])(.*)$/
        var inFence = false
        var seen = 0
        var lines: [String] = []
        for piece in source.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(piece)
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
            } else if !inFence, let match = line.wholeMatch(of: taskLine) {
                if seen == index {
                    let box = String(match.output.3)
                    let next = box.compare("[x]", options: .caseInsensitive) == .orderedSame ? "[ ]" : "[x]"
                    line = "\(match.output.1)\(match.output.2) \(next)\(match.output.4)"
                }
                seen += 1
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
