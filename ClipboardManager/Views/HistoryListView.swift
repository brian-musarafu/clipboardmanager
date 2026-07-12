import SwiftUI

/// Scrolling list of history, split into a pinned section and a recent section.
struct HistoryListView: View {
    let pinned: [ClipboardItem]
    let recent: [ClipboardItem]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if !pinned.isEmpty {
                    sectionHeader("Pinned", systemImage: "pin.fill")
                    ForEach(pinned) { item in
                        ItemRowView(item: item)
                    }
                }

                if !recent.isEmpty {
                    sectionHeader("Recent", systemImage: "clock")
                        .padding(.top, pinned.isEmpty ? 0 : 8)
                    ForEach(recent) { item in
                        ItemRowView(item: item)
                    }
                }
            }
            .padding(8)
        }
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
    }
}
