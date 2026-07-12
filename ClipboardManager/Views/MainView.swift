import SwiftData
import SwiftUI

/// The popover shown from the menu bar: search field, pinned section, and
/// recent history.
struct MainView: View {
    @Environment(ClipboardViewModel.self) private var viewModel

    // Two queries keep the layout simple: pinned first, then everything else
    // newest-first. Filtering by search text happens in-memory below since the
    // history is small (capped at ~100 items).
    @Query(
        filter: #Predicate<ClipboardItem> { $0.isPinned },
        sort: \.createdAt, order: .reverse
    ) private var pinnedItems: [ClipboardItem]

    @Query(
        filter: #Predicate<ClipboardItem> { !$0.isPinned },
        sort: \.createdAt, order: .reverse
    ) private var recentItems: [ClipboardItem]

    @State private var category: CategoryFilter = .all
    @State private var favoritesOnly = false
    @State private var launchAtLogin = LoginItemService.isEnabled

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            if viewModel.isPrivateMode {
                privateModeBanner
            }

            SearchBarView(text: $viewModel.searchText)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            filterBar

            Divider()

            if filteredPinned.isEmpty && filteredRecent.isEmpty {
                emptyState
            } else {
                HistoryListView(
                    pinned: filteredPinned,
                    recent: filteredRecent
                )
            }

            Divider()
            footer
        }
        .frame(width: 360, height: 480)
        .onChange(of: launchAtLogin) { _, enabled in
            LoginItemService.setEnabled(enabled)
        }
    }

    private var privateModeBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "eye.slash.fill")
            Text("Private Mode — not tracking the clipboard")
            Spacer()
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.orange)
    }

    // MARK: - Filtering

    private var query: String {
        viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredPinned: [ClipboardItem] { filter(pinnedItems) }
    private var filteredRecent: [ClipboardItem] { filter(recentItems) }

    private func filter(_ items: [ClipboardItem]) -> [ClipboardItem] {
        items.filter { item in
            category.matches(item)
                && (!favoritesOnly || item.isFavorite)
                && (query.isEmpty || item.content.localizedCaseInsensitiveContains(query))
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(CategoryFilter.allCases) { option in
                        filterChip(option)
                    }
                }
            }
            Button {
                favoritesOnly.toggle()
            } label: {
                Image(systemName: favoritesOnly ? "star.fill" : "star")
                    .foregroundStyle(favoritesOnly ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .help("Show favorites only")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func filterChip(_ option: CategoryFilter) -> some View {
        let selected = category == option
        return Button {
            category = option
        } label: {
            Text(option.label)
                .font(.caption)
                .fontWeight(selected ? .semibold : .regular)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(
                    selected ? Color.accentColor.opacity(0.18) : Color.clear,
                    in: Capsule()
                )
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(query.isEmpty ? "Nothing copied yet" : "No matches")
                .font(.headline)
                .foregroundStyle(.secondary)
            if query.isEmpty {
                Text("Copy some text and it will appear here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Button(role: .destructive) {
                viewModel.clearHistory()
            } label: {
                Label("Clear History", systemImage: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(recentItems.isEmpty)

            Spacer()

            Button {
                viewModel.isPrivateMode.toggle()
            } label: {
                Label(
                    viewModel.isPrivateMode ? "Tracking Off" : "Private",
                    systemImage: viewModel.isPrivateMode ? "eye.slash.fill" : "eye.slash"
                )
            }
            .buttonStyle(.borderless)
            .foregroundStyle(viewModel.isPrivateMode ? .orange : .secondary)
            .help("Pause clipboard tracking")

            Button {
                viewModel.openSnippets?()
            } label: {
                Label("Snippets", systemImage: "note.text")
            }
            .buttonStyle(.borderless)

            Menu {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                Divider()
                Button("Export Backup (JSON)…") { viewModel.exportBackup() }
                Button("Export History (CSV)…") { viewModel.exportCSV() }
                Divider()
                Button("Import Backup…") { viewModel.importBackup() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Backup & restore")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.borderless)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
