import SwiftUI

/// The reply to a question: at most three sentences, and a command to copy when there is one.
struct AnswerScreen: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.question.liner)
                .font(model.theme.mono(10))
                .kerning(0.6)
                .foregroundStyle(NotchTheme.faint)
                .lineLimit(1)

            Text(model.isThinking ? "thinking…" : model.answerText)
                .font(model.theme.font(model.theme.textSize * 0.9, .light))
                .foregroundStyle(model.isThinking ? NotchTheme.secondary : NotchTheme.text)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            if let command = model.answerCommand {
                HStack(spacing: 8) {
                    Text("$").font(model.theme.mono(12)).foregroundStyle(model.theme.accent)
                    Text(command)
                        .font(model.theme.mono(12))
                        .foregroundStyle(NotchTheme.text)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    Button(model.didCopy ? "copied" : "copy") { model.onCopyCommand() }
                        .buttonStyle(PillButtonStyle(theme: model.theme))
                }
                .padding(.leading, 12)
                .padding(.trailing, 6)
                .padding(.vertical, 6)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(NotchTheme.hairline, lineWidth: 1))
            }
        }
        .padding(.horizontal, 10)
    }
}
