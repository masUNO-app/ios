import SwiftUI

/// Court and field line art (SPEC §7.7.3), built as shapes rather than images. Each drawing is
/// in the Figma "Court lines" frame's space, 402 pt wide, and is scaled by `scale` and centered
/// in the width it's given, so the same art serves the detail header and the chat band.
struct CourtArt: View {
    var kind: CourtKind
    var scale: CGFloat = 1

    /// Width of the Figma frame the paths are drawn in.
    static let designWidth: CGFloat = 402

    var body: some View {
        ZStack {
            ForEach(Array(Self.layers(for: kind).enumerated()), id: \.offset) { _, layer in
                let shape = CourtPath(path: layer.path, scale: scale, spansWidth: layer.spansWidth)
                switch layer.style {
                case .fill(let color):
                    shape.fill(color)
                case .stroke(let color, let width, let dash):
                    shape.stroke(color, style: StrokeStyle(lineWidth: width * scale, lineJoin: .round, dash: dash.map { $0 * scale }))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A path drawn in the 402 pt design space, scaled and centered into the view.
private nonisolated struct CourtPath: Shape {
    var path: Path
    var scale: CGFloat
    /// Stretches edge to edge instead of staying with the court (the soccer pitch's stripes).
    var spansWidth = false

    func path(in rect: CGRect) -> Path {
        if spansWidth {
            let bounds = path.boundingRect
            return Path(CGRect(x: rect.minX, y: rect.minY + bounds.minY * scale, width: rect.width, height: bounds.height * scale))
        }
        let inset = (rect.width - CourtArt.designWidth * scale) / 2
        return path
            .applying(CGAffineTransform(scaleX: scale, y: scale))
            .offsetBy(dx: rect.minX + inset, dy: rect.minY)
    }
}

private nonisolated struct CourtLayer {
    enum Style {
        case fill(Color)
        case stroke(Color, width: CGFloat = 3, dash: [CGFloat] = [])
    }

    var path: Path
    var style: Style
    var spansWidth = false
}

private extension CourtArt {
    static let ink = Color(hex: 0x1F2638)

    static func layers(for kind: CourtKind) -> [CourtLayer] {
        switch kind {
        case .basketball: basketball
        case .tennis: tennis
        case .soccer: soccer
        case .volleyball: volleyball
        case .padel: padel
        case .generic: generic
        }
    }

    static func rect(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> CGRect {
        CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
    }

    static func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: x1, y: y1))
            path.addLine(to: CGPoint(x: x2, y: y2))
        }
    }

    static func circle(_ x: CGFloat, _ y: CGFloat, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
    }

    /// Half court: baseline at the top, key, free-throw circle, three-point arc and hoop.
    static let basketball: [CourtLayer] = {
        let lines = Path { path in
            path.addRoundedRect(in: rect(18.6, 74.1, 383.5, 403.6), cornerSize: CGSize(width: 4, height: 4))
            path.addRect(rect(128.9, 74.1, 273.2, 228.5))
            path.addPath(circle(201, 228.5, radius: 57.7))
            path.addPath(circle(201, 100.9, radius: 11.3))
            // Three-point line: straight in the corners, then the arc.
            path.move(to: CGPoint(x: 59.8, y: 74.1))
            path.addLine(to: CGPoint(x: 59.8, y: 154.4))
            path.addCurve(to: CGPoint(x: 110.1, y: 236.7), control1: CGPoint(x: 66.6, y: 186.8), control2: CGPoint(x: 84.4, y: 215.8))
            path.addCurve(to: CGPoint(x: 201, y: 268.9), control1: CGPoint(x: 135.8, y: 257.5), control2: CGPoint(x: 167.9, y: 268.9))
            path.addCurve(to: CGPoint(x: 291.9, y: 236.7), control1: CGPoint(x: 234.1, y: 268.9), control2: CGPoint(x: 266.2, y: 257.5))
            path.addCurve(to: CGPoint(x: 342.2, y: 154.4), control1: CGPoint(x: 317.7, y: 215.8), control2: CGPoint(x: 335.4, y: 186.8))
            path.addLine(to: CGPoint(x: 342.2, y: 74.1))
        }
        return [CourtLayer(path: lines, style: .stroke(Color(hex: 0xFFE3CC)))]
    }()

    /// One side of the net: doubles and singles sidelines, service line and center line.
    static let tennis: [CourtLayer] = {
        let lines = Path { path in
            path.addRect(rect(41.2, 78.2, 360.8, 407.7))
            path.addPath(line(86.6, 78.2, 86.6, 407.7))
            path.addPath(line(315.4, 78.2, 315.4, 407.7))
            path.addPath(line(86.6, 238.9, 315.4, 238.9))
            path.addPath(line(201, 78.2, 201, 238.9))
        }
        return [
            CourtLayer(path: lines, style: .stroke(.white)),
            CourtLayer(path: line(22.7, 78.2, 379.3, 78.2), style: .stroke(ink.opacity(0.45), width: 5, dash: [3, 3])),
        ]
    }()

    /// Mown stripes, the goal and both boxes at the top, the halfway line and center circle below.
    static let soccer: [CourtLayer] = {
        let stripe = Color(hex: 0x35A565)
        let stripes = [(74.1, 125.6), (177.1, 228.6), (280.0, 331.5)].map { top, bottom in
            CourtLayer(path: Path(rect(0, top, 402, bottom)), style: .fill(stripe), spansWidth: true)
        }
        let chalk = Color(hex: 0xE8FFF1)
        let lines = Path { path in
            path.addRect(rect(18.6, 74.1, 383.4, 403.6))
            path.addRect(rect(87.6, 74.1, 314.4, 195.6))
            path.addRect(rect(144.3, 74.1, 257.7, 121.5))
            path.addRect(rect(164.9, 61.8, 237.1, 74.1))
            path.addPath(line(18.6, 345.9, 383.4, 345.9))
            path.addPath(circle(201, 345.9, radius: 51.5))
            // Penalty arc.
            path.move(to: CGPoint(x: 154.6, y: 195.6))
            path.addCurve(to: CGPoint(x: 175.3, y: 211.9), control1: CGPoint(x: 160.2, y: 202.5), control2: CGPoint(x: 167.3, y: 208.1))
            path.addCurve(to: CGPoint(x: 201, y: 217.7), control1: CGPoint(x: 183.3, y: 215.7), control2: CGPoint(x: 192.1, y: 217.7))
            path.addCurve(to: CGPoint(x: 226.7, y: 211.9), control1: CGPoint(x: 209.9, y: 217.7), control2: CGPoint(x: 218.7, y: 215.7))
            path.addCurve(to: CGPoint(x: 247.4, y: 195.6), control1: CGPoint(x: 234.7, y: 208.1), control2: CGPoint(x: 241.8, y: 202.5))
        }
        return stripes + [
            CourtLayer(path: lines, style: .stroke(chalk)),
            CourtLayer(path: circle(201, 156.5, radius: 3.6), style: .fill(chalk)),
        ]
    }()

    /// One half under the net: the court, the attack line, and the net with its posts.
    static let volleyball: [CourtLayer] = {
        let court = Path(rect(30.9, 78.2, 371.1, 407.7))
        let posts = Path { path in
            path.addPath(circle(12.4, 78.2, radius: 5.2))
            path.addPath(circle(389.6, 78.2, radius: 5.2))
        }
        let lines = Path { path in
            path.addRect(rect(30.9, 78.2, 371.1, 407.7))
            path.addPath(line(30.9, 191.5, 371.1, 191.5))
        }
        return [
            CourtLayer(path: court, style: .fill(Color(hex: 0xB7ADF8))),
            CourtLayer(path: lines, style: .stroke(Color(hex: 0xF4F1FF))),
            CourtLayer(path: line(12.4, 78.2, 389.6, 78.2), style: .stroke(ink.opacity(0.5), width: 7, dash: [4, 4])),
            CourtLayer(path: posts, style: .fill(ink)),
        ]
    }()

    /// Glass-walled court: the walls, the service line and center line, and the net.
    static let padel: [CourtLayer] = {
        let court = Path(rect(22.7, 86.5, 379.3, 415.9))
        let service = Path { path in
            path.addPath(line(22.7, 275.9, 379.3, 275.9))
            path.addPath(line(201, 86.5, 201, 275.9))
        }
        let panels = Path { path in
            for x in [22.7, 379.3] {
                path.addPath(line(x, 86.5, x, 154.4))
                path.addPath(line(x, 205.9, x, 278))
            }
        }
        return [
            CourtLayer(path: court, style: .fill(Color(hex: 0x6CC8EE))),
            CourtLayer(path: service, style: .stroke(.white)),
            CourtLayer(path: court, style: .stroke(Color(hex: 0xE6F8FF), width: 7)),
            CourtLayer(path: panels, style: .stroke(ink.opacity(0.4))),
            CourtLayer(path: line(14.4, 86.5, 387.6, 86.5), style: .stroke(ink.opacity(0.45), width: 5, dash: [3, 3])),
        ]
    }()

    /// A sport without a drawing: a plain court with a center line.
    static let generic: [CourtLayer] = {
        let lines = Path { path in
            path.addRoundedRect(in: rect(18.6, 74.1, 383.4, 403.6), cornerSize: CGSize(width: 4, height: 4))
            path.addPath(line(18.6, 238.9, 383.4, 238.9))
            path.addPath(circle(201, 238.9, radius: 44))
        }
        return [CourtLayer(path: lines, style: .stroke(.white.opacity(0.6)))]
    }()
}

/// Where each spot stands on a court, in the Figma header's 402 × 410 space.
nonisolated enum CourtLayout {
    struct Slots: Equatable {
        var points: [CGPoint]
        /// Token diameter: smaller as the court fills up.
        var tokenSize: CGFloat
        /// First names fit under the tokens.
        var showsNames: Bool
        /// The spot you stand on when it's your game.
        var featured: Int
    }

    /// The Figma arrangements for each sport's usual number of players, and a grid for anything else.
    static func slots(for kind: CourtKind, count: Int) -> Slots {
        switch (kind, count) {
        case (.basketball, 5...6):
            let points = [(107, 166), (295, 187), (201, 267), (75, 284), (327, 296), (145, 357)]
            return Slots(points: Array(points.prefix(count)).map(point), tokenSize: 44, showsNames: true, featured: 2)
        case (_, 3...4):
            let points = [(111, 184), (295, 178), (126, 314), (287, 308)]
            return Slots(points: Array(points.prefix(count)).map(point), tokenSize: 44, showsNames: true, featured: 2)
        case (.soccer, 9...10):
            let points = [(62, 163), (155, 155), (252, 166), (344, 155), (105, 250), (201, 242), (299, 252), (78, 337), (201, 328), (322, 339)]
            return Slots(points: Array(points.prefix(count)).map(point), tokenSize: 44, showsNames: true, featured: 5)
        default:
            return grid(count)
        }
    }

    private static func point(_ pair: (Int, Int)) -> CGPoint {
        CGPoint(x: pair.0, y: pair.1)
    }

    /// Rows of up to four (six once it's crowded), every other column nudged down so it reads
    /// as people standing around rather than a table.
    private static func grid(_ count: Int) -> Slots {
        let columns = count <= 2 ? 2 : count <= 6 ? 3 : count <= 16 ? 4 : 6
        let rows = Int((Double(count) / Double(columns)).rounded(.up))
        let top: CGFloat = 159, bottom: CGFloat = 333
        let rowGap = rows > 1 ? (bottom - top) / CGFloat(rows - 1) : 0
        let tokenSize: CGFloat = rows <= 3 ? 44 : rows == 4 ? 38 : 32

        var points: [CGPoint] = []
        for row in 0..<rows {
            let inRow = min(columns, count - row * columns)
            let left: CGFloat = columns == 6 ? 42 : columns == 4 ? 54 : 84
            let span = CourtArt.designWidth - left * 2
            for column in 0..<inRow {
                // A short last row sits centered under the rows above.
                let x = inRow == 1 ? CourtArt.designWidth / 2 : left + span * CGFloat(column) / CGFloat(inRow - 1)
                let y = (rows == 1 ? (top + bottom) / 2 : top + rowGap * CGFloat(row)) + (column.isMultiple(of: 2) ? 4 : -4)
                points.append(CGPoint(x: x, y: y))
            }
        }
        return Slots(points: points, tokenSize: tokenSize, showsNames: rows <= 3, featured: min(columns / 2, count - 1))
    }
}

/// The full-bleed header on game details (SPEC §7.7.3): the court in the sport's color, with
/// everyone going standing on it and a "+1" on every open spot.
struct CourtHeader: View {
    var activity: Activity
    var lineup: Lineup
    /// Total spots to draw: the game's capacity.
    var capacity: Int
    var scale: CGFloat = 1
    var onTap: () -> Void = {}

    /// The Figma header: 402 × 410, with the court lines starting 48 pt down.
    static let designHeight: CGFloat = 410
    private static let artTop: CGFloat = 48

    var body: some View {
        let slots = CourtLayout.slots(for: activity.court, count: max(capacity, 1))
        let places = Self.places(lineup: lineup, slots: slots)

        GeometryReader { geo in
            let inset = (geo.size.width - CourtArt.designWidth * scale) / 2
            ZStack(alignment: .topLeading) {
                CourtArt(kind: activity.court, scale: scale)
                    .offset(y: Self.artTop * scale)

                ForEach(Array(places.enumerated()), id: \.offset) { index, place in
                    let point = slots.points[index]
                    token(place, slots: slots)
                        .position(x: inset + point.x * scale, y: point.y * scale + labelOffset(place, slots: slots))
                }
            }
            .animation(.spring(duration: 0.45, bounce: 0.3), value: places)
        }
        .frame(height: Self.designHeight * scale)
        .background(activity.color)
        .clipped()
        .contentShape(.rect)
        .onTapGesture(perform: onTap)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: lineup.accessibilityLabel))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows who's going")
    }

