import Foundation

/// Bildet einen Aufnahme-Typ (+ Zielkamera) auf die zu sendenden Start-/Stop-Pakete ab.
/// Geteilt von `CaptureView` (Aufnahme-Tab) und `RecordButton` (Video-Overlay), damit
/// beide Bedienorte exakt dieselben Befehle senden.
enum CaptureSession {

    /// Pakete zum Starten der Aufnahme. Für `.photo` ist dies die Einmal-Auslösung.
    static func startPackets(type: CaptureType, camera: CameraTarget,
                             count: Int,
                             timelapseInterval: Int = 5,
                             timelapseCount: Int = 60) -> [Data] {
        switch type {
        case .stacked:
            return [DwarfCommands.astroStartLiveStacking()]
        case .photo:
            return [camera == .tele ? DwarfCommands.telePhotograph() : DwarfCommands.widePhotograph()]
        case .video:
            return [camera == .tele ? DwarfCommands.teleStartRecord() : DwarfCommands.wideStartRecord()]
        case .burst:
            return [camera == .tele ? DwarfCommands.teleBurst(count: Int32(count))
                                    : DwarfCommands.wideBurst(count: Int32(count))]
        case .timelapse:
            return [camera == .tele
                ? DwarfCommands.teleStartTimelapse(interval: Int32(timelapseInterval), count: Int32(timelapseCount))
                : DwarfCommands.wideStartTimelapse(interval: Int32(timelapseInterval), count: Int32(timelapseCount))]
        }
    }

    /// Pakete zum Stoppen der Aufnahme. `.photo` ist eine Einmal-Aktion ohne Stop.
    static func stopPackets(type: CaptureType, camera: CameraTarget) -> [Data] {
        switch type {
        case .stacked:
            // Tele-Kamera zurück auf Live: GoLive + erneutes Betreten des Kamera-
            // Betriebs (Task-Center), damit der RTSP-Stream wieder läuft.
            return [DwarfCommands.astroStopLiveStacking(),
                    DwarfCommands.astroGoLive(),
                    DwarfCommands.enterCamera()]
        case .photo:
            return []
        case .video:
            return [camera == .tele ? DwarfCommands.teleStopRecord() : DwarfCommands.wideStopRecord()]
        case .burst:
            return [camera == .tele ? DwarfCommands.teleStopBurst() : DwarfCommands.wideStopBurst()]
        case .timelapse:
            return [camera == .tele ? DwarfCommands.teleStopTimelapse() : DwarfCommands.wideStopTimelapse()]
        }
    }

    /// Aufnahmeart, die das Gerät für diesen Typ melden würde (nil = Einzelfoto).
    static func expectedKind(for type: CaptureType) -> CaptureKind? {
        switch type {
        case .stacked:   .stacking
        case .video:     .recording
        case .burst:     .burst
        case .timelapse: .timelapse
        case .photo:     nil
        }
    }
}
