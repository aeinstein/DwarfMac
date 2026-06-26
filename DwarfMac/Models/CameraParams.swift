import Foundation

// Belichtungs- und Gain-Wertetabellen für die Kameras (Quelle: APK
// assets/params_range.json). Das Protokoll erwartet in ReqSetExp/ReqSetGain
// NICHT einen 0-basierten Index, sondern den jeweiligen Tabellen-`value`
// (Belichtung 0,3,6,…,168; Gain 40,50,…,240). Wir bieten diese Werte mit
// lesbaren Labels (Sekunden/Brüche bzw. die Gain-Zahl) an.

enum CameraParams {

    struct Entry: Identifiable, Hashable {
        let value: Int32      // Protokollwert (an ReqSetExp/ReqSetGain.index)
        let label: String     // Anzeige (z. B. „1/100", „15 s", „240")
        var id: Int32 { value }
    }

    // value → Belichtungslabel (vollständige Tabelle aus expValues).
    private static let expLabels: [Int32: String] = [
        0: "1/10000", 3: "1/8000", 6: "1/6400", 9: "1/5000", 12: "1/4000",
        15: "1/3200", 18: "1/2500", 21: "1/2000", 24: "1/1600", 27: "1/1250",
        30: "1/1000", 33: "1/800", 36: "1/640", 39: "1/500", 42: "1/400",
        45: "1/320", 48: "1/250", 51: "1/200", 54: "1/160", 57: "1/125",
        60: "1/100", 63: "1/80", 66: "1/60", 69: "1/50", 72: "1/40",
        75: "1/30", 78: "1/25", 81: "1/20", 84: "1/15", 87: "1/13",
        90: "1/10", 93: "1/8", 96: "1/6", 99: "1/5", 102: "1/4",
        105: "1/3", 108: "0,4 s", 111: "0,5 s", 114: "0,6 s", 117: "0,8 s",
        120: "1 s", 123: "1,3 s", 126: "1,6 s", 129: "2 s", 132: "2,5 s",
        135: "3,2 s", 138: "4 s", 141: "5 s", 144: "6 s", 147: "8 s",
        150: "10 s", 153: "13 s", 156: "15 s", 159: "30 s", 160: "45 s",
        162: "60 s", 163: "90 s", 165: "120 s", 168: "180 s",
    ]

    /// Belichtungswerte je Kamera. Tele bis 180 s, Weitwinkel bis 30 s
    /// (Werte in 3er-Schritten 0…N; Obergrenzen gemäß Handbuch DWARF mini).
    static func exposures(for camera: CameraTarget) -> [Entry] {
        let maxValue: Int32 = camera == .tele ? 168 : 159
        return expLabels.keys
            .filter { $0 <= maxValue }
            .sorted()
            .map { Entry(value: $0, label: expLabels[$0] ?? "\($0)") }
    }

    /// Gain-Werte (40…240 in 10er-Schritten); Label = die Gain-Zahl.
    static func gains(for camera: CameraTarget) -> [Entry] {
        stride(from: Int32(40), through: 240, by: 10).map { Entry(value: $0, label: "\($0)") }
    }

    /// Sinnvolle Vorgabewerte (aus params_range.json defaultValue).
    static let defaultExposure: Int32 = 120   // 1 s
    static let defaultGain: Int32 = 60

    // MARK: Weißabgleich (Feature-Param id=2, aus params_config.json)

    /// Farbtemperatur (Gear-Mode, mode_index=0). CommonParam.index = Gear-Index
    /// (0,3,…,141 → 2800…7500 K in 100-K-Schritten).
    static let wbColorTemps: [Entry] = stride(from: Int32(0), through: 141, by: 3).map {
        Entry(value: $0, label: "\(2800 + Int($0) / 3 * 100) K")
    }
    static let defaultWbColorTemp: Int32 = 51   // 4500 K

    /// Szenen (Scene-Mode, mode_index=2). CommonParam.index = Szenen-Index 0…6.
    static let wbScenes: [Entry] = [
        Entry(value: 0, label: "Glühlampe"),
        Entry(value: 1, label: "Warmweiß (Leuchtstoff)"),
        Entry(value: 2, label: "Leuchtstoff"),
        Entry(value: 3, label: "Sonnenlicht"),
        Entry(value: 4, label: "Bewölkt"),
        Entry(value: 5, label: "Schatten"),
        Entry(value: 6, label: "Dämmerung"),
    ]
    static let defaultWbScene: Int32 = 3   // Sonnenlicht

    /// Schnappt einen (evtl. ungültigen) Wert auf den nächsten erlaubten Eintrag.
    static func snap(_ value: Int32, to entries: [Entry]) -> Int32 {
        entries.min(by: { abs($0.value - value) < abs($1.value - value) })?.value ?? value
    }
}
