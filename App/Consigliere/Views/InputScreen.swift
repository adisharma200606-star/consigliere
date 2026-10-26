import SwiftUI

/// The box. Type a name and the matches appear under it, like a track list. Enter opens the marked one.
struct InputScreen: View {
    @ObservedObject var model: NotchModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                TextField("", text: $model.text)
                    .textFieldStyle(.plain)
                    .font(model.theme.font(model.theme.textSize * 3.2, .thin))
                    .kerning(-2)
                    .foregroundStyle(NotchTheme.text)
                    .tint(model.theme.accent)
                    .focused($focused)
                    .disableAutocorrection(true)
                    // Enter is handled centrally in NotchController's key monitor, not here — see the
                    // comment on `onEnter` there. Only one path exists, on purpose: with both wired up, a
                    // single Enter press would fire submit() twice, which for a toggle like "flip" means
                    // rotating and immediately rotating back, looking exactly like nothing happened.
                    .onChange(of: model.text) { newValue in model.onTextChange(newValue) }

                if model.isListening {
                    ListeningDots(color: model.theme.accent)
                } else {
                    Text(model.inputHint ?? "hold to talk")
                        .font(model.theme.mono(10))
                        .kerning(1.2)
                        .foregroundStyle(NotchTheme.faint)
                }
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                Rectangle().fill(NotchTheme.hairline).frame(height: 1)
                ForEach(model.rows) { row in
                    TrackRow(model: model, row: row, selected: row.id == model.selected)
                }
                if model.isUnknown {
                    HStack(spacing: 14) {
                        Text("--").font(model.theme.mono(10)).foregroundStyle(NotchTheme.faint).frame(width: 18, alignment: .leading)
                        Text("never heard of it").font(model.theme.font(model.theme.textSize, .light)).foregroundStyle(NotchTheme.secondary)
                        Spacer()
                    }
                    .padding(.leading, 13)
                    .frame(height: 44)
                }
            }
        }
        .padding(.horizontal, 4)
        .onAppear { focused = true }
        .onChange(of: model.focusToken) { _ in focused = true }
    }
}

/// One line of the list: a number, the name, and where it opens. The marked one gets a hairline of light.
private struct TrackRow: View {
    @ObservedObject var model: NotchModel
    let row: NotchModel.Row
    let selected: Bool

    var body: some View {
        Button {
            model.onSubmit(row.id)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(String(format: "%02d", row.id + 1))
                    .font(model.theme.mono(10))
                    .foregroundStyle(selected ? model.theme.accent : NotchTheme.faint)
                    .frame(width: 18, alignment: .leading)
                Text(row.title.liner)
                    .font(model.theme.font(model.theme.textSize, selected ? .regular : .light))
                    .foregroundStyle(selected ? NotchTheme.text : NotchTheme.faint)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text(row.detail.liner.replacingOccurrences(of: ", ", with: " / "))
                    .font(model.theme.mono(10))
                    .kerning(0.4)
                    .foregroundStyle(NotchTheme.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .frame(height: 44)
            .overlay(alignment: .leading) {
                Rectangle().fill(selected ? model.theme.accent : Color.clear).frame(width: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(NotchTheme.hairline).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Three dots that pulse while he is listening.
struct ListeningDots: View {
    let color: Color
    @State private var on = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: 4, height: 4)
                    .opacity(on ? 1 : 0.2)
                    .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(index) * 0.15), value: on)
            }
        }
        .padding(.bottom, 6)
        .onAppear { on = true }
    }
}
