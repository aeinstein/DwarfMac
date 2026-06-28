import SwiftUI

/// Schmale Leiste unter der Verbindungsleiste:
/// - Kamera-Stream starten/stoppen
/// - Aufnahme-Modus wählen
/// - Modus-spezifische Parameter (Anzahl, Preset, Interval …) direkt einstellen
struct CameraControlBar: View {
    let conn: DeviceConnection
    let state: DeviceState

    @AppStorage("captureType")        private var captureTypeRaw    = CaptureType.stacked.rawValue
    @AppStorage("observingMode")      private var observingModeRaw  = ObservingMode.allgemein.rawValue
    @AppStorage("stackCount")         private var stackCount        = 10
    @AppStorage("timelapseInterval")  private var timelapseInterval = 5
    @AppStorage("timelapseCount")     private var timelapseCount    = 60

    private var capture: CaptureType { CaptureType(rawValue: captureTypeRaw) ?? .stacked }
    private var mode: ObservingMode { ObservingMode(rawValue: observingModeRaw) ?? .allgemein }

    var body: some View {
        HStack(spacing: 14) {
            // — Kamera-Stream —
            Text("Kameras").font(.callout.weight(.medium))
            Button("Starten") { startCameras() }
            Button("Stoppen") { stopCameras() }

            Divider().frame(height: 18)

            // — Aufnahme-Modus —
            Text("Aufnahme").font(.callout.weight(.medium))
            Picker("Modus", selection: $captureTypeRaw) {
                ForEach(mode.allowedCaptureTypes) { t in
                    Text(t.label).tag(t.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 110)

            // — Modus-spezifische Parameter —
            modeParams

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    // MARK: – Modus-Parameter

    @ViewBuilder
    private var modeParams: some View {
        switch capture {

        case .stacked:
            if state.stackingPresets.isEmpty {
                // Gerät hat noch keine Preset-Liste geliefert → manueller Stepper
                Stepper("Anzahl: \(stackCount)", value: $stackCount, in: 1...200)
                    .help("Anzahl gestackter Frames (wird nach Abschluss dieser Anzahl automatisch gestoppt, sofern implementiert)")
            } else {
                // Preset-Liste vom Gerät: Segmented-Picker
                Picker("Stacking-Preset", selection: Binding(
                    get: { state.selectedStackingPresetId ?? state.stackingPresets.first?.id ?? 0 },
                    set: { state.selectedStackingPresetId = $0 }
                )) {
                    ForEach(state.stackingPresets) { p in
                        Text("\(p.name) s · \(p.frames)×").tag(p.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
                .help("Belichtungszeit-Preset für Live-Stacking")
            }

        case .burst:
            Stepper("Anzahl: \(stackCount)", value: $stackCount, in: 1...999)
                .help("Anzahl der Einzelbilder im Serienfoto")

        case .timelapse:
            HStack(spacing: 10) {
                Stepper("Interval: \(timelapseInterval) s", value: $timelapseInterval, in: 1...300)
                    .help("Sekunden zwischen zwei Zeitraffer-Aufnahmen")
                Stepper("Anzahl: \(timelapseCount)", value: $timelapseCount, in: 1...9999)
                    .help("Gesamtanzahl der Zeitraffer-Aufnahmen")
            }

        case .photo, .video:
            EmptyView()
        }
    }

    // MARK: – Kamera-Befehle

    private func startCameras() {
        // enterCamera + Preview-Quality für beide Kameras (sonst kein Wide-Bild).
        DwarfCommands.startCameraStreams().forEach(send)
        send(DwarfCommands.getTeleAllParams())
        send(DwarfCommands.getTeleAllFeatureParams())
    }

    private func stopCameras() {
        send(DwarfCommands.closeWideCamera())
        send(DwarfCommands.closeTeleCamera())
    }

    private func send(_ packet: Data) {
        Task {
            do {
                try await conn.send(packet)
            } catch {
                Log.line("[CameraControlBar] Senden fehlgeschlagen: \(error)")
            }
        }
    }
}
