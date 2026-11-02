import AppKit
import SwiftUI

/// The composer's images above the input: thumbnails `Size.attachmentThumb` tall, each with a remove ×; one being
/// prepared shows a spinner, one that failed its error ("Too large", "Not an image"). `note` goes under the row.
public struct AttachmentTray: View {
    public struct Item: Identifiable {
        public let id: UUID
        /// Nil while the image is being prepared, or when it failed.
        public let image: NSImage?
        public let error: String?

        public init(id: UUID, image: NSImage?, error: String?) {
            self.id = id
            self.image = image
            self.error = error
        }
    }

    let items: [Item]
    let note: String?
    let onRemove: @MainActor (UUID) -> Void

    public init(items: [Item], note: String? = nil, onRemove: @escaping @MainActor (UUID) -> Void) {
        self.items = items
        self.note = note
        self.onRemove = onRemove
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.s) {
                ForEach(items) { item in
                    thumbnail(item)
                        .overlay(alignment: .topTrailing) {
                            EndfieldButton("Remove", symbol: Symbol.close, kind: .quiet, iconOnly: true) { onRemove(item.id) }
                                .background(Ink.surface.raised)
                        }
                }
            }
            if let note {
                Text(note).typeRole(.caption).foregroundStyle(Ink.text.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func thumbnail(_ item: Item) -> some View {
        if let image = item.image {
            let size = image.size
            // Fit the height; a very wide image is cut at two squares.
            let width = size.height > 0 ? min(Size.attachmentThumb * size.width / size.height, Size.attachmentThumb * 2) : Size.attachmentThumb
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                .frame(width: max(width, Size.attachmentThumb / 2), height: Size.attachmentThumb).clipped()
                .overlay(Rectangle().strokeBorder(Ink.line.rule, lineWidth: Stroke.hairline))
        } else {
            ZStack {
                if let error = item.error {
                    Text(error).typeRole(.caption).foregroundStyle(Ink.text.error).multilineTextAlignment(.center).padding(Space.xs)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: Size.attachmentThumb, height: Size.attachmentThumb)
            .background(Ink.surface.sunken)
            .overlay(Rectangle().strokeBorder(item.error == nil ? Ink.line.rule : Ink.text.error, lineWidth: Stroke.hairline))
        }
    }
}

/// A message's images: one fits within `Size.chatImage`; two to four are a two-column grid of squares. A click calls
/// `onOpen` with the cell's id. A cell that can't load shows its caption (the file name).
public struct ChatImageGrid: View {
    public struct Cell: Identifiable {
        public let id: String
        public let image: NSImage?
        /// The image's pixel size when known before it loads, so the layout doesn't jump.
        public let pixelSize: CGSize?
        /// Set when it can't be loaded.
        public let caption: String?

        public init(id: String, image: NSImage?, pixelSize: CGSize? = nil, caption: String? = nil) {
            self.id = id
            self.image = image
            self.pixelSize = pixelSize
            self.caption = caption
        }
    }

    let cells: [Cell]
    let onOpen: @MainActor (String) -> Void

    public init(cells: [Cell], onOpen: @escaping @MainActor (String) -> Void) {
        self.cells = cells
        self.onOpen = onOpen
    }

    public var body: some View {
        if cells.count == 1, let cell = cells.first {
            let size = Self.fitted(cell.image?.size ?? cell.pixelSize)
            box(cell, width: size.width, height: size.height)
        } else {
            let side = (Size.chatImage.width - Space.xs) / 2
            Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) {
                ForEach(Array(stride(from: 0, to: cells.count, by: 2)), id: \.self) { i in
                    GridRow {
                        ForEach(cells[i..<min(i + 2, cells.count)]) { box($0, width: side, height: side) }
                    }
                }
            }
        }
    }

    /// Within Size.chatImage, never enlarged; the whole box while the size isn't known.
    static func fitted(_ size: CGSize?) -> CGSize {
        guard let size, size.width > 0, size.height > 0 else { return CGSize(width: Size.chatImage.width, height: Size.chatImage.height) }
        let scale = min(Size.chatImage.width / size.width, Size.chatImage.height / size.height, 1)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    @ViewBuilder private func box(_ cell: Cell, width: CGFloat, height: CGFloat) -> some View {
        if let image = cell.image {
            Button { onOpen(cell.id) } label: {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height).clipped()
                    .overlay(Rectangle().strokeBorder(Ink.line.rule, lineWidth: Stroke.hairline))
            }
            .buttonStyle(.plain)
            .help("Open full size")
            .accessibilityLabel("Image")
        } else if let caption = cell.caption {
            Text(caption).typeRole(.caption).foregroundStyle(Ink.text.secondary).lineLimit(2).truncationMode(.middle)
                .frame(maxWidth: Size.chatImage.width, alignment: .leading)
        } else {
            ProgressView().controlSize(.small)
                .frame(width: width, height: height)
                .background(Ink.surface.sunken)
        }
    }
}
