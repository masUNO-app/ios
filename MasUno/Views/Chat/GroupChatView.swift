import SwiftUI

/// Not in the Figma yet — a minimal local-only chat so "Open group chat" goes somewhere.
/// TODO(backend): real-time messaging. A link to an existing group chat could stand in for MVP.
struct GroupChatView: View {
    @Environment(EventStore.self) private var store
    @State private var viewModel: GroupChatViewModel

    init(eventID: SportsEvent.ID) {
        _viewModel = State(initialValue: GroupChatViewModel(eventID: eventID))
    }

    var body: some View {
        if let event = viewModel.event(in: store) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(event.messages) { message in
                            bubble(message, in: event).id(message.id)
                        }
                    }
                    .padding(20)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: event.messages.count) {
                    if let last = event.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            .background(Theme.cream)
            .navigationTitle(event.title)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { composer }
            .onAppear { viewModel.markRead(in: store) }
        }
    }

    private func bubble(_ message: ChatMessage, in event: SportsEvent) -> some View {
        let isMine = message.sender == Person.you
        return VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
            Text("\(message.sender) · \(event.role(of: message.sender))")
                .font(.caption)
                .foregroundStyle(message.sender == event.host ? Theme.orange : Theme.secondaryInk)
            Text(message.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .foregroundStyle(isMine ? .white : Theme.ink)
                .background(isMine ? Theme.orange : Theme.card, in: .rect(cornerRadius: 18))
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
    }

    private var composer: some View {
        @Bindable var viewModel = viewModel

        return HStack(spacing: 10) {
            TextField("Message", text: $viewModel.draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassEffect(.regular.interactive(), in: .capsule)
            Button("Send", systemImage: "arrow.up") {
                viewModel.send(in: store)
            }
            .labelStyle(.iconOnly)
            .font(.headline)
            .frame(width: 44, height: 44)
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(Theme.orange)
            .disabled(!viewModel.canSend)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}
