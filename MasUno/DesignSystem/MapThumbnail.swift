import MapKit
import SwiftUI

/// Small static map image with a pin dot (location cards). A snapshot rather than a live
/// `Map`, so there's no "Legal" label or gesture handling at thumbnail size.
struct MapThumbnail: View {
    var coordinate: CLLocationCoordinate2D
    var size: CGFloat = 48

    @State private var image: UIImage?
    @State private var renderedRequest: MapSnapshotRequest?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.tile)
            .fill(Theme.accentSoft)
            .overlay {
                if let image, renderedRequest == request {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .overlay {
                Circle()
                    .fill(Theme.you)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            }
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: Theme.Radius.tile))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.tile).strokeBorder(Theme.hairline))
            .accessibilityHidden(true)
            .task(id: request) { await render(request) }
    }

    private var request: MapSnapshotRequest {
        MapSnapshotRequest(latitude: coordinate.latitude, longitude: coordinate.longitude, size: Double(size), scale: Double(displayScale))
    }

    private func render(_ request: MapSnapshotRequest) async {
        do {
            let rendered = try await MapSnapshotCache.shared.image(for: request)
            try Task.checkCancellation()
            guard request == self.request else { return }
            image = rendered
            renderedRequest = request
        } catch {
            // The accent placeholder remains useful while offline or after cancellation.
        }
    }
}
