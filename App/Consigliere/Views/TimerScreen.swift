import ConsigliereCore
import SwiftUI

/// The timer. Two faces on one screen:
///
/// - **Setting one** (no timer running): the length in big numbers, minus and plus, a row of usual lengths, Start.
///   Opened by typing just `timer`. Enter starts it; the up and down arrows change it by a minute.
/// - **Running**: a ring that drains, the time left, when it ends, and pause, more time, cancel.
///   Opened by clicking the time beside the closed notch, or by typing `timer` while one runs.
struct TimerScreen: View {
    @ObservedObject var model: NotchModel

    private static let presets = [1, 5, 10, 15, 25, 45, 60]

    var body: some View {
        Group {
            if model.timerText == nil { setup } else { running }
        }
        .padding(.horizontal, 10)
    }

    // MARK: Setting one

    private var setup: some View {
        VStack(spacing: 14) {
            HStack {
                Text("NEW TIMER")
                    .font(model.theme.mono(10))
                    .kerning(1)
                    .foregroundStyle(NotchTheme.faint)
                Spacer()
                Text("↑ ↓ change · enter starts")
                    .font(model.theme.mono(10))
                    .kerning(0.6)
                    .foregroundStyle(NotchTheme.faint)
            }

            HStack(alignment: .center) {
                Button { model.onTimerSet(model.timerSetupSeconds - 60) } label: { Text("−") }
                    .buttonStyle(StepButtonStyle(theme: model.theme))
                Spacer()
                Text(CountdownTimer.format(remainingMs: model.timerSetupSeconds * 1000))
                    .font(model.theme.font(72, .thin))
                    .monospacedDigit()
                    .kerning(-3)
                    .foregroundStyle(NotchTheme.text)
                Spacer()
                Button { model.onTimerSet(model.timerSetupSeconds + 60) } label: { Text("+") }
                    .buttonStyle(StepButtonStyle(theme: model.theme))
            }

            HStack(spacing: 6) {
                ForEach(TimerScreen.presets, id: \.self) { minutes in
                    Button { model.onTimerSet(minutes * 60) } label: { Text("\(minutes)m") }
                        .buttonStyle(ChipButtonStyle(theme: model.theme, selected: model.timerSetupSeconds == minutes * 60))
                }
            }

            Button { model.onTimerStart() } label: {
                Text("start").frame(maxWidth: .infinity)
            }
            .buttonStyle(FilledButtonStyle(theme: model.theme))
        }
    }

    // MARK: Running

    private var running: some View {
        VStack(spacing: 14) {
            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: CGFloat(max(0, min(1, model.timerFraction))))
                        .stroke(model.theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: model.theme.accent.opacity(model.timerPaused ? 0 : 0.8), radius: 5)
                        .animation(.linear(duration: 0.5), value: model.timerFraction)
                    Text(model.timerPaused ? "PAUSED" : "LEFT")
                        .font(model.theme.mono(9))
                        .kerning(1)
                        .foregroundStyle(model.timerPaused ? model.theme.accent : NotchTheme.faint)
                }
                .frame(width: 84, height: 84)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.timerText ?? "0:00")
                        .font(model.theme.font(64, .thin))
                        .monospacedDigit()
                        .kerning(-3)
                        .foregroundStyle(model.timerPaused ? NotchTheme.secondary : NotchTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(model.timerEnds)
                        .font(model.theme.mono(10))
                        .kerning(0.8)
                        .foregroundStyle(NotchTheme.faint)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button(model.timerPaused ? "resume" : "pause") { model.onTimerPause() }
                    .buttonStyle(PillButtonStyle(theme: model.theme))
                Button("+1 min") { model.onAddTime(60) }
                    .buttonStyle(PillButtonStyle(theme: model.theme))
                Button("+5 min") { model.onAddTime(300) }
                    .buttonStyle(PillButtonStyle(theme: model.theme))
                Spacer()
                Button("cancel") { model.onStopTimer() }
                    .buttonStyle(PillButtonStyle(theme: model.theme))
            }
        }
    }
}

/// The round minus and plus beside the time.
private struct StepButtonStyle: ButtonStyle {
    let theme: NotchTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.font(26, .light))
            .foregroundStyle(configuration.isPressed ? theme.accent : NotchTheme.text)
            .frame(width: 44, height: 44)
            .overlay(Circle().stroke(configuration.isPressed ? theme.accent : Color.white.opacity(0.18), lineWidth: 1))
            .contentShape(Circle())
    }
}

/// One of the usual lengths. The chosen one is filled in.
private struct ChipButtonStyle: ButtonStyle {
    let theme: NotchTheme
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.mono(11))
            .foregroundStyle(selected ? Color.black : NotchTheme.text)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(selected ? theme.accent : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(selected || configuration.isPressed ? theme.accent : Color.white.opacity(0.18), lineWidth: 1))
            .contentShape(Rectangle())
    }
}

/// The one button that matters on the screen.
private struct FilledButtonStyle: ButtonStyle {
    let theme: NotchTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.mono(12, medium: true))
            .kerning(1)
            .textCase(.uppercase)
            .foregroundStyle(Color.black)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(theme.accent.opacity(configuration.isPressed ? 0.7 : 1)))
            .contentShape(Rectangle())
    }
}
