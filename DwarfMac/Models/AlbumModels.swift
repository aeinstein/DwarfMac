import Foundation

enum MediaType: Int, CaseIterable, Identifiable {
    case all = 0, photo = 1, video = 2, burst = 3, astro = 4, timelapse = 5

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .all:       "Alle"
        case .photo:     "Fotos"
        case .video:     "Videos"
        case .burst:     "Serienfoto"
        case .astro:     "Astro"
        case .timelapse: "Zeitraffer"
        }
    }

    var icon: String {
        switch self {
        case .all:       "square.grid.2x2"
        case .photo:     "photo"
        case .video:     "video"
        case .burst:     "square.stack"
        case .astro:     "sparkles"
        case .timelapse: "timer"
        }
    }
}

struct MediaItem: Identifiable, Decodable {
    var id: String { filePath }
    let fileName: String
    let filePath: String
    let fileSize: Int
    let mediaType: Int
    let modificationTime: Int
    let thumbnailPath: String?
    let camId: Int?

    var date: Date { Date(timeIntervalSince1970: Double(modificationTime)) }
    var typeEnum: MediaType { MediaType(rawValue: mediaType) ?? .photo }
    var camera: String? {
        guard let c = camId else { return nil }
        return c == 0 ? "Tele" : "Weitwinkel"
    }

    var formattedSize: String {
        let mb = Double(fileSize) / 1_048_576
        return mb >= 1 ? String(format: "%.1f MB", mb) : String(format: "%.0f KB", Double(fileSize) / 1024)
    }

    /// Sinnvoller Dateiname für den Download: echte Endung aus `filePath`,
    /// Zeitstempel angehängt damit "Normal_Photo" o. ä. eindeutig wird.
    var suggestedFileName: String {
        // Endung möglichst aus dem echten Pfad, sonst aus dem Anzeigenamen.
        let pathExt = (filePath as NSString).pathExtension
        let nameExt = (fileName as NSString).pathExtension
        let ext = !pathExt.isEmpty ? pathExt : nameExt

        // Basisname ohne (evtl. vorhandene) Endung.
        var base = (fileName as NSString).deletingPathExtension
        if base.isEmpty { base = "DwarfMedia" }

        let stamp = Self.stampFormatter.string(from: date)
        let name = "\(base)_\(stamp)"
        return ext.isEmpty ? name : "\(name).\(ext)"
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f
    }()
}

struct MediaCount: Decodable {
    let mediaType: Int
    let count: Int
}
