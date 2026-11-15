import SwiftUI

/// Who a report sheet is about. The sheet needs the person's name; the RPC only takes IDs.
enum ReportSubject: Hashable, Identifiable {
    case person(PersonSummary)
    case game(UUID)
    case message(ChatMessage)

    var id: Self { self }

    var target: ReportTarget {
        switch self {
        case .person(let person): .person(person.id)
        case .game(let id): .game(id)
        case .message(let message): .message(message.id)
        }
    }

    /// Who "Block … too" is offered for once the report is sent.
    var person: PersonSummary? {
        switch self {
        case .person(let person): person
        case .game: nil
        case .message(let message): message.sender
        }
    }
}

/// Figma "Report Ricardo": a person, a game or a chat message (SPEC §7.6.6). One reason, an
/// optional note, **Send report**; then "Thanks for telling us", where people can also be blocked.
struct ReportSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var target: ReportSubject

    @State private var reason: ReportReason?
    @State private var note = ""
    @State private var isSent = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var noteIsFocused: Bool

    private static let noteLimit = 280

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                SheetHeader(title: Text(title), subtitle: Text("Only the masUNO team sees this.")) { dismiss() }
                    .padding(.bottom, 4)

                if case .message(let message) = target {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(message.sender.displayName) wrote")
                            .font(.rounded(.caption))
                            .foregroundStyle(Theme.muted)
                        Text(verbatim: message.body)
                            .font(.rounded(.subheadline))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(4)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.separator.opacity(0.6), in: .rect(cornerRadius: 16))
                }

                ForEach(ReportReason.listed) { option in
                    OptionRow(title: option.title(for: target.target), isSelected: reason == option) {
                        reason = option
                    }
                }

                HStack {
                    Text("Anything else we should know?")
                        .font(.rounded(.footnote, .bold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    OptionalTag()
                }
                .padding(.top, 4)

                TextField("Tell us what happened", text: $note, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.rounded(.callout))
                    .foregroundStyle(Theme.ink)
                    .focused($noteIsFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .cardSurface(radius: 16)
                    .onChange(of: note) { if note.count > Self.noteLimit { note = String(note.prefix(Self.noteLimit)) } }

                if let errorMessage {
                    Text(verbatim: errorMessage)
                        .font(.rounded(.caption))
                        .foregroundStyle(Theme.error)
                }

                Button {
                    Task { await send() }
                } label: {
                    if isSending { ProgressView().tint(Theme.onAccent) } else { Text("Send report") }
                }
                .pill(.primary)
                .disabled(reason == nil || isSending)
                .padding(.top, 8)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 22)
            .padding(.bottom, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .sheetChrome(detents: [.height(target.person == nil || isMessage ? 620 : 560), .large])
        .dialog(isPresented: $isSent, isDismissable: false) { thanks }
        #if DEBUG
        .onAppear {
            // `-screen report-sent`: straight to "Thanks for telling us".
            if UserDefaults.standard.string(forKey: "screen") == "report-sent" { isSent = true }
        }
        #endif
    }

    private var isMessage: Bool {
        if case .message = target { return true }
        return false
    }

    private var title: LocalizedStringKey {
        switch target {
        case .person(let person): "Report \(person.firstName)"
        case .game: "Report game"
        case .message: "Report message"
        }
    }

    /// Figma "Thanks for telling us": **Done**, or **Block Ricardo too** for a person.
    private var thanks: some View {
        let person = target.person
        let message = person.map {
            String(localized: "Only the masUNO team sees reports. We'll look into it within a day, and \($0.firstName) won't know it was you.")
        } ?? String(localized: "Only the masUNO team sees reports. We'll look into it within a day.")

        return DialogCard(
            systemImage: "checkmark.shield",
            title: Text("Thanks for telling us"),
            message: Text(verbatim: message),
            confirm: DialogAction("Done") { dismiss() },
            cancel: person.map { person in
                DialogAction("Block \(person.firstName) too") {
                    Task { await store.block(person) }
                    dismiss()
                }
            }
        )
    }

    private func send() async {
        guard let reason else { return }
        isSending = true
        defer { isSending = false }
        let detail = [reason.noteLead(for: target.target), note.trimmingCharacters(in: .whitespacesAndNewlines)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
        do {
            try await store.report(target.target, reason: reason, note: detail.isEmpty ? nil : String(detail.prefix(Self.noteLimit)))
            errorMessage = nil
            noteIsFocused = false
            isSent = true
        } catch {
            errorMessage = (error as? DomainError ?? .offline).message
        }
    }
}
