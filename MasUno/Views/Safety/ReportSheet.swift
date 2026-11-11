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

    /// Who "Block" is offered for once the report is sent.
    var person: PersonSummary? {
        switch self {
        case .person(let person): person
        case .game: nil
        case .message(let message): message.sender
        }
    }
}

/// Report a person, a game or a chat message (SPEC §7.6.6). After sending, people can also be blocked.
struct ReportSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var target: ReportSubject

    @State private var reason: ReportReason?
    @State private var note = ""
    @State private var isSent = false
    @State private var blockTarget: PersonSummary?
    @State private var isSending = false
    @State private var errorMessage: String?

    private static let noteLimit = 280

    var body: some View {
        NavigationStack {
            Group {
                if isSent { sentView } else { form }
            }
            .background(Theme.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                        .tint(Theme.ink)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.background)
        .blockConfirmation(person: $blockTarget) { dismiss() }
    }

    private var title: LocalizedStringKey {
        switch target {
        case .person(let person): "Report \(person.displayName)"
        case .game: "Report game"
        case .message: "Report message"
        }
    }

    private var form: some View {
        Form {
            Section {
                ForEach(ReportReason.allCases) { option in
                    Button {
                        reason = option
                    } label: {
                        HStack {
                            Text(option.title).foregroundStyle(Theme.ink)
                            Spacer()
                            if reason == option {
                                Image(systemName: "checkmark").foregroundStyle(Theme.accent).fontWeight(.semibold)
                            }
                        }
                    }
                    .accessibilityAddTraits(reason == option ? .isSelected : [])
                }
            } header: {
                Text("What's wrong?")
            }

            if case .message(let message) = target {
                Section {
                    Text(verbatim: message.body).foregroundStyle(Theme.ink)
                } header: {
                    Text("\(message.sender.displayName) wrote")
                }
            }

            Section {
                TextField("Add details (optional)", text: $note, axis: .vertical)
                    .lineLimit(3...6)
                    .onChange(of: note) { if note.count > Self.noteLimit { note = String(note.prefix(Self.noteLimit)) } }
            } footer: {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Theme.error)
                } else {
                    Text("Only the masUNO team sees reports.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
            Button("Send report") {
                Task { await send() }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .buttonSizing(.flexible)
            .fontWeight(.semibold)
            .disabled(reason == nil || isSending)
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 8)
        }
    }

    private func send() async {
        guard let reason else { return }
        isSending = true
        defer { isSending = false }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await store.report(target.target, reason: reason, note: trimmed.isEmpty ? nil : trimmed)
            errorMessage = nil
            withAnimation { isSent = true }
        } catch {
            errorMessage = (error as? DomainError ?? .offline).message
        }
    }

    private var sentView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent)
            Text("Thanks — we'll review this within 24 hours.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Spacer()
            if let person = target.person {
                Button("Block \(person.displayName)", role: .destructive) { blockTarget = person }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.destructive)
                    .controlSize(.large)
                    .buttonSizing(.flexible)
                    .fontWeight(.semibold)
            }
            Button("Done") { dismiss() }
                .buttonStyle(.glassProminent)
                .tint(Theme.accentSoft)
                .foregroundStyle(Theme.ink)
                .controlSize(.large)
                .buttonSizing(.flexible)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 48)
        .padding(.bottom, 8)
    }
}
