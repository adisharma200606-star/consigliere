import SwiftUI

/// A quick look at recent notes or upcoming reminders, so what was captured does not vanish.
/// Reminders can be ticked off right here; clicking a line opens it in its own app.
struct GlanceScreen: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.glanceTitle.liner)
                .font(model.theme.mono(10))
                .kerning(1)
                .foregroundStyle(NotchTheme.faint)
                .padding(.horizontal, 10)

            VStack(spacing: 0) {
                Rectangle().fill(NotchTheme.hairline).frame(height: 1)
                if model.glanceItems.isEmpty {
                    Text(model.glanceEmpty.liner)
                        .font(model.theme.font(model.theme.textSize * 0.85, .light))
                        .foregroundStyle(NotchTheme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                }
                ForEach(model.glanceItems) { item in
                    HStack(spacing: 12) {
                        if let done = item.done {
                            Button { model.onGlanceTick(item.id) } label: {
                                ZStack {
                                    Circle().stroke(done ? model.theme.accent : NotchTheme.secondary, lineWidth: 1)
                                    if done { Circle().fill(model.theme.accent).padding(4) }
                                }
                                .frame(width: 14, height: 14)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(String(format: "%02d", item.id + 1))
                                .font(model.theme.mono(10))
                                .foregroundStyle(NotchTheme.faint)
                                .frame(width: 24, alignment: .leading)
                        }
                        Button { model.onGlanceOpen(item.id) } label: {
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.title.liner)
                                    .font(model.theme.font(model.theme.textSize * 0.9, .light))
                                    .strikethrough(item.done == true, color: NotchTheme.secondary)
                                    .foregroundStyle(item.done == true ? NotchTheme.secondary : NotchTheme.text)
                                    .lineLimit(1)
                                Spacer(minLength: 10)
                                Text(item.detail.liner)
                                    .font(model.theme.mono(10))
                                    .foregroundStyle(NotchTheme.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 40)
                    .overlay(alignment: .bottom) { Rectangle().fill(NotchTheme.hairline).frame(height: 1) }
                }
            }

            if !model.glanceButtons.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(model.glanceButtons.enumerated()), id: \.offset) { index, title in
                        Button(title) { model.onGlanceButton(index) }
                            .buttonStyle(PillButtonStyle(theme: model.theme))
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }
}
