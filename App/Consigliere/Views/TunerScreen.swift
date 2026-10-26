import ConsigliereCore
import SwiftUI

/// The tuner: a huge thin note, how far off it is, a dot on a track, and the strings of the tuning.
struct TunerScreen: View {
    @ObservedObject var model: NotchModel

    private var inTune: Bool { model.tuner.inTune }
    private var accent: Color { inTune ? NotchTheme.ok : NotchTheme.off }

    /// "E2" into "E" and "2". Chromatic mode already keeps them apart.
    private var noteParts: (letter: String, octave: String) {
        guard model.tuner.state != .idle, let label = model.tuner.label else { return ("–", "") }
        if let octave = model.tuner.octave { return (label, String(octave)) }
        let letters = label.prefix { !$0.isNumber && $0 != "-" }
        return (String(letters), String(label.dropFirst(letters.count)))
    }

    private var centsText: String {
        let rounded = Int(model.tuner.cents.rounded())
        if rounded == 0 { return "0" }
        return rounded > 0 ? "+\(rounded)" : "−\(abs(rounded))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { model.onTuningStep(-1) } label: { Text("‹") }
                    .buttonStyle(RoundButtonStyle(theme: model.theme))
                Spacer()
                Text(model.tuningName.liner.replacingOccurrences(of: ", ", with: " / "))
                    .font(model.theme.mono(10))
                    .kerning(1)
                    .foregroundStyle(NotchTheme.faint)
                Spacer()
                Button { model.onTuningStep(1) } label: { Text("›") }
                    .buttonStyle(RoundButtonStyle(theme: model.theme))
            }

            HStack(alignment: .bottom) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(noteParts.letter)
                        .font(model.theme.font(118, .thin))
                        .kerning(-5)
                        .foregroundStyle(inTune ? NotchTheme.text : Color(white: 0.9))
                    Text(noteParts.octave)
                        .font(model.theme.mono(16))
                        .foregroundStyle(NotchTheme.faint)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if model.tuner.state == .idle {
                        Text("pluck a string")
                            .font(model.theme.mono(10))
                            .kerning(0.8)
                            .foregroundStyle(NotchTheme.faint)
                    } else {
                        Text(inTune ? "in tune" : centsText)
                            .font(model.theme.font(inTune ? 30 : 40, .thin))
                            .monospacedDigit()
                            .foregroundStyle(inTune ? NotchTheme.text : model.theme.accent)
                        if !inTune {
                            Text(model.tuner.cents < 0 ? "cents · tune up" : "cents · tune down")
                                .font(model.theme.mono(10))
                                .kerning(0.8)
                                .foregroundStyle(NotchTheme.secondary)
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            .frame(height: 100)
            .padding(.horizontal, 4)

            GeometryReader { proxy in
                let clamped = max(-50, min(50, model.tuner.cents))
                let x = proxy.size.width * CGFloat(0.5 + clamped / 100)
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.18)).frame(height: 1)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    Rectangle().fill(NotchTheme.text).frame(width: 1, height: 15)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    Rectangle()
                        .fill(inTune ? NotchTheme.text : model.theme.accent)
                        .frame(width: 2, height: 11)
                        .shadow(color: inTune ? .white : model.theme.accent, radius: inTune ? 10 : 6)
                        .opacity(model.tuner.state == .idle ? 0.25 : 1)
                        .position(x: x, y: proxy.size.height / 2)
                        .animation(.linear(duration: 0.09), value: model.tuner.cents)
                }
            }
            .frame(height: 20)
            .padding(.horizontal, 4)

            HStack(spacing: 6) {
                ForEach(Array(model.tuningStrings.enumerated()), id: \.offset) { index, name in
                    let active = model.tuner.state != .idle && model.tuner.stringIndex == index
                    let locked = model.lockedStrings.contains(index)
                    VStack(spacing: 6) {
                        Rectangle().fill(active ? model.theme.accent : Color.clear).frame(height: 1)
                        Text(name)
                            .font(model.theme.mono(12))
                            .foregroundStyle(active ? NotchTheme.text : (locked ? model.theme.accent : Color(white: 0.3)))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

struct RoundButtonStyle: ButtonStyle {
    let theme: NotchTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.font(18, .light))
            .foregroundStyle(configuration.isPressed ? theme.accent : NotchTheme.secondary)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
    }
}
