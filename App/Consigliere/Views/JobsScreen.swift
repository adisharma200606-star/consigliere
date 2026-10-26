import SwiftUI

/// Today's jobs, as a checklist you work in directly: type at the bottom and press Enter to add (commas for
/// several), click a box to tick one off (a small pixel explosion), "start" to open what the job needs,
/// right-click to delete. Escape or a click elsewhere closes it.
struct JobsScreen: View {
    @ObservedObject var model: NotchModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                // Click him to let him out to play.
                CharacterView(frames: model.character)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
                    .onTapGesture { model.onCharacterTap() }
                VStack(alignment: .leading, spacing: 2) {
                    Text("today's jobs")
                        .font(model.theme.mono(10))
                        .kerning(1)
                        .foregroundStyle(NotchTheme.faint)
                    Text(model.jobsDate.liner)
                        .font(model.theme.font(model.theme.textSize * 0.95, .light))
                        .foregroundStyle(NotchTheme.text)
                }
                Spacer()
                Text(model.jobsCount.liner)
                    .font(model.theme.mono(10))
                    .foregroundStyle(model.theme.accent)
            }
            .padding(.horizontal, 8)

            VStack(spacing: 0) {
                Rectangle().fill(NotchTheme.hairline).frame(height: 1)
                if model.jobRows.isEmpty {
                    Text("nothing on the books yet. type below.")
                        .font(model.theme.font(model.theme.textSize * 0.85, .light))
                        .foregroundStyle(NotchTheme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                }
                ForEach(model.jobRows) { row in
                    JobRowView(model: model, row: row)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("+")
                    .font(model.theme.mono(14, medium: true))
                    .foregroundStyle(model.theme.accent)
                TextField("", text: $model.jobDraft, prompt: Text("add a job: read 30 min, gym by 7pm").foregroundColor(NotchTheme.faint))
                    .textFieldStyle(.plain)
                    .font(model.theme.font(model.theme.textSize * 1.05, .light))
                    .foregroundStyle(NotchTheme.text)
                    .tint(model.theme.accent)
                    .focused($focused)
                    .disableAutocorrection(true)
                    // Enter is handled in NotchController's key monitor, the same single path as the box.
                    .onChange(of: model.jobDraft) { _ in model.onJobDraftChange() }
            }
            .padding(.horizontal, 12)

            Text("enter adds · commas for several · right-click to delete · esc closes")
                .font(model.theme.mono(9))
                .kerning(0.4)
                .foregroundStyle(NotchTheme.faint)
                .padding(.horizontal, 12)
        }
        .padding(.horizontal, 4)
        .onAppear { focused = true }
        .onChange(of: model.focusToken) { _ in focused = true }
    }
}

private struct JobRowView: View {
    @ObservedObject var model: NotchModel
    let row: NotchModel.JobRow

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button { model.onJobToggle(row.id) } label: {
                PixelCheckbox(done: row.done, accent: model.theme.accent)
                    .frame(width: 16, height: 16)
                    .overlay {
                        if let boom = model.boom, boom.rowID == row.id {
                            PixelBoom(accent: model.theme.accent).id(boom.serial)
                        }
                    }
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title.liner)
                    .font(model.theme.font(model.theme.textSize * 0.95, row.done ? .light : .regular))
                    .strikethrough(row.done, color: NotchTheme.secondary)
                    .foregroundStyle(row.done ? NotchTheme.secondary : NotchTheme.text)
                    .lineLimit(1)
                if !row.detail.isEmpty {
                    Text(row.detail.liner)
                        .font(model.theme.mono(9))
                        .foregroundStyle(NotchTheme.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if row.canStart && !row.done {
                Button("start") { model.onJobStart(row.id) }
                    .buttonStyle(PillButtonStyle(theme: model.theme))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 46)
        .overlay(alignment: .bottom) { Rectangle().fill(NotchTheme.hairline).frame(height: 1) }
        .contentShape(Rectangle())
        .contextMenu {
            if !row.done { Button("Start") { model.onJobStart(row.id) } }
            Button(row.done ? "Not done after all" : "Done") { model.onJobToggle(row.id) }
            Button("Delete") { model.onJobDelete(row.id) }
        }
    }
}

/// A checkbox drawn as pixels: an outline when open, a filled square with a pixel tick when done.
struct PixelCheckbox: View {
    let done: Bool
    let accent: Color

    /// The tick, on an 8 by 8 grid.
    private static let tick = [
        "........",
        "......#.",
        ".....##.",
        "#...##..",
        "##.##...",
        ".###....",
        "..#.....",
        "........",
    ]

    var body: some View {
        Canvas { context, size in
            let cell = size.width / 8
            func pixel(_ x: Int, _ y: Int, _ color: Color) {
                context.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)), with: .color(color))
            }
            if done {
                for y in 0..<8 { for x in 0..<8 { pixel(x, y, accent) } }
                for (y, row) in Self.tick.enumerated() {
                    for (x, ch) in row.enumerated() where ch == "#" { pixel(x, y, .black) }
                }
            } else {
                for i in 0..<8 {
                    pixel(i, 0, NotchTheme.secondary)
                    pixel(i, 7, NotchTheme.secondary)
                    pixel(0, i, NotchTheme.secondary)
                    pixel(7, i, NotchTheme.secondary)
                }
            }
        }
    }
}

/// The pixel explosion when a job is ticked off: square bits fly out and fade, moving in chunky steps like an
/// old game rather than smoothly, and a pixel ring flashes outwards.
struct PixelBoom: View {
    let accent: Color
    @State private var start = Date()

    private static let duration = 0.7
    private static let steps = 9.0
    /// Sixteen bits: direction in degrees, how far, how big, which colour.
    private static let bits: [(angle: Double, distance: Double, size: Double, color: Int)] = (0..<16).map { i in
        let jitter = [0, 9, -7, 4, -11, 6, -3, 10, -6, 2, -9, 7, -4, 11, -2, 5][i]
        let far = [34, 26, 40, 30, 22, 38, 28, 36, 24, 42, 32, 27, 39, 23, 35, 29][i]
        return (Double(i) * 22.5 + Double(jitter), Double(far), i % 3 == 0 ? 4 : 3, i % 4)
    }

    private func color(_ index: Int) -> Color {
        switch index {
        case 0: return accent
        case 1: return Color(red: 0.95, green: 0.60, blue: 0.23)   // the dragon's orange
        case 2: return .white
        default: return Color(red: 0.25, green: 0.64, blue: 0.61)  // his wings
        }
    }

    var body: some View {
        TimelineView(.animation) { context in
            let raw = min(1, context.date.timeIntervalSince(start) / Self.duration)
            // Quantised: the explosion moves in a few hard steps, which is what makes it read as pixels.
            let t = (raw * Self.steps).rounded(.down) / Self.steps
            let eased = 1 - pow(1 - t, 2)
            ZStack {
                if raw < 1 {
                    ForEach(0..<Self.bits.count, id: \.self) { i in
                        let bit = Self.bits[i]
                        let r = bit.angle * .pi / 180
                        Rectangle()
                            .fill(color(bit.color))
                            .frame(width: bit.size, height: bit.size)
                            .offset(x: (cos(r) * bit.distance * eased / 2).rounded() * 2,
                                    y: (sin(r) * bit.distance * eased / 2).rounded() * 2)
                            .opacity(1 - t)
                    }
                    Rectangle()
                        .stroke(accent, lineWidth: 2)
                        .frame(width: 16 + 40 * eased, height: 16 + 40 * eased)
                        .opacity(t < 0.5 ? 0.8 - t : 0)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
