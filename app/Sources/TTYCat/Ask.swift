// Answering a prompt from the panel: the board's Approval, Deny and question screens.
//
// As on the board, an answer names the exact prompt it was shown for (its rev), and a click
// this soon after a prompt appears isn't an answer to it. Each card takes `.id(rev)` from
// its parent, so a different prompt always gets a new card with its buttons unarmed.
import SwiftUI

private let armDelay = Duration.milliseconds(600)  // ARM_DELAY_MS in firmware/main/ui.c
private let maxTyped = 1000                        // approvals.MAX_TYPED

struct AskCard: View {
  @EnvironmentObject var m: TTYCatModel
  @StateObject private var armed = Local(false)
  let row: AgentRow
  var position: (at: Int, of: Int)?

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      header
      switch row.ask {
      case "approve": ApproveView(row: row, armed: armed.value)
      case "choice": QuestionsView(row: row, armed: armed.value)
      default: TerminalAskView(row: row)
      }
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .pixelBox(Palette.card, border: Palette.orange)
    .task {
      try? await Task.sleep(for: armDelay)
      // Still clicking, at bugs perhaps: what's under the pointer now is this prompt.
      while !Task.isCancelled, !HandsOff.clear(now: Date(), until: m.handsOffUntil, lastClick: m.lastPanelClick) {
        try? await Task.sleep(for: .milliseconds(100))
      }
      armed.value = true
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        Caps("\(row.n ?? "Agent") \u{B7} \(row.p ?? "")", color: Palette.white)
        if let host = row.host { Text(host).font(Pixel.small).foregroundStyle(Palette.muted2) }
        Spacer(minLength: 4)
        if let position, position.of > 1 {
          Text("\(position.at) of \(position.of)").font(Pixel.small).foregroundStyle(Palette.muted)
        } else {
          Text("waiting \(ageText(row.age))").font(Pixel.small).foregroundStyle(Palette.muted)
        }
      }
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(row.tool?.isEmpty == false ? row.tool! : "ASK").font(Pixel.hero).foregroundStyle(Palette.orange).lineLimit(1)
        Text(row.verb ?? "needs you").font(Pixel.small).foregroundStyle(Palette.muted2).lineLimit(1)
      }
    }
  }
}

// ---------------------------------------------------------------- allow / deny

private struct ApproveView: View {
  @EnvironmentObject var m: TTYCatModel
  @StateObject private var denying = Local(false)
  let row: AgentRow
  let armed: Bool

  private var busy: Bool { m.answering == row.rev }

  var body: some View {
    if denying.value {
      denyChoices
    } else {
      if let file = row.file {
        HStack(spacing: 6) {
          Text(file).font(Pixel.small).foregroundStyle(Palette.white).lineLimit(1)
          Text("+\(row.add ?? 0)").font(Pixel.small).foregroundStyle(Palette.green)
          Text("-\(row.del ?? 0)").font(Pixel.small).foregroundStyle(Palette.orange)
        }
      }
      CodeBox(text: row.body ?? "", diff: row.file != nil, shell: row.tool == "BASH")
      HStack(spacing: 6) {
        ChoiceButton(title: "Deny", icon: PixelIcon.cross, enabled: armed && !busy) { denying.value = true }
        ChoiceButton(title: busy ? "Sending" : "Allow", icon: PixelIcon.check, loud: true, enabled: armed && !busy) {
          m.answer(row, action: "allow")
        }
      }
    }
  }

  private var denyChoices: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(row.d ?? "").font(Pixel.small).foregroundStyle(Palette.muted2).lineLimit(1)
      DenyChoice(title: "Stop", detail: "ends the turn and waits for you", loud: true, enabled: !busy) {
        m.answer(row, action: "deny")
      }
      DenyChoice(title: "Try another way", detail: "\(row.n ?? "It") carries on without this", enabled: !busy) {
        m.answer(row, action: "deny-retry")
      }
      DenyChoice(title: "Explain first", detail: "\(row.n ?? "It") says why it needs this", enabled: !busy) {
        m.answer(row, action: "deny-explain")
      }
      PixelButton(title: "Back") { denying.value = false }
    }
  }
}

