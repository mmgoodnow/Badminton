import Kingfisher
import SwiftUI

struct ListItemStyle {
    var titleFont: Font
    var subtitleFont: Font
    var subtitleColor: Color
    var rowPosterSize: CGSize
    var rowPosterCornerRadius: CGFloat
    var cardPosterSize: CGSize
    var cardPosterCornerRadius: CGFloat
    var rowSpacing: CGFloat
    var subtitleSpacing: CGFloat

    static let standard = ListItemStyle(
        titleFont: .title3.weight(.semibold),
        subtitleFont: .subheadline,
        subtitleColor: .secondary,
        rowPosterSize: CGSize(width: 104, height: 156),
        rowPosterCornerRadius: 8,
        cardPosterSize: CGSize(width: 144, height: 216),
        cardPosterCornerRadius: 12,
        rowSpacing: 12,
        subtitleSpacing: 4
    )
}

private struct ListItemStyleKey: EnvironmentKey {
    static let defaultValue = ListItemStyle.standard
}

extension EnvironmentValues {
    var listItemStyle: ListItemStyle {
        get { self[ListItemStyleKey.self] }
        set { self[ListItemStyleKey.self] = newValue }
    }
}

extension View {
    func listItemStyle(_ style: ListItemStyle) -> some View {
        environment(\.listItemStyle, style)
    }
}

struct ListPoster: View {
    let url: URL?
    let size: CGSize?
    let cornerRadius: CGFloat?
    let showDogEar: Bool
    let dogEarColor: Color
    let dogEarSize: CGFloat

    @Environment(\.listItemStyle) private var style

    init(
        url: URL?,
        size: CGSize? = nil,
        cornerRadius: CGFloat? = nil,
        showDogEar: Bool = false,
        dogEarColor: Color = .yellow,
        dogEarSize: CGFloat = 26
    ) {
        self.url = url
        self.size = size
        self.cornerRadius = cornerRadius
        self.showDogEar = showDogEar
        self.dogEarColor = dogEarColor
        self.dogEarSize = dogEarSize
    }

    var body: some View {
        let resolvedSize = size ?? style.rowPosterSize
        let resolvedCornerRadius = cornerRadius ?? style.rowPosterCornerRadius

        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: resolvedCornerRadius)
                .fill(Color.gray.opacity(0.2))
            if let url {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
            }
            if showDogEar {
                PosterDogEar(size: dogEarSize, color: dogEarColor)
            }
        }
        .frame(width: resolvedSize.width, height: resolvedSize.height)
        .clipShape(RoundedRectangle(cornerRadius: resolvedCornerRadius))
    }
}

struct ListItemTextStack: View {
    let title: String
    let subtitleLines: [String]
    let titleFont: Font?
    let subtitleFont: Font?
    let subtitleColor: Color?
    let titleLineLimit: Int?
    let subtitleLineLimit: Int?

    @Environment(\.listItemStyle) private var style

    var body: some View {
        let resolvedTitleFont = titleFont ?? style.titleFont
        let resolvedSubtitleFont = subtitleFont ?? style.subtitleFont
        let resolvedSubtitleColor = subtitleColor ?? style.subtitleColor

        VStack(alignment: .leading, spacing: style.subtitleSpacing) {
            Text(title)
                .font(resolvedTitleFont)
                .lineLimit(titleLineLimit)
            ForEach(subtitleLines.filter { !$0.isEmpty }, id: \.self) { line in
                Text(line)
                    .font(resolvedSubtitleFont)
                    .foregroundStyle(resolvedSubtitleColor)
                    .lineLimit(subtitleLineLimit)
            }
        }
    }
}

struct ListItemRow: View {
    let title: String
    let subtitleLines: [String]
    let imageURL: URL?
    let showChevron: Bool
    let showDogEar: Bool
    let dogEarColor: Color
    let dogEarSize: CGFloat
    let posterSize: CGSize?
    let posterCornerRadius: CGFloat?
    let titleFont: Font?
    let subtitleFont: Font?
    let subtitleColor: Color?
    let titleLineLimit: Int?
    let subtitleLineLimit: Int?

    @Environment(\.listItemStyle) private var style

