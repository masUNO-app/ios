import MapKit
import SwiftUI

/// Small static map image with a pin dot (location cards). A snapshot rather than a live
/// `Map`, so there's no "Legal" label or gesture handling at thumbnail size.
struct MapThumbnail: View {
    var coordinate: CLLocationCoordinate2D
    var size: CGFloat = 48

    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.tile)
            .fill(Theme.accentSoft)
            .overlay {
                if let image {
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
            .task(id: "\(coordinate.latitude),\(coordinate.longitude)") { await render() }
    }

    private func render() async {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 400, longitudinalMeters: 400)
        options.size = CGSize(width: size, height: size)
        options.scale = displayScale
        options.pointOfInterestFilter = .excludingAll
        // The app is light-only; snapshots otherwise follow the system appearance.
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        image = try? await MKMapSnapshotter(options: options).start().image
    }
}