struct ChoiceButton: View {
  let title: String
  let icon: [UInt8]
  var loud = false
  let enabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        PixelIcon(rows: icon, scale: 2, color: !enabled ? Palette.faint : loud ? Palette.black : Palette.orange)
        Text(title.uppercased()).font(Pixel.button)
          .foregroundStyle(!enabled ? Palette.faint : loud ? Palette.black : Palette.white)
      }
      .frame(maxWidth: .infinity, minHeight: 36)
      .pixelBox(loud && enabled ? Palette.orange : Palette.tile, border: loud && enabled ? nil : Palette.line)
    }
    .buttonStyle(PixelPress())
    .disabled(!enabled)
  }
}

private struct DenyChoice: View {
  let title: String
  let detail: String
  var loud = false
  let enabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 1) {
        Caps(title, color: !enabled ? Palette.faint : loud ? Palette.black : Palette.white)
        Text(detail).font(Pixel.small).foregroundStyle(!enabled ? Palette.faint : loud ? Palette.black : Palette.muted)
      }
      .padding(.horizontal, 8)
      .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
      .pixelBox(loud && enabled ? Palette.orange : Palette.tile, border: loud && enabled ? nil : Palette.line)
    }
    .buttonStyle(PixelPress())
    .disabled(!enabled)
  }
}

private struct HeightKey: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// As tall as its content, up to a limit, then it scrolls. Measured, so nothing is cut off
/// by a wrong guess at how the text wraps. A window that hugs its content can't size a plain
/// ScrollView: left alone, it collapses.
struct FitScroll<Content: View>: View {
  @StateObject private var height = Local<CGFloat>(0)
  let tallest: CGFloat
  var hint: String?
  @ViewBuilder let content: Content

  private var overflows: Bool { height.value > tallest }

  var body: some View {
    VStack(alignment: .trailing, spacing: 2) {
      ScrollView(.vertical, showsIndicators: overflows) {
        content.background(GeometryReader { Color.clear.preference(key: HeightKey.self, value: $0.size.height) })
      }
      .frame(height: height.value == 0 ? 40 : min(height.value, tallest))
      .onPreferenceChange(HeightKey.self) { height.value = $0 }
      if overflows, let hint {
        Text(hint).font(Pixel.small).foregroundStyle(Palette.orange)
      }
    }
  }
}

/// All of a command or diff, scrolling if it's long: what gets approved is never cut off.
struct CodeBox: View {
  let text: String
  var diff = false
  var shell = false

  private var lines: [String] { text.components(separatedBy: "\n") }

  var body: some View {
    FitScroll(tallest: 190, hint: "scroll to read all of it") {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
          Text(line.isEmpty ? " " : line)
            .font(Pixel.body)
            .foregroundStyle(color(of: line))
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(6)
      .textSelection(.enabled)
      .pixelBox(Palette.code, border: Palette.line)
    }
  }

  private func color(of line: String) -> Color {
    if diff {
      if line.hasPrefix("+") { return Palette.green }
      if line.hasPrefix("-") { return Palette.orange }
      return Palette.muted
    }
    return shell ? Palette.green : Palette.white
  }
}

// ---------------------------------------------------------------- only in the terminal

private struct TerminalAskView: View {
  @EnvironmentObject var m: TTYCatModel
  let row: AgentRow

  var body: some View {
    CodeBox(text: row.body ?? row.d ?? "")
    Text(row.note ?? "Answer this one in the terminal")
      .font(Pixel.small).foregroundStyle(Palette.muted).lineLimit(2)
    if row.canOpen {
      ChoiceButton(title: "Open in terminal", icon: PixelIcon.right, loud: true, enabled: true) { m.open(row) }
    }
  }
}

// ---------------------------------------------------------------- questions

private final class Answers: ObservableObject {
  @Published var picked: [Set<Int>]
  @Published var typed: [String]

  init(count: Int) {
    picked = Array(repeating: [], count: count)
    typed = Array(repeating: "", count: count)
  }
}

private struct QuestionsView: View {
  @EnvironmentObject var m: TTYCatModel
  @StateObject private var answers: Answers
  let row: AgentRow
  let armed: Bool

