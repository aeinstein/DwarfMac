import SwiftUI

// MARK: - ViewModel

@MainActor
@Observable
final class AlbumViewModel {
    var items: [MediaItem] = []
    var counts: [Int: Int] = [:]
    var selectedType: Int = 0
    var isLoading = false
    var error: String?
    private var page = 0
    private var hasMore = true

    func loadCounts(host: String) async {
        guard counts.isEmpty else { return }
        do {
            let c = try await AlbumService.fetchCounts(host: host)
            counts = Dictionary(uniqueKeysWithValues: c.map { ($0.mediaType, $0.count) })
        } catch {
            self.error = error.localizedDescription
        }
    }

    func load(host: String, reset: Bool = false) async {
        if reset { items = []; page = 0; hasMore = true }
        guard hasMore, !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let batch = try await AlbumService.fetchItems(host: host, mediaType: selectedType, page: page)
            items.append(contentsOf: batch)
            if batch.count == 50 { page += 1 } else { hasMore = false }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func selectType(_ type: Int, host: String) async {
        selectedType = type
        await load(host: host, reset: true)
    }

    func delete(_ item: MediaItem, host: String) async {
        do {
            try await AlbumService.deleteItems(host: host, items: [item])
            items.removeAll { $0.id == item.id }
            counts[item.mediaType] = (counts[item.mediaType] ?? 1) - 1
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - AlbumView

struct AlbumView: View {
    let host: String

    @Environment(\.dismiss) private var dismiss
    @State private var model = AlbumViewModel()
    @State private var selected: MediaItem?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            content
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Schließen") { dismiss() }
            }
        }
        .sheet(item: $selected) { item in
            AlbumItemSheet(item: item, host: host) {
                Task { await model.delete(item, host: host) }
            }
        }
        .task {
            await model.loadCounts(host: host)
            await model.load(host: host)
        }
    }

    // MARK: Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(MediaType.allCases) { type in
                    let count = type == .all
                        ? model.counts.values.reduce(0, +)
                        : model.counts[type.rawValue] ?? 0
                    Button {
                        Task { await model.selectType(type.rawValue, host: host) }
                    } label: {
                        Label("\(type.label) \(count > 0 ? "(\(count))" : "")", systemImage: type.icon)
                    }
                    .buttonStyle(.bordered)
                    .tint(model.selectedType == type.rawValue ? .accentColor : nil)
                }
                Spacer()
                Button { Task { await model.loadCounts(host: host); await model.load(host: host, reset: true) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Neu laden")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.items.isEmpty {
            ProgressView("Lade Archiv…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = model.error {
            ContentUnavailableView("Fehler", systemImage: "exclamationmark.triangle", description: Text(err))
        } else if model.items.isEmpty {
            ContentUnavailableView("Keine Dateien", systemImage: "photo.on.rectangle.angled",
                                   description: Text("Dieser Filter enthält keine Aufnahmen."))
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(model.items) { item in
                        AlbumCell(item: item, host: host)
                            .onTapGesture { selected = item }
                            .onAppear {
                                if item.id == model.items.last?.id {
                                    Task { await model.load(host: host) }
                                }
                            }
                    }
                }
                .padding(16)
                if model.isLoading {
                    ProgressView().padding()
                }
            }
        }
    }
}

// MARK: - AlbumCell

private struct AlbumCell: View {
    let item: MediaItem
    let host: String

    var body: some View {
        thumbnail
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(item.typeEnum.label, systemImage: item.typeEnum.icon)
                        .font(.caption2)
                        .foregroundStyle(.white)
                    Text(item.fileName)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.55))
            }
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let path = item.thumbnailPath, let url = AlbumService.url(host: host, devicePath: path) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                case .failure:
                    placeholder
                default:
                    Color.gray.opacity(0.2).overlay(ProgressView().scaleEffect(0.6))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Color.gray.opacity(0.15)
            .overlay(Image(systemName: item.typeEnum.icon)
                .font(.largeTitle).foregroundStyle(.secondary))
    }
}

// MARK: - AlbumItemSheet

struct AlbumItemSheet: View {
    let item: MediaItem
    let host: String
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var downloading = false
    @State private var downloadError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Preview
            Group {
                if item.typeEnum == .video || item.typeEnum == .timelapse {
                    ZStack {
                        Color.black
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                } else if let path = item.thumbnailPath, let url = AlbumService.url(host: host, devicePath: path) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFit()
                        default: Color.gray.opacity(0.1)
                        }
                    }
                } else {
                    Color.gray.opacity(0.1)
                        .overlay(Image(systemName: item.typeEnum.icon).font(.system(size: 72)).foregroundStyle(.secondary))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            .background(Color.black)

            // Info
            Form {
                Section {
                    LabeledContent("Dateiname")  { Text(item.fileName).textSelection(.enabled) }
                    LabeledContent("Typ")        { Text(item.typeEnum.label) }
                    LabeledContent("Kamera")     { Text(item.camera ?? "–") }
                    LabeledContent("Größe")      { Text(item.formattedSize) }
                    LabeledContent("Datum")      { Text(item.date, style: .date) + Text("  ") + Text(item.date, style: .time) }
                }
            }
            .formStyle(.grouped)
            .frame(height: 220)

            if let err = downloadError {
                Text(err).font(.footnote).foregroundStyle(.red).padding(.horizontal)
            }

            // Buttons
            HStack(spacing: 12) {
                Button(role: .destructive) {
                    onDelete()
                    dismiss()
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Schließen") { dismiss() }

                Button {
                    Task { await download() }
                } label: {
                    if downloading {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Label("Herunterladen", systemImage: "arrow.down.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(downloading)
            }
            .padding()
        }
        .frame(minWidth: 700, idealWidth: 900)
    }

    private func download() async {
        guard let fileURL = AlbumService.url(host: host, devicePath: item.filePath) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.fileName
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        downloading = true
        downloadError = nil
        defer { downloading = false }
        do {
            let (tmp, _) = try await URLSession.shared.download(from: fileURL)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
        } catch {
            downloadError = error.localizedDescription
        }
    }
}
