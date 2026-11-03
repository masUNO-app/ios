import SwiftUI

/// Report a person or a game (SPEC §7.6.6). After sending, people can also be blocked.
struct ReportSheet: View {
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var target: ReportTarget

    @State private var reason: EventStore.ReportReason?
    @State private var note = ""
    @State private var isSent = false
    @State private var blockTarget: String?

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
        case .person(let name): "Report \(Person.display(name))"
        case .game: "Report game"
        }
    }

    private var form: some View {
        Form {
            Section {
                ForEach(EventStore.ReportReason.allCases) { option in
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

            Section {
                TextField("Add details (optional)", text: $note, axis: .vertical)
                    .lineLimit(3...6)
                    .onChange(of: note) { if note.count > Self.noteLimit { note = String(note.prefix(Self.noteLimit)) } }
            } footer: {
                Text("Only the masUNO team sees reports.")
            }
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
            Button("Send report") {
                guard let reason else { return }
                store.report(target, reason: reason, note: note)
                withAnimation { isSent = true }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .buttonSizing(.flexible)
            .fontWeight(.semibold)
            .disabled(reason == nil)
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 8)
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
            if case .person(let name) = target {
                Button("Block \(Person.display(name))", role: .destructive) { blockTarget = name }
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
