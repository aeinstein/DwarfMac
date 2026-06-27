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
}

struct MediaCount: Decodable {
    let mediaType: Int
    let count: Int
}
