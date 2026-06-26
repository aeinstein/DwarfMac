import SwiftUI

/// Großer runder Aufnahme-Button als Overlay über dem Video. Löst die im
/// „Aufnahme"-Tab gewählte Aufnahme aus (gleiche `@AppStorage`-Keys) und spiegelt
/// den geräteseitigen Laufzustand (`state.activeCapture`).
struct RecordButton: View {
    let conn: DeviceConnection
    let state: DeviceState

    @AppStorage("captureType")       private var captureTypeRaw     = CaptureType.stacked.rawValue
    @AppStorage("captureCamera")    private var captureCameraRaw   = CameraTarget.tele.rawValue
    @AppStorage("stackCount")       private var stackCount         = 10
    @AppStorage("timelapseInterval") private var timelapseInterval = 5
    @AppStorage("timelapseCount")   private var timelapseCount     = 60

    private var capture: CaptureType { CaptureType(rawValue: captureTypeRaw) ?? .stacked }

    /// Stacked-Foto läuft immer über die Telekamera (MODULE_ASTRO).
    private var camera: CameraTarget {
        capture == .stacked ? .tele : (CameraTarget(rawValue: captureCameraRaw) ?? .tele)
    }

    /// Läuft die zum aktuellen Typ passende Aufnahme gerade?
    private var isRunning: Bool {
        guard let kind = CaptureSession.expectedKind(for: capture) else { return false }
        return state.activeCapture == kind
    }

    var body: some View {
        Button(action: trigger) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                Circle()
                    .stroke(.white.opacity(0.9), lineWidth: 3)
                    .padding(3)
                innerShape
            }
            .frame(width: 64, height: 64)
        }
        .buttonStyle(.plain)
        .opacity(0.9)
        .padding(20)
        .disabled(conn.state != .connected)
        .help(helpText)
    }

    /// Innensymbol: laufend → rotes Quadrat (Stop); Foto → weißer Auslöser;
    /// sonst → roter Kreis (Aufnahme starten).
    @ViewBuilder
    private var innerShape: some View {
        if isRunning {
            RoundedRectangle(cornerRadius: 5)
                .fill(.red)
                .frame(width: 24, height: 24)
        } else if capture == .photo {
            Circle()
                .fill(.white)
                .frame(width: 44, height: 44)
        } else {
            Circle()
                .fill(.red)
                .frame(width: 44, height: 44)
        }
    }

    private var helpText: String {
        if capture == .photo { return "Foto aufnehmen" }
        return isRunning ? "Aufnahme stoppen" : "Aufnahme starten"
    }

    private func trigger() {
        state.lastErrorText = nil
        let packets: [Data]
        if capture == .photo {
            packets = CaptureSession.startPackets(type: .photo, camera: camera, count: stackCount)
        } else if isRunning {
            // Gerätestatus sofort aufräumen (wie in CaptureView.stopCapture).
            if let kind = CaptureSession.expectedKind(for: capture) {
                state.setCapture(kind, active: false)
            }
            packets = CaptureSession.stopPackets(type: capture, camera: camera)
        } else {
            packets = CaptureSession.startPackets(type: capture, camera: camera, count: stackCount,
                                                  timelapseInterval: timelapseInterval,
                                                  timelapseCount: timelapseCount)
        }
        packets.forEach(send)
    }

    private func send(_ packet: Data) {
        Task {
            do {
                try await conn.send(packet)
            } catch {
                Log.line("[RecordButton] Senden fehlgeschlagen: \(error)")
            }
        }
    }
}