    init(
        title: String,
        subtitle: String = "",
        imageURL: URL?,
        showChevron: Bool = true,
        showDogEar: Bool = false,
        dogEarColor: Color = .yellow,
        dogEarSize: CGFloat = 26,
        posterSize: CGSize? = nil,
        posterCornerRadius: CGFloat? = nil,
        titleFont: Font? = nil,
        subtitleFont: Font? = nil,
        subtitleColor: Color? = nil,
        titleLineLimit: Int? = nil,
        subtitleLineLimit: Int? = nil
    ) {
        self.title = title
        self.subtitleLines = subtitle.split(whereSeparator: \.isNewline).map { String($0) }
        self.imageURL = imageURL
        self.showChevron = showChevron
        self.showDogEar = showDogEar
        self.dogEarColor = dogEarColor
        self.dogEarSize = dogEarSize
        self.posterSize = posterSize
        self.posterCornerRadius = posterCornerRadius
        self.titleFont = titleFont
        self.subtitleFont = subtitleFont
        self.subtitleColor = subtitleColor
        self.titleLineLimit = titleLineLimit
        self.subtitleLineLimit = subtitleLineLimit
    }

    init(
        title: String,
        subtitleLines: [String],
        imageURL: URL?,
        showChevron: Bool = true,
        showDogEar: Bool = false,
        dogEarColor: Color = .yellow,
        dogEarSize: CGFloat = 26,
        posterSize: CGSize? = nil,
        posterCornerRadius: CGFloat? = nil,
        titleFont: Font? = nil,
        subtitleFont: Font? = nil,
        subtitleColor: Color? = nil,
        titleLineLimit: Int? = nil,
        subtitleLineLimit: Int? = nil
    ) {
        self.title = title
        self.subtitleLines = subtitleLines
        self.imageURL = imageURL
        self.showChevron = showChevron
        self.showDogEar = showDogEar
        self.dogEarColor = dogEarColor
        self.dogEarSize = dogEarSize
        self.posterSize = posterSize
        self.posterCornerRadius = posterCornerRadius
        self.titleFont = titleFont
        self.subtitleFont = subtitleFont
        self.subtitleColor = subtitleColor
        self.titleLineLimit = titleLineLimit
        self.subtitleLineLimit = subtitleLineLimit
    }

