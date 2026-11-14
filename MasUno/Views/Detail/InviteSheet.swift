import CoreImage.CIFilterBuiltins
import SwiftUI

/// Figma "Invite a friend": the game as its card, the link, **Share link** and **Show QR code**.
/// The link is the App Store listing: a link that opens this game needs Universal Links, which
/// come after the program (SPEC §7.6.4). The friend signs in with their own school email.
struct InviteSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var event: Game

    @State private var showsCode = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SheetHeader(
                    title: Text(event.isHostedByMe ? "Share game" : "Invite a friend"),
                    subtitle: Text("They'll see who's going and can grab an open spot.")
                ) { dismiss() }

                GameCard(
                    event: event, lineup: store.lineup(for: event),
                    status: event.roomLine, time: EventFormat.cardTime(event)
                )

                if let url = AppConfig.inviteURL {
                    if showsCode {
                        code(for: url)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    } else {
                        FieldBox("masUNO on the App Store") {
                            Text(verbatim: Self.display(url))
                        }
                    }

                    VStack(spacing: 10) {
                        ShareLink(
                            item: url,
                            subject: Text(event.title),
                            message: Text(EventDetailViewModel.inviteMessage(for: event, invites: store.invites))
                        ) {
                            Text("Share link")
                        }
                        .pill(.primary)

                        Button(showsCode ? "Hide QR code" : "Show QR code") {
                            withAnimation(.snappy) { showsCode.toggle() }
                        }
                        .pill(.quiet)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 22)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .sheetChrome(detents: [.height(580), .large])
    }

    private func code(for url: URL) -> some View {
        VStack(spacing: 10) {
            if let image = Self.qrCode(for: url) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .accessibilityLabel("QR code for masUNO on the App Store")
            }
            Text("Scan to get masUNO")
                .font(.rounded(.footnote))
                .foregroundStyle(Theme.muted)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .cardSurface(radius: Theme.Radius.field)
    }

    /// "apps.apple.com/app/id123", without the scheme.
    private static func display(_ url: URL) -> String {
        url.absoluteString.replacingOccurrences(of: "https://", with: "")
    }

    private static func qrCode(for url: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}
