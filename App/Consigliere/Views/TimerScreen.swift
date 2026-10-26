import SwiftUI

/// The running timer: time left, a bar that drains, and the controls.
/// Opened by clicking the time beside the closed notch, or by typing "timer" while one runs.
struct TimerScreen: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline) {
                Text(model.timerText ?? "0:00")
                    .font(model.theme.font(72, .thin))
                    .monospacedDigit()
                    .kerning(-3)
                    .foregroundStyle(NotchTheme.text)
                Spacer()
                Text("left")
                    .font(model.theme.mono(10))
                    .kerning(1)
                    .foregroundStyle(NotchTheme.faint)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1)
                    Rectangle()
                        .fill(model.theme.accent)
                        .frame(width: proxy.size.width * CGFloat(max(0, min(1, model.timerFraction))), height: 2)
                        .shadow(color: model.theme.accent, radius: 6)
                        .animation(.linear(duration: 0.5), value: model.timerFraction)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 6)

            HStack(spacing: 8) {
                Button("stop") { model.onStopTimer() }
                    .buttonStyle(PillButtonStyle(theme: model.theme))
                Spacer()
                Button("+1 min") { model.onAddTime(60) }
                    .buttonStyle(PillButtonStyle(theme: model.theme))
                Button("+5 min") { model.onAddTime(300) }
                    .buttonStyle(PillButtonStyle(theme: model.theme))
            }
        }
        .padding(.horizontal, 10)
    }
}
