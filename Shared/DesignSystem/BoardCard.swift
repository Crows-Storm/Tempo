import SwiftUI

struct BoardCard: View {
    var board: BoardOverview
    var action: () -> Void
    var pin: () -> Void
    var archive: () -> Void
    var unarchive: () -> Void
    var delete: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: TempoSpacing.xs) {
                    Text(board.name)
                        .font(.headline)
                        .foregroundStyle(TempoColor.label)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Spacer(minLength: TempoSpacing.xs)
                    if board.archived {
                        Image(systemName: "archivebox.fill")
                            .font(.caption)
                            .foregroundStyle(TempoColor.secondary)
                            .accessibilityLabel(Text("Archived"))
                    } else if board.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(TempoColor.breakTint)
                            .accessibilityLabel(Text("Pin"))
                    }
                }
                Text(TempoFormat.minutesValue(board.spentHours * 3600))
                    .font(.callout)
                    .foregroundStyle(TempoColor.secondary)
                    .monospacedDigit()
                if board.total > 0 {
                    ProgressView(value: board.progress)
                        .progressViewStyle(.linear)
                        .tint(TempoColor.info)
                    Text("\(board.done) of \(board.total) done")
                        .font(.caption)
                        .foregroundStyle(TempoColor.secondary)
                        .monospacedDigit()
                } else {
                    Text("No cards yet")
                        .font(.caption)
                        .foregroundStyle(TempoColor.tertiary)
                }
                HStack(spacing: TempoSpacing.md) {
                    countLabel("To Do", board.todo)
                    countLabel("In Progress", board.inProgress)
                    countLabel("Done", board.done)
                }
                if let next = board.nextTitle, !next.isEmpty {
                    Text(next)
                        .font(.callout)
                        .foregroundStyle(TempoColor.label)
                        .lineLimit(1)
                }
            }
            .padding(TempoSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: TempoRadius.column, style: .continuous)
                    .fill(.quaternary.opacity(0.28))
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: TempoRadius.column, style: .continuous))
        .opacity(board.archived ? 0.62 : 1)
        .contextMenu {
            if board.archived {
                Button("Unarchive", action: unarchive)
            } else {
                Button(board.pinned ? "Unpin" : "Pin", action: pin)
                Button("Archive", action: archive)
                    .disabled(!board.canArchive)
            }
            Button("Delete", role: .destructive, action: delete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(board.name))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityHint(Text("Shows the board."))
    }

    private func countLabel(_ title: LocalizedStringKey, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(TempoColor.label)
            Text(title)
                .font(.caption2)
                .foregroundStyle(TempoColor.secondary)
                .lineLimit(1)
        }
    }

    private var accessibilityValue: String {
        let time = TempoFormat.spoken(board.spentHours * 3600)
        return "\(time), \(board.todo), \(board.inProgress), \(board.done)"
    }
}

struct NewBoardCard: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: TempoSpacing.sm) {
                Image(systemName: "plus")
                    .font(.title2)
                    .foregroundStyle(TempoColor.secondary)
                Text("New Board")
                    .font(.headline)
                    .foregroundStyle(TempoColor.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 148)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: TempoRadius.column, style: .continuous)
                    .fill(.quaternary.opacity(0.28))
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: TempoRadius.column, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TempoRadius.column, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .help("New Board")
        .accessibilityLabel(Text("New Board"))
    }
}

enum BoardGrid {
    static let columns = [GridItem(.adaptive(minimum: 240), spacing: TempoSpacing.md, alignment: .top)]
}
