import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A single history row. Click to paste the content into the frontmost app (or
/// open a link); drag it into another app; hover for pin/preview/delete. Images
/// show a thumbnail, files show their icon.
struct ItemRowView: View {
    @Environment(ClipboardViewModel.self) private var viewModel
    let item: ClipboardItem

    @State private var isHovering = false
    @State private var justCopied = false
    @State private var showImagePreview = false
    @State private var showDetail = false

    private var isLink: Bool { viewModel.linkURL(for: item) != nil }

    /// Text-like kinds get the smart-detail popover (links, JSON, color, QR…).
    private var isTextual: Bool {
        switch item.kind {
        case .text, .code, .url, .note: true
        case .image, .file: false
        }
    }

    private var detectedColor: NSColor? {
        isTextual ? SmartContentDetector.detectColor(item.content) : nil
    }

    var body: some View {
        Button(action: activate) {
            HStack(spacing: 10) {
                leadingIcon

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayText)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .font(.callout)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 4)

                if item.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }

                if justCopied {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if isHovering {
                    rowActions
                } else if isLink {
                    Image(systemName: "arrow.up.forward.square")
                        .foregroundStyle(.tertiary)
                        .help("Opens in browser")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                isHovering ? Color.primary.opacity(0.06) : .clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .onDrag { dragProvider() }
        .contextMenu { contextMenu }
        .popover(isPresented: $showImagePreview, arrowEdge: .trailing) {
            if let image = item.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 420, maxHeight: 420)
                    .padding(8)
            }
        }
        .popover(isPresented: $showDetail, arrowEdge: .trailing) {
            SmartDetailView(item: item)
                .environment(viewModel)
        }
    }

    // MARK: - Leading icon / thumbnail

    @ViewBuilder
    private var leadingIcon: some View {
        switch item.kind {
        case .image:
            if let image = item.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator))
            } else {
                symbolIcon
            }
        case .file:
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.content))
                .resizable()
                .frame(width: 24, height: 24)
        default:
            if let color = detectedColor {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: color))
                    .frame(width: 24, height: 24)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator))
            } else {
                symbolIcon
            }
        }
    }

    private var symbolIcon: some View {
        Image(systemName: item.kind.symbolName)
            .font(.body)
            .foregroundStyle(.tint)
            .frame(width: 24)
    }

    private var subtitle: String {
        let age = item.createdAt.formatted(.relative(presentation: .named))
        switch item.kind {
        case .image, .file: return "\(item.kind.label) · \(age)"
        default: return age
        }
    }

    // MARK: - Hover actions

    private var rowActions: some View {
        HStack(spacing: 6) {
            if item.kind == .image {
                Button { showImagePreview = true } label: {
                    Image(systemName: "eye")
                }
                .help("Preview")
            }

            if isTextual {
                Button { showDetail = true } label: {
                    Image(systemName: "sparkles")
                }
                .help("Smart actions")
            }

            Button {
                viewModel.togglePin(item)
            } label: {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
            }
            .help(item.isPinned ? "Unpin" : "Pin")

            Button {
                viewModel.delete(item)
            } label: {
                Image(systemName: "trash")
            }
            .help("Delete")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenu: some View {
        switch item.kind {
        case .file:
            Button("Paste") { viewModel.activate(item) }
            Button("Open") { viewModel.openFile(item) }
            Button("Reveal in Finder") { viewModel.revealInFinder(item) }
        case .image:
            Button("Paste") { viewModel.activate(item) }
            Button("Preview") { showImagePreview = true }
        default:
            if isLink {
                Button("Open Link") { viewModel.activate(item) }
            } else {
                Button("Paste") { viewModel.activate(item) }
            }
        }
        if isTextual {
            Button("Smart Actions…") { showDetail = true }
        }
        Button("Copy") { copyOnly() }
        Divider()
        Button(item.isPinned ? "Unpin" : "Pin") { viewModel.togglePin(item) }
        Button(item.isFavorite ? "Remove Favorite" : "Favorite") { viewModel.toggleFavorite(item) }
        Button("Delete", role: .destructive) { viewModel.delete(item) }
    }

    // MARK: - Drag & drop

    private func dragProvider() -> NSItemProvider {
        switch item.kind {
        case .image:
            if let image = item.image {
                return NSItemProvider(object: image)
            }
        case .file:
            if let url = item.fileURL, let provider = NSItemProvider(contentsOf: url) {
                return provider
            }
        default:
            return NSItemProvider(object: item.content as NSString)
        }
        return NSItemProvider(object: item.content as NSString)
    }

    // MARK: - Actions

    private func activate() {
        viewModel.activate(item)
    }

    private func copyOnly() {
        viewModel.copyToClipboard(item)
        withAnimation { justCopied = true }
        Task {
            try? await Task.sleep(for: .seconds(1))
            withAnimation { justCopied = false }
        }
    }
}
