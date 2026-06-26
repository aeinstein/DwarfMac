import SwiftUI

/// Zeigt Telemetrie aus den Notify-Meldungen (Akku, Temperaturen, SD-Karte).
/// Werte kommen ~80 s nach Verbindungsaufbau als Batch-Notify vom Gerät.
struct StatusBar: View {
    let state: DeviceState

    var body: some View {
        HStack(spacing: 16) {
            item("🔋", battery)
            sensorItem
            item("♨️", system, label: "Sys")
            item("💾", sdcard)
        }
        .font(.callout)
    }

    // Sensor-Chip-Temperatur mit Warnfarbe wenn Alert-Flag gesetzt.
    private var sensorItem: some View {
        HStack(spacing: 4) {
            Text("🌡️")
            Text("CMOS").foregroundStyle(.secondary)
            Text(sensor)
                .foregroundStyle(state.sensorTemperatureAlert == true ? .orange : .secondary)
        }
    }

    private func item(_ icon: String, _ value: String, label: String? = nil) -> some View {
        HStack(spacing: 4) {
            Text(icon)
            if let l = label { Text(l).foregroundStyle(.secondary) }
            Text(value).foregroundStyle(.secondary)
        }
    }

    private var battery: String {
        guard let pct = state.batteryPercent else { return "—" }
        return state.isCharging == true ? "\(pct)% ⚡" : "\(pct)%"
    }
    private var sensor: String { state.sensorTemperature.map { "\($0)°C" } ?? "—" }
    private var system: String { state.systemTemperature.map { "\($0)°C" } ?? "—" }
    private var sdcard: String {
        if let a = state.sdAvailableGB, let t = state.sdTotalGB { return "\(a)/\(t) GB" }
        return "—"
    }
}
