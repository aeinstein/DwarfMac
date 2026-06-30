import Foundation

@Observable
final class DeviceState {
    // Verbindungsstatus (gespiegelt aus DeviceConnection für die UI)
    var isConnected: Bool = false

    // Telemetrie aus Notify-Meldungen
    var batteryPercent: Int?
    var isCharging: Bool?
    var sensorTemperature: Int?        // CMOS / Sensor-Chip (°C) — aus notifyCmosTemperature (15292)
    var sensorTemperatureAlert: Bool?  // field[2]=1 im selben Notify → Chip heiß nach Betrieb
    var systemTemperature: Int?        // Gehäuse/Bewegungseinheit (°C) — aus notifyTemperature (15243)
    var sdAvailableGB: Int?
    var sdTotalGB: Int?
    var isPoweringOff = false

    // MARK: Aufnahme-Status (gerätegeführt aus Notify-Meldungen)

    /// Welche Aufnahme das Gerät gerade meldet (nil = keine).
    var activeCapture: CaptureKind?
    var recordSeconds: Int?          // laufende Aufnahmedauer (Video)
    var burstCompleted: Int?         // Serienfoto-Fortschritt
    var burstTotal: Int?
    var stackedCount: Int?           // gestackte Frames (Live-Stacking)
    var exposureElapsed: Double?     // laufende Belichtung (Langzeit) in s
    var exposureTotal: Double?

    // MARK: Astro GoTo / Kalibrierung
    var calibrationState: AstroState = .idle
    var calibrationPlateSolvingTimes: Int = 0
    var gotoState: AstroState = .idle
    var gotoTargetName: String?
    var trackingState: AstroState = .idle

    // MARK: Fokus
    var focusValue: Int?             // aktuelle Fokusposition (notifyFocus)
    var isAutoFocusing = false       // Autofokus läuft (normal oder astro)

    // MARK: Kameramodus
    var shootingModeId: Int?         // aktueller Shooting-Mode (notifySwitchShootingMode)
    /// Zuletzt ans Gerät gesendeter Beobachtungsmodus (rawValue). Liegt hier in der
    /// stabilen @Observable-Referenz statt in @State der App, weil der `Picker` im
    /// CommandMenu beim Öffnen ein Spurious-`onChange` auslöst und ein @State-Guard
    /// dort nicht zuverlässig hält.
    var lastSentObservingMode: Int?

    // MARK: Geräte-Zustand (aus GET_DEVICE_STATE_INFO, cmd=16405)
    var teleStreamType: Int?         // aktueller Stream-Typ der Telekamera
    var wideStreamType: Int?
    var teleResolution: String?      // z. B. „1920×1080"
    var wideResolution: String?
    var teleHFov: Double?            // Sichtfeld (Grad)
    var teleVFov: Double?
    var wideTemperature: Int?        // CMOS-Temp Weitwinkel (°C)
    var teleExclusiveState: Int?     // 0=verfügbar, 1=exklusiv belegt (anderer Client)
    var wideExclusiveState: Int?

    // Reconnect-Token für die RTSP-Player: wird hochgezählt, wenn das Gerät einen
    // Stream-Wechsel meldet (notifyStreamType 15234 / geänderter Stream-Typ). Ein
    // Moduswechsel (Allgemein↔Astro) stellt den Geräte-Stream um; ohne erneutes
    // DESCRIBE/SETUP/PLAY bleibt der alte Stream „hängen". Die `RTSPPlayerView`
    // beobachtet den Token und verbindet bei Änderung neu.
    var teleStreamReload = 0
    var wideStreamReload = 0

    // MARK: Kamera-Parameter (synchronisiert vom Gerät via notifyGeneralIntParam, cmd=15264)
    // Werden beim Empfang in die UI-Schieberegler gespiegelt (kein Feedback-Loop, da
    // die Schieberegler nur beim Loslassen senden).
    var teleBrightness: Int?
    var teleContrast: Int?
    var teleSaturation: Int?
    var teleHue: Int?
    var teleSharpness: Int?
    var wideBrightness: Int?
    var wideContrast: Int?
    var wideSaturation: Int?
    var wideHue: Int?
    var wideSharpness: Int?
    // Belichtung/Gain/IR-Cut werden ebenfalls über notifyGeneralIntParam gemeldet
    // (paramId 1=Belichtung, 2=Gain, 13=IR-Cut/filterType).
    var teleExposure: Int?
    var teleGain: Int?
    var teleIrCut: Int?
    var wideExposure: Int?
    var wideGain: Int?
    var wideIrCut: Int?
    /// Inkrementiert bei jedem eingehenden Param-Notify → löst UI-Sync aus.
    var paramGeneration: Int = 0

    // MARK: Weißabgleich (vom Gerät gemeldet, notifyWb)
    var wbMode: Int?                 // 0=Farbtemperatur, 1=Szene
    var wbIndex: Int?                // gemeldeter WB-Index
    var wbAuto: Bool?                // Auto-Weißabgleich aktiv

    // MARK: Stacking-Presets (vom Gerät, cmd=11040)
    var stackingPresets: [StackingPreset] = []
    var selectedStackingPresetId: Int?

    /// Setzt eine Aufnahmeart aktiv bzw. beendet sie (löscht dann die Detailwerte).
    func setCapture(_ kind: CaptureKind, active: Bool) {
        if active {
            activeCapture = kind
        } else if activeCapture == kind {
            activeCapture = nil
            recordSeconds = nil
            burstCompleted = nil
            burstTotal = nil
            stackedCount = nil
        }
    }

    // MARK: Befehls-Antworten (REQUEST_RESPONSE)

    var lastResponseCmd: UInt32?
    var lastResponseCode: Int32?
    /// Verständliche Fehlermeldung des letzten fehlgeschlagenen Befehls (nil = ok).
    var lastErrorText: String?

    // Letzte empfangene Meldung
    var lastMessageTime: Date?
    var lastCmdId: UInt32?
    var rawMessageCount: Int = 0

    func noteMessage(cmdId: UInt32) {
        lastMessageTime = .now
        lastCmdId = cmdId
        rawMessageCount += 1
    }
}

/// Aufnahmeart, die das Gerät meldet.
enum CaptureKind {
    case recording, burst, timelapse, stacking
}

/// Stacking-Preset vom Gerät (cmd=11040).
struct StackingPreset: Identifiable {
    let id: Int       // Geräte-interne ID (proto field[2])
    let name: String  // Belichtungszeit-Label, z. B. "2", "3.2", "15"
    let frames: Int   // Anzahl zu stapelnder Frames (proto field[3])
}