    private enum Place: Equatable {
        case person(PersonSummary)
        case you
        case unlisted
        case open
    }

    /// People in joining order, then open spots. When it's your game you take the featured spot.
    private static func places(lineup: Lineup, slots: CourtLayout.Slots) -> [Place] {
        var people: [Place] = lineup.people.map { $0.id == lineup.myID ? .you : .person($0) }
        people += Array(repeating: .unlisted, count: lineup.unlisted)
        var places = Array(people.prefix(slots.points.count))
        places += Array(repeating: .open, count: max(slots.points.count - places.count, 0))
        if lineup.isHostedByMe, let mine = places.firstIndex(of: .you), slots.featured < places.count {
            places.swapAt(mine, slots.featured)
        }
        return places
    }

    @ViewBuilder
    private func token(_ place: Place, slots: CourtLayout.Slots) -> some View {
        let size = slots.tokenSize * scale
        switch place {
        case .person(let person):
            VStack(spacing: 3) {
                PersonAvatar(person: person, size: size)
                if slots.showsNames {
                    Text(verbatim: person.firstName)
                        .font(.rounded(size: 11 * scale, .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .frame(width: 64 * scale)
                }
            }
            .transition(.scale.combined(with: .opacity))
        case .you:
            YouToken(size: size)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
        case .unlisted:
            PersonToken(initials: "", color: .white.opacity(0.6), size: size)
        case .open:
            OpenSpotToken(size: size, fill: .white.opacity(0.38))
                .transition(.opacity)
        }
    }

    /// A token with a name under it is centered on the pair, so shift it down to keep the circle on its spot.
    private func labelOffset(_ place: Place, slots: CourtLayout.Slots) -> CGFloat {
        if case .person = place, slots.showsNames { return 9 * scale }
        return 0
    }
}
