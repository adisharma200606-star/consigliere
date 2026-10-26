import SwiftUI

/// What sits inside the expanded notch. DynamicNotchKit builds this view once and keeps it, so it never
/// changes identity; it simply shows whichever screen the model asks for.
struct NotchRootView: View {
    @ObservedObject var model: NotchModel

    /// The expanded notch sizes itself to its content, so the width is set here.
    static let width: CGFloat = 440

    var body: some View {
        Group {
            switch model.screen {
            case .input: InputScreen(model: model)
            case .line: LineScreen(model: model)
            case .pull: PullScreen(model: model)
            case .tuner: TunerScreen(model: model)
            case .answer: AnswerScreen(model: model)
            case .chooser: ChooserScreen(model: model)
            case .timer: TimerScreen(model: model)
            case .glance: GlanceScreen(model: model)
            case .jobs: JobsScreen(model: model)
            }
        }
        .frame(width: NotchRootView.width, alignment: .leading)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .foregroundStyle(NotchTheme.text)
        .animation(model.theme.spring, value: model.screen)
        .animation(model.theme.spring, value: model.rows)
        .animation(model.theme.spring, value: model.jobRows)
    }
}

/// Shown to the left of the closed notch while a timer runs: a small dot in the glow colour.
struct CompactLeadingView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        HStack(spacing: 6) {
            // A job is waiting but he has been asked to stay in: only his head peeks out.
            if model.jobWaiting {
                CharacterView(frames: model.character)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
                    .onTapGesture { model.onJobWaitingTap() }
            }
            Rectangle()
                .fill(model.theme.accent)
                .frame(width: 2, height: 10)
                .shadow(color: model.theme.accent, radius: 4)
                .opacity(model.timerText == nil ? 0 : 1)
                .contentShape(Rectangle())
                .onTapGesture { model.onTimerTap() }
        }
        .padding(8)
    }
}

/// Shown to the right of the closed notch while a timer runs: the time left.
struct CompactTrailingView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        Text(model.timerText ?? "")
            .font(model.theme.mono(12))
            .monospacedDigit()
            .foregroundStyle(NotchTheme.text)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture { model.onTimerTap() }
    }
}
