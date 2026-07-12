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
    @State private var showReveal = false
    @State private var revealedText: String?
    @State private var showOCR = false
    @State private var ocrText = ""
    @State private var ocrRunning = false

    private var isLink: Bool { viewModel.linkURL(for: item) != nil }

    /// Text-like kinds get the smart-detail popover (links, JSON, color, QR…).
    /// Sensitive items are excluded — their content is encrypted ciphertext.
    private var isTextual: Bool {
        guard !item.isSensitive else { return false }
        switch item.kind {
        case .text, .code, .url, .note: return true
        case .image, .file: return false
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
                    Text(item.isSensitive ? "Sensitive content" : item.displayText)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .font(.callout)
                        .foregroundStyle(item.isSensitive ? .secondary : .primary)
                        .italic(item.isSensitive)
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
        .popover(isPresented: $showOCR, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Extracted Text", systemImage: "text.viewfinder")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(ocrText.isEmpty ? "No text found." : ocrText)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
                if !ocrText.isEmpty {
                    HStack {
                        Button("Copy") { viewModel.copyString(ocrText); showOCR = false }
                        Button("Add to History") { viewModel.saveText(ocrText); showOCR = false }
                    }
                    .controlSize(.small)
                }
            }
            .padding(12)
            .frame(width: 280)
        }
        .popover(isPresented: $showReveal, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Revealed", systemImage: "lock.open")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(revealedText ?? "")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                Button("Copy") {
                    viewModel.copyToClipboard(item)
                    showReveal = false
                }
                .controlSize(.small)
            }
            .padding(12)
            .frame(minWidth: 220, maxWidth: 300)
        }
    }

    // MARK: - Leading icon / thumbnail

    @ViewBuilder
    private var leadingIcon: some View {
        if item.isSensitive {
            Image(systemName: "lock.fill")
                .font(.body)
                .foregroundStyle(.orange)
                .frame(width: 24)
        } else {
            kindIcon
        }
    }

    @ViewBuilder
    private var kindIcon: some View {
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
            if item.isSensitive {
                Button { reveal() } label: {
                    Image(systemName: "eye")
                }
                .help("Reveal (requires authentication)")
            }

            if item.kind == .image {
                Button { showImagePreview = true } label: {
                    Image(systemName: "eye")
                }
                .help("Preview")

                Button { runOCR() } label: {
                    Image(systemName: ocrRunning ? "hourglass" : "text.viewfinder")
                }
                .help("Extract text (OCR)")
                .disabled(ocrRunning)
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
        if item.isSensitive {
            Button("Reveal…") { reveal() }
            Button("Paste") { viewModel.activate(item) }
        } else {
            switch item.kind {
            case .file:
                Button("Paste") { viewModel.activate(item) }
                Button("Open") { viewModel.openFile(item) }
                Button("Reveal in Finder") { viewModel.revealInFinder(item) }
            case .image:
                Button("Paste") { viewModel.activate(item) }
                Button("Preview") { showImagePreview = true }
                Button("Extract Text (OCR)") { runOCR() }
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
        }
        Divider()
        Button(item.isPinned ? "Unpin" : "Pin") { viewModel.togglePin(item) }
        Button(item.isFavorite ? "Remove Favorite" : "Favorite") { viewModel.toggleFavorite(item) }
        Button("Delete", role: .destructive) { viewModel.delete(item) }
    }

    // MARK: - Drag & drop

    private func dragProvider() -> NSItemProvider {
        // Never expose a secret's ciphertext (or plaintext) via drag.
        if item.isSensitive {
            return NSItemProvider(object: "Sensitive content" as NSString)
        }
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

    /// Runs on-device OCR on an image item and shows the result.
    private func runOCR() {
        guard let data = item.imageData, !ocrRunning else { return }
        ocrRunning = true
        Task {
            let text = await AIService.recognizeText(in: data)
            ocrText = text
            ocrRunning = false
            showOCR = true
        }
    }

    /// Authenticates, then shows the decrypted secret in a popover.
    private func reveal() {
        Task {
            if let plaintext = await viewModel.revealPlaintext(of: item) {
                revealedText = plaintext
                showReveal = true
            }
        }
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
