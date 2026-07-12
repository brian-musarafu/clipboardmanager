import SwiftData
import SwiftUI

/// The snippet library window: a list of snippets with an editor.
struct SnippetsView: View {
    @Environment(SnippetsViewModel.self) private var viewModel
    @Query(sort: \Snippet.createdAt) private var snippets: [Snippet]
    @State private var selection: Snippet.ID?

    var body: some View {
        NavigationSplitView {
            List(snippets, selection: $selection) { snippet in
                VStack(alignment: .leading, spacing: 2) {
                    Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
                        .fontWeight(.medium)
                    Text(snippet.trigger.isEmpty ? "no trigger" : snippet.trigger)
                        .font(.caption.monospaced())
                        .foregroundStyle(snippet.trigger.isEmpty ? Color.secondary : Color.accentColor)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .toolbar {
                Button {
                    selection = viewModel.addSnippet().id
                } label: {
                    Label("Add Snippet", systemImage: "plus")
                }
            }
        } detail: {
            if let snippet = snippets.first(where: { $0.id == selection }) {
                SnippetEditorView(snippet: snippet)
                    .id(snippet.id)
            } else {
                ContentUnavailableView(
                    "No Snippet Selected",
                    systemImage: "note.text",
                    description: Text("Select a snippet, or add one with the + button.")
                )
            }
        }
        .frame(minWidth: 620, minHeight: 400)
    }
}

/// Editor for a single snippet. Edits bind straight to the model; changes are
/// saved (and expansion rules refreshed) as you type.
struct SnippetEditorView: View {
    @Environment(SnippetsViewModel.self) private var viewModel
    @Bindable var snippet: Snippet

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $snippet.title)
                TextField("Trigger", text: $snippet.trigger, prompt: Text("/sig"))
                    .font(.body.monospaced())
            } footer: {
                Text("Type the trigger anywhere to expand this snippet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Content") {
                TextEditor(text: $snippet.content)
                    .font(.body.monospaced())
                    .frame(minHeight: 140)
            }

            Section("Variables") {
                ForEach(SnippetVariables.reference, id: \.token) { variable in
                    HStack {
                        Text(variable.token).font(.caption.monospaced()).foregroundStyle(.tint)
                        Spacer()
                        Text(variable.description).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button("Delete Snippet", role: .destructive) {
                    viewModel.delete(snippet)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: snippet.title) { viewModel.save() }
        .onChange(of: snippet.trigger) { viewModel.save() }
        .onChange(of: snippet.content) { viewModel.save() }
    }
}
