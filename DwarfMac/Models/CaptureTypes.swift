import Foundation

/// Beobachtungs-Modus. Nur „Allgemein" ist umgesetzt; die übrigen sind Platzhalter.
enum ObservingMode: Int, CaseIterable, Identifiable {
    case allgemein, deepSky, solarSystem, milkyWay, starTrails
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .allgemein:   "Allgemein"
        case .deepSky:     "DeepSky"
        case .solarSystem: "Sonnensystem"
        case .milkyWay:    "Milchstraße"
        case .starTrails:  "Sternspuren"
        }
    }
}

/// Aufnahme-Typ innerhalb des Modus „Allgemein".
enum CaptureType: Int, CaseIterable, Identifiable {
    case stacked, photo, video, burst, timelapse
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .stacked:   "StackedFoto"
        case .photo:     "Foto"
        case .video:     "Video"
        case .burst:     "Serienfoto"
        case .timelapse: "Zeitraffer"
        }
    }
}

/// Zielkamera für Aufnahme und Parameter. Stacked-Foto nutzt immer die Telekamera.
enum CameraTarget: Int, CaseIterable, Identifiable {
    case tele, wide
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .tele: "Tele"
        case .wide: "Weitwinkel"
        }
    }
}
