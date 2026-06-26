import SwiftUI

struct ConnectionBar: View {
    let state: DeviceConnection.State
    let errorMessage: String?
    let sentCount: Int
    let receivedCount: Int
    let gamepad: GamepadController
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    let onGoTo: () -> Void

    // Aktueller Aufnahme-Typ/-Kamera (gewählt im Menü „Gerät" bzw. übers Hauptbild).
    @AppStorage("captureType")   private var captureTypeRaw   = CaptureType.stacked.rawValue
    @AppStorage("captureCamera") private var captureCameraRaw = CameraTarget.tele.rawValue

    private var capture: CaptureType { CaptureType(rawValue: captureTypeRaw) ?? .stacked }
    private var camera: CameraTarget {
        capture == .stacked ? .tele : (CameraTarget(rawValue: captureCameraRaw) ?? .tele)
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 10, height: 10)

                Text(stateLabel)
                    .font(.headline)

                Spacer()

                messageCounter

                captureInfo

                if gamepad.isConnected {
                    Label(gamepad.controllerName ?? "Gamepad", systemImage: "gamecontroller.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .help("Gamepad verbunden – linker Analogstick steuert das Teleskop")
                }

                Button("GoTo") { onGoTo() }
                    .disabled(state != .connected)

                Button("Verbinden") { onConnect() }
                    .disabled(state != .disconnected)

                Button("Trennen") { onDisconnect() }
                    .disabled(state == .disconnected)
            }

            if let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(errorMessage)
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// Zähler gesendeter/empfangener Nachrichten.
    private var messageCounter: some View {
        HStack(spacing: 8) {
            Label("\(sentCount)", systemImage: "arrow.up").help("Gesendet")
            Label("\(receivedCount)", systemImage: "arrow.down").help("Empfangen")
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    /// Kompakte Aufnahme-Anzeige im Header: Typ + (außer StackedFoto) Kamera.
    private var captureInfo: some View {
        Label {
            Text(capture == .stacked ? capture.label : "\(capture.label) · \(camera.label)")
        } icon: {
            Image(systemName: "camera")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .help("Aufnahme-Typ über Menü „Gerät“ wählen; Kamera = Hauptbild")
    }

    private var indicatorColor: Color {
        switch state {
        case .disconnected: .red
        case .connecting:   .orange
        case .connected:    .green
        }
    }

    private var stateLabel: String {
        switch state {
        case .disconnected: "Getrennt"
        case .connecting:   "Verbinde …"
        case .connected:    "Verbunden"
        }
    }
}
