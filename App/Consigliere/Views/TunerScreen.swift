import ConsigliereCore
import SwiftUI

/// The tuner: the note in the middle, a scale with a needle under it, plain words for what to do
/// ("12 cents flat · tighten"), the strings of the tuning, and a thin bar showing the microphone hears you.
struct TunerScreen: View {
    @ObservedObject var model: NotchModel

    private var idle: Bool { model.tuner.state == .idle }
    private var inTune: Bool { !idle && model.tuner.inTune }
    private var flat: Bool { !idle && !inTune && model.tuner.cents < 0 }
    private var sharp: Bool { !idle && !inTune && model.tuner.cents > 0 }

    /// "E2" into "E" and "2". Chromatic mode already keeps them apart.
    private var noteParts: (letter: String, octave: String) {
        guard !idle, let label = model.tuner.label else { return ("–", "") }
        if let octave = model.tuner.octave { return (label, String(octave)) }
        let letters = label.prefix { !$0.isNumber && $0 != "-" }
        return (String(letters), String(label.dropFirst(letters.count)))
    }

    /// One plain sentence: what is wrong, and which way to turn the peg.
    private var hint: String {
        if let problem = model.tunerProblem { return problem }
        if idle { return model.tunerLevel > 0.12 ? "listening…" : "pluck a string" }
        if inTune { return "in tune" }
        let cents = Int(abs(model.tuner.cents).rounded())
        return model.tuner.cents < 0 ? "\(cents) cents flat · tighten" : "\(cents) cents sharp · loosen"
    }

    var body: some View {
        VStack(spacing: 10) {
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

            HStack(alignment: .center) {
                sideLabel("flat", lit: flat)
                Spacer()
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(noteParts.letter)
                        .font(model.theme.font(88, .thin))
                        .kerning(-3)
                        .foregroundStyle(idle ? NotchTheme.faint : NotchTheme.text)
                    Text(noteParts.octave)
                        .font(model.theme.mono(15))
                        .foregroundStyle(NotchTheme.faint)
                }
                Spacer()
                sideLabel("sharp", lit: sharp)
            }
            .frame(height: 84)

            gauge
                .frame(height: 34)

            Text(hint)
                .font(model.theme.mono(11))
                .kerning(0.8)
                .foregroundStyle(inTune ? NotchTheme.text : (idle ? NotchTheme.faint : model.theme.accent))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(spacing: 8) {
                ForEach(Array(model.tuningStrings.enumerated()), id: \.offset) { index, name in
                    let active = !idle && model.tuner.stringIndex == index
                    let locked = model.lockedStrings.contains(index)
                    Text(name)
                        .font(model.theme.mono(11))
                        .foregroundStyle(active ? NotchTheme.text : (locked ? model.theme.accent : NotchTheme.faint))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(locked ? model.theme.accent.opacity(0.16) : Color.clear))
                        .overlay(Circle().stroke(active ? model.theme.accent : Color.white.opacity(0.14), lineWidth: active ? 1.5 : 1))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 2)

            // The microphone's level. If this never moves while you play, the Mac is not hearing the instrument.
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
                    Rectangle()
                        .fill(model.theme.accent.opacity(0.8))
                        .frame(width: proxy.size.width * CGFloat(max(0, min(1, model.tunerLevel))), height: 2)
                        .animation(.linear(duration: 0.08), value: model.tunerLevel)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 6)
    }

    private func sideLabel(_ text: String, lit: Bool) -> some View {
        Text(text)
            .font(model.theme.mono(10))
            .kerning(1)
            .foregroundStyle(lit ? model.theme.accent : NotchTheme.faint.opacity(0.6))
            .frame(width: 52)
    }

    /// A scale from 50 cents flat to 50 cents sharp, a band in the middle for "close enough", and the needle.
    private var gauge: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let mid = proxy.size.height / 2
            let clamped = max(-50, min(50, model.tuner.cents))
            let needleX = width * CGFloat(0.5 + clamped / 100)
            let band = width * CGFloat(max(2, model.tunerTolerance) * 2 / 100)
            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(inTune ? 0.22 : 0.07))
                    .frame(width: band, height: 26)
                    .position(x: width / 2, y: mid)
                ForEach(-10...10, id: \.self) { step in
                    Rectangle()
                        .fill(Color.white.opacity(step == 0 ? 0.9 : (step % 5 == 0 ? 0.4 : 0.18)))
                        .frame(width: 1, height: step == 0 ? 26 : (step % 5 == 0 ? 16 : 8))
                        .position(x: width * CGFloat(0.5 + Double(step) * 0.05), y: mid)
                }
                Capsule()
                    .fill(inTune ? NotchTheme.text : model.theme.accent)
                    .frame(width: 3, height: 32)
                    .shadow(color: inTune ? .white : model.theme.accent, radius: inTune ? 10 : 6)
                    .opacity(idle ? 0.2 : 1)
                    .position(x: needleX, y: mid)
                    .animation(.linear(duration: 0.07), value: model.tuner.cents)
            }
        }
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
