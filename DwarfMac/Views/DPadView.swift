import SwiftUI

/// Steuerkreuz (Joystick-D-Pad). Eigenständige View, damit es sowohl im
/// ControlPanel als auch als Overlay über dem großen Video genutzt werden kann.
struct DPadView: View {
    let conn: DeviceConnection

    // Beim Halten einer Richtungstaste rampt die Geschwindigkeit linear hoch:
    // Start 0,05 → nach 5 s 0,5 (danach konstant), bis losgelassen wird. Dazu wird
    // der Joystick-Befehl periodisch mit steigendem vector_length nachgesendet.
    private let startSpeed = 0.05
    private let maxSpeed = 0.5
    private let rampDuration: TimeInterval = 5

    @State private var pressedDir: Direction?
    @State private var rampTask: Task<Void, Never>?

    enum Direction { case up, down, left, right }

    private func angle(for dir: Direction) -> Double {
        switch dir {
        case .right: 0
        case .up:    90
        case .left:  180
        case .down:  270
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            dpadButton("▲", .up)
            HStack(spacing: 8) {
                dpadButton("◄", .left)
                Button(action: stop) {
                    Image(systemName: "stop.fill")
                        .frame(width: 44, height: 44)
                }
                dpadButton("►", .right)
            }
            dpadButton("▼", .down)
        }
        .font(.title2)
    }

    private func dpadButton(_ label: String, _ dir: Direction) -> some View {
        Text(label)
            .frame(width: 44, height: 44)
            .background(pressedDir == dir ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            // Drücken = Bewegung starten, Loslassen = stoppen.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard pressedDir != dir else { return }
                        pressedDir = dir
                        move(dir)
                    }
                    .onEnded { _ in
                        pressedDir = nil
                        stop()
                    }
            )
    }

    // MARK: - Aktionen

    private func move(_ dir: Direction) {
        let ang = angle(for: dir)
        rampTask?.cancel()
        rampTask = Task { @MainActor in
            let start = Date()
            while !Task.isCancelled {
                let frac = min(1.0, Date().timeIntervalSince(start) / rampDuration)
                let speed = startSpeed + (maxSpeed - startSpeed) * frac
                try? await conn.send(DwarfCommands.joystick(angle: ang, speed: speed))
                try? await Task.sleep(nanoseconds: 150_000_000)   // ~6–7 Updates/s
            }
        }
    }

    private func stop() {
        rampTask?.cancel()
        rampTask = nil
        send(DwarfCommands.joystickStop())
    }

    private func send(_ packet: Data) {
        Task {
            do {
                try await conn.send(packet)
            } catch {
                Log.line("[DPadView] Senden fehlgeschlagen: \(error)")
            }
        }
    }
}
