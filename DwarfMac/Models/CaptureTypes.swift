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

    /// Geräte-Mode-ID für `SWITCH_SHOOTING_MODE` (cmd 16402). PCAP-verifiziert
    /// (protocol.md §18a): entspricht der Menü-Reihenfolge, 1-basiert.
    /// 1=Allgemein, 2=DeepSky, 3=Sonnensystem, 4=Milchstraße, 5=Sternspuren.
    var deviceMode: Int32 { Int32(rawValue) + 1 }

    /// Astro-Modi (Milchstraße/Sternspuren) fragen beim Wechsel zusätzlich die
    /// Astro-Belichtungszeit ab (cmd 11039); Foto-Modi senden stattdessen
    /// `SWITCH_SHOOTING_TECH` (cmd 16403).
    var isAstroMode: Bool {
        switch self {
        case .milkyWay, .starTrails: true
        default: false
        }
    }

    /// Ob die Telekamera in diesem Modus aktiv ist. Milchstraße/Sternspuren sind
    /// reine Weitwinkel-Modi — das Gerät schaltet den Tele-Stream (ch0) dort ab.
    /// Der Client darf ihn dann nicht anzuzeigen versuchen (sonst „nicht
    /// ansprechbar" + sinnlose Reconnects).
    var teleActive: Bool { !isAstroMode }

    /// Aufnahme-Typen, die das Gerät in diesem Modus unterstützt.
    var allowedCaptureTypes: [CaptureType] {
        switch self {
        case .allgemein, .solarSystem: CaptureType.allCases
        case .deepSky:                 [.stacked]
        case .milkyWay:                [.stacked, .timelapse]
        case .starTrails:              [.photo]
        }
    }

    /// Stellt sicher, dass `current` im Modus erlaubt ist; sonst den ersten erlaubten Typ.
    func validCaptureType(_ current: CaptureType) -> CaptureType {
        allowedCaptureTypes.contains(current) ? current : (allowedCaptureTypes.first ?? .stacked)
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

    /// Shooting-Technik für `switchShootingTech` (cmd 16403). SDK-Enum (dwarflab-sdk
    /// `ShootingTech`): SINGLE_SHOT=1, STACKING=2, BURST=3, VIDEO=4, TIMELAPSE=5,
    /// PANORAMA=6. Muss VOR der jeweiligen Aufnahme gesetzt werden — Serienfoto
    /// (BURST) wird sonst mit `code:-1 PARSE_PROTOBUF_ERROR` abgelehnt.
    var shootingTech: Int32 {
        switch self {
        case .stacked:   2   // STACKING
        case .photo:     1   // SINGLE_SHOT
        case .video:     4   // VIDEO
        case .burst:     3   // BURST
        case .timelapse: 5   // TIMELAPSE
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