    var body: some View {
        HStack(alignment: .top, spacing: style.rowSpacing) {
            ListPoster(
                url: imageURL,
                size: posterSize,
                cornerRadius: posterCornerRadius,
                showDogEar: showDogEar,
                dogEarColor: dogEarColor,
                dogEarSize: dogEarSize
            )
            ListItemTextStack(
                title: title,
                subtitleLines: subtitleLines,
                titleFont: titleFont,
                subtitleFont: subtitleFont,
                subtitleColor: subtitleColor,
                titleLineLimit: titleLineLimit,
                subtitleLineLimit: subtitleLineLimit
            )
            Spacer(minLength: 0)
            if showChevron {
                VStack {
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct ListPosterCard: View {
    let title: String
    let subtitle: String
    let imageURL: URL?
    let showDogEar: Bool
    let dogEarColor: Color
    let dogEarSize: CGFloat
    let posterSize: CGSize?
    let posterCornerRadius: CGFloat?
    let titleFont: Font?
    let subtitleFont: Font?
    let subtitleColor: Color?

    @Environment(\.listItemStyle) private var style

    init(
        title: String,
        subtitle: String = "",
        imageURL: URL?,
        showDogEar: Bool = false,
        dogEarColor: Color = .yellow,
        dogEarSize: CGFloat = 26,
        posterSize: CGSize? = nil,
        posterCornerRadius: CGFloat? = nil,
        titleFont: Font? = nil,
        subtitleFont: Font? = nil,
        subtitleColor: Color? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.imageURL = imageURL
        self.showDogEar = showDogEar
        self.dogEarColor = dogEarColor
        self.dogEarSize = dogEarSize
        self.posterSize = posterSize
        self.posterCornerRadius = posterCornerRadius
        self.titleFont = titleFont
        self.subtitleFont = subtitleFont
        self.subtitleColor = subtitleColor
    }

    var body: some View {
        let resolvedTitleFont = titleFont ?? style.titleFont
        let resolvedSubtitleFont = subtitleFont ?? style.subtitleFont
        let resolvedSubtitleColor = subtitleColor ?? style.subtitleColor
        let resolvedPosterSize = posterSize ?? style.cardPosterSize

        VStack(alignment: .leading, spacing: 8) {
            ListPoster(
                url: imageURL,
                size: resolvedPosterSize,
                cornerRadius: posterCornerRadius ?? style.cardPosterCornerRadius,
                showDogEar: showDogEar,
                dogEarColor: dogEarColor,
                dogEarSize: dogEarSize
            )
            Text(title)
                .font(resolvedTitleFont)
                .lineLimit(2)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(resolvedSubtitleFont)
                    .foregroundStyle(resolvedSubtitleColor)
            }
        }
        .frame(width: resolvedPosterSize.width, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct ListPosterGridItem: View {
    let title: String
    let subtitleLines: [String]
    let imageURL: URL?
    let showDogEar: Bool
    let dogEarColor: Color
    let dogEarSize: CGFloat
    let posterSize: CGSize?
    let posterCornerRadius: CGFloat?
    let titleFont: Font?
    let subtitleFont: Font?
    let subtitleColor: Color?
    let titleLineLimit: Int?
    let subtitleLineLimit: Int?

    @Environment(\.listItemStyle) private var style

    init(
        title: String,
        subtitle: String = "",
        imageURL: URL?,
        showDogEar: Bool = false,
        dogEarColor: Color = .yellow,
        dogEarSize: CGFloat = 26,
        posterSize: CGSize? = nil,
        posterCornerRadius: CGFloat? = nil,
        titleFont: Font? = nil,
        subtitleFont: Font? = nil,
        subtitleColor: Color? = nil,
        titleLineLimit: Int? = 2,
        subtitleLineLimit: Int? = 2
    ) {
        self.title = title
        self.subtitleLines = subtitle.split(whereSeparator: \.isNewline).map { String($0) }
        self.imageURL = imageURL
        self.showDogEar = showDogEar
        self.dogEarColor = dogEarColor
        self.dogEarSize = dogEarSize
        self.posterSize = posterSize
        self.posterCornerRadius = posterCornerRadius
        self.titleFont = titleFont
        self.subtitleFont = subtitleFont
        self.subtitleColor = subtitleColor
        self.titleLineLimit = titleLineLimit
        self.subtitleLineLimit = subtitleLineLimit
    }

    init(
        title: String,
        subtitleLines: [String],
        imageURL: URL?,
        showDogEar: Bool = false,
        dogEarColor: Color = .yellow,
        dogEarSize: CGFloat = 26,
        posterSize: CGSize? = nil,
        posterCornerRadius: CGFloat? = nil,
        titleFont: Font? = nil,
        subtitleFont: Font? = nil,
        subtitleColor: Color? = nil,
        titleLineLimit: Int? = 2,
        subtitleLineLimit: Int? = 2
    ) {
        self.title = title
        self.subtitleLines = subtitleLines
        self.imageURL = imageURL
        self.showDogEar = showDogEar
        self.dogEarColor = dogEarColor
        self.dogEarSize = dogEarSize
        self.posterSize = posterSize
        self.posterCornerRadius = posterCornerRadius
        self.titleFont = titleFont
        self.subtitleFont = subtitleFont
        self.subtitleColor = subtitleColor
        self.titleLineLimit = titleLineLimit
        self.subtitleLineLimit = subtitleLineLimit
    }

    var body: some View {
        let resolvedPosterSize = posterSize ?? style.rowPosterSize
        let resolvedCornerRadius = posterCornerRadius ?? style.rowPosterCornerRadius

        VStack(alignment: .leading, spacing: 8) {
            ListPoster(
                url: imageURL,
                size: resolvedPosterSize,
                cornerRadius: resolvedCornerRadius,
                showDogEar: showDogEar,
                dogEarColor: dogEarColor,
                dogEarSize: dogEarSize
            )
            ListItemTextStack(
                title: title,
                subtitleLines: subtitleLines,
                titleFont: titleFont,
                subtitleFont: subtitleFont,
                subtitleColor: subtitleColor,
                titleLineLimit: titleLineLimit,
                subtitleLineLimit: subtitleLineLimit
            )
        }
        .frame(width: resolvedPosterSize.width, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct PosterDogEar: View {
    let size: CGFloat
    let color: Color

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: size, y: 0))
            path.addLine(to: CGPoint(x: size, y: size))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.closeSubpath()
        }
        .fill(color)
        .shadow(color: Color.black.opacity(0.28), radius: 3, x: 0, y: 2)
        .frame(width: size, height: size)
    }
}
