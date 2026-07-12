import AppKit
import SwiftUI
import Translation

/// The "smart" detail popover for a text item: shows the full content plus
/// contextual actions based on what was detected (link, email, color, JSON) and
/// a QR code for the content.
struct SmartDetailView: View {
    @Environment(ClipboardViewModel.self) private var viewModel
    let item: ClipboardItem

    @State private var shortURL: String?
    @State private var isShortening = false
    @State private var jsonResult: String?
    @State private var flash: String?
    @State private var showQR = false
    @State private var summary: String?
    @State private var showTranslation = false

    private var content: String { item.content }
    private var url: URL? { SmartContentDetector.detectURL(content) }
    private var email: String? { SmartContentDetector.detectEmail(content) }
    private var color: NSColor? { SmartContentDetector.detectColor(content) }
    private var isJSONish: Bool { SmartContentDetector.looksLikeJSON(content) }
    private var language: String? { AIService.dominantLanguage(of: content) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            contentPreview

            if let url { linkSection(url) }
            if let email { emailSection(email) }
            if let color { colorSection(color) }
            if isJSONish { jsonSection }
            aiSection
            qrSection

            if let flash {
                Text(flash)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(14)
        .frame(width: 300)
        .translation(isPresented: $showTranslation, text: content)
    }

    @ViewBuilder
    private var aiSection: some View {
        section("AI") {
            if let language {
                HStack {
                    Text("Language").foregroundStyle(.secondary)
                    Spacer()
                    Text(language)
                }
                .font(.caption)
            }
            HStack(spacing: 6) {
                actionButton("Summarize", "text.append") {
                    summary = AIService.summarize(content)
                }
                actionButton("Translate", "character.bubble") {
                    showTranslation = true
                }
            }
            if let summary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Sections

    private var contentPreview: some View {
        ScrollView {
            Text(content)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 110)
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private func linkSection(_ url: URL) -> some View {
        section("Link") {
            HStack(spacing: 6) {
                actionButton("Open", "safari") { viewModel.open(url) }
                actionButton("Copy", "doc.on.doc") { copy(url.absoluteString) }
                actionButton(isShortening ? "…" : "Shorten", "link.badge.plus") {
                    Task { await shorten(url) }
                }
                .disabled(isShortening)
            }
            if let shortURL {
                HStack(spacing: 6) {
                    Text(shortURL).font(.caption).foregroundStyle(.tint).lineLimit(1)
                    Spacer()
                    Button("Copy") { copy(shortURL) }.font(.caption).buttonStyle(.borderless)
                }
            }
        }
    }

    private func emailSection(_ email: String) -> some View {
        section("Email") {
            HStack(spacing: 6) {
                actionButton("Compose", "envelope") { viewModel.composeEmail(to: email) }
                actionButton("Copy Address", "doc.on.doc") { copy(email) }
            }
        }
    }

    private func colorSection(_ color: NSColor) -> some View {
        section("Color") {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: color))
                    .frame(width: 40, height: 40)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                VStack(alignment: .leading, spacing: 4) {
                    Button(SmartContentDetector.hexString(color)) {
                        copy(SmartContentDetector.hexString(color))
                    }
                    Button(SmartContentDetector.rgbString(color)) {
                        copy(SmartContentDetector.rgbString(color))
                    }
                }
                .font(.caption.monospaced())
                .buttonStyle(.borderless)
            }
        }
    }

    private var jsonSection: some View {
        section("JSON") {
            HStack(spacing: 6) {
                actionButton("Pretty Print", "text.alignleft") {
                    if let pretty = SmartContentDetector.prettyJSON(content) {
                        copy(pretty, message: "Pretty JSON copied")
                    } else {
                        jsonResult = "✗ Invalid JSON"
                    }
                }
                actionButton("Validate", "checkmark.seal") {
                    jsonResult = SmartContentDetector.prettyJSON(content) != nil
                        ? "✓ Valid JSON" : "✗ Invalid JSON"
                }
            }
            if let jsonResult {
                Text(jsonResult).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var qrSection: some View {
        section("QR Code") {
            if showQR, let qr = SmartContentDetector.qrImage(for: content) {
                Image(nsImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 130, height: 130)
            } else {
                Button("Show QR Code") { showQR = true }
                    .font(.caption)
                    .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Building blocks

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            content()
        }
    }

    private func actionButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Helpers

    private func copy(_ string: String, message: String = "Copied") {
        viewModel.copyString(string)
        show(message)
    }

    private func shorten(_ url: URL) async {
        isShortening = true
        let result = await viewModel.shortenURL(url)
        isShortening = false
        if let result {
            shortURL = result
            viewModel.copyString(result)
            show("Short link copied")
        } else {
            show("Couldn't shorten link")
        }
    }

    private func show(_ message: String) {
        withAnimation { flash = message }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation { flash = nil }
        }
    }
}

private extension View {
    /// Presents Apple's system translation UI. Gracefully no-ops before macOS
    /// 14.4, where the presentation API isn't available.
    @ViewBuilder
    func translation(isPresented: Binding<Bool>, text: String) -> some View {
        if #available(macOS 14.4, *) {
            translationPresentation(isPresented: isPresented, text: text)
        } else {
            self
        }
    }
}