  init(row: AgentRow, armed: Bool) {
    self.row = row
    self.armed = armed
    _answers = StateObject(wrappedValue: Answers(count: row.qs?.count ?? 0))
  }

  private var questions: [Question] { row.qs ?? [] }
  private var ready: Bool {
    !questions.isEmpty && questions.indices.allSatisfy {
      !answers.picked[$0].isEmpty || !answers.typed[$0].trimmingCharacters(in: .whitespaces).isEmpty
    }
  }
  private var busy: Bool { m.answering == row.rev }

  var body: some View {
    FitScroll(tallest: 400, hint: "scroll for the rest") {
      VStack(alignment: .leading, spacing: 10) {
        ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
          questionBlock(index, question)
        }
      }
    }
    ChoiceButton(title: busy ? "Sending" : "Send answer", icon: PixelIcon.right, loud: true, enabled: armed && ready && !busy) {
      m.answer(row, action: "answer", picks: picks)
    }
  }

  // Option numbers, not labels: the daemon looks the words up in the original question.
  private var picks: [[String: Any]] {
    questions.indices.map { index in
      let typed = answers.typed[index].trimmingCharacters(in: .whitespaces)
      return ["o": answers.picked[index].sorted(), "t": typed]
    }
  }

  private func questionBlock(_ index: Int, _ question: Question) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(question.q).font(Pixel.body).foregroundStyle(Palette.white)
        .fixedSize(horizontal: false, vertical: true)
      if question.m {
        Caps("Pick any", color: Palette.muted2)
      }
      ForEach(Array(question.o.enumerated()), id: \.offset) { number, option in
        OptionRow(option: option, many: question.m, on: answers.picked[index].contains(number)) {
          toggle(number, in: index, many: question.m)
        }
      }
      TextField(
        "", text: typedBinding(index, many: question.m),
        prompt: Text("or type an answer").foregroundStyle(Palette.faint)
      )
      .textFieldStyle(.plain)
      .font(Pixel.body)
      .foregroundStyle(Palette.white)
      .padding(.horizontal, 6)
      .frame(height: 26)
      .pixelBox(Palette.code, border: answers.typed[index].isEmpty ? Palette.line : Palette.orange)
    }
  }

  // One answer to a single choice, as on the board: picking one replaces any other.
  private func toggle(_ number: Int, in index: Int, many: Bool) {
    if answers.picked[index].contains(number) {
      answers.picked[index].remove(number)
    } else {
      if !many {
        answers.picked[index] = []
        answers.typed[index] = ""
      }
      answers.picked[index].insert(number)
    }
  }

  private func typedBinding(_ index: Int, many: Bool) -> Binding<String> {
    Binding(
      get: { answers.typed.indices.contains(index) ? answers.typed[index] : "" },
      set: { value in
        guard answers.typed.indices.contains(index) else { return }
        answers.typed[index] = String(value.prefix(maxTyped))
        if !many && !value.isEmpty { answers.picked[index] = [] }
      })
  }
}

private struct OptionRow: View {
  let option: QuestionOption
  let many: Bool
  let on: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(alignment: .top, spacing: 8) {
        if many {
          PixelCheckbox(on: on).padding(.top, 2)
        } else {
          ZStack {
            Rectangle().strokeBorder(on ? Palette.orange : Palette.faint, lineWidth: 2)
            if on { Rectangle().fill(Palette.orange).padding(4) }
          }
          .frame(width: 16, height: 16)
          .padding(.top, 2)
        }
        VStack(alignment: .leading, spacing: 0) {
          Text(option.l).font(Pixel.body).foregroundStyle(Palette.white)
            .fixedSize(horizontal: false, vertical: true)
          if !option.d.isEmpty {
            Text(option.d).font(Pixel.small).foregroundStyle(Palette.muted)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        Spacer(minLength: 0)
      }
      .padding(6)
      .frame(maxWidth: .infinity, alignment: .leading)
      .pixelBox(Palette.tile, border: on ? Palette.orange : Palette.line)
    }
    .buttonStyle(PixelPress())
  }
}
