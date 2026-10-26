import SwiftUI

/// One line: what he just said, or a confirmation such as "call mom · tomorrow 17:00". Quiet, lowercase,
/// after a dash, like a credit in the liner notes.
struct LineScreen: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // He is the one talking, so he sits beside what he says.
            CharacterView(frames: model.character)
                .frame(width: 26, height: 26)
            Text(model.lineText.liner)
                .font(model.theme.font(model.theme.textSize * 0.9, .light))
                .kerning(0.5)
                .lineLimit(2)
        }
        .foregroundStyle(model.theme.tint)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

/// Something handed back from the stash, with a way to ask for a different one.
struct PullScreen: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("from the vault")
                .font(model.theme.mono(10))
                .kerning(1)
                .foregroundStyle(NotchTheme.faint)
            Text(model.pullTitle)
                .font(model.theme.font(model.theme.textSize, .light))
                .foregroundStyle(NotchTheme.text)
                .lineLimit(3)
            Text(model.pullDetail.liner)
                .font(model.theme.mono(10))
                .foregroundStyle(NotchTheme.secondary)
                .lineLimit(1)
            Button("another") { model.onAnother() }
                .buttonStyle(PillButtonStyle(theme: model.theme))
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }
}

/// "Which one did you mean?" Used when two living bookmarks fit the same page.
struct ChooserScreen: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.chooserTitle.liner)
                .font(model.theme.mono(10))
                .kerning(0.6)
                .foregroundStyle(NotchTheme.secondary)
                .padding(.horizontal, 10)
            VStack(spacing: 0) {
                Rectangle().fill(NotchTheme.hairline).frame(height: 1)
                ForEach(Array(model.chooserOptions.enumerated()), id: \.offset) { index, option in
                    Button {
                        model.onChoose(index)
                    } label: {
                        HStack(spacing: 14) {
                            Text(String(format: "%02d", index + 1))
                                .font(model.theme.mono(10))
                                .foregroundStyle(model.theme.accent)
                            Text(option.liner)
                                .font(model.theme.font(model.theme.textSize, .light))
                                .foregroundStyle(NotchTheme.text)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .overlay(alignment: .bottom) { Rectangle().fill(NotchTheme.hairline).frame(height: 1) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Buttons in this look: a hairline outline and a small monospaced label. No fills, no pills of colour.
struct PillButtonStyle: ButtonStyle {
    let theme: NotchTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.mono(11))
            .kerning(0.6)
            .textCase(.lowercase)
            .foregroundStyle(configuration.isPressed ? theme.accent : NotchTheme.text)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(configuration.isPressed ? theme.accent : Color.white.opacity(0.18), lineWidth: 1)
            )
            .contentShape(Rectangle())
    }
}
