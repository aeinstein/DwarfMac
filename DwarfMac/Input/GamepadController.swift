@preconcurrency import GameController
import Foundation

/// Liest USB/Bluetooth-Gamepad-Eingaben (Apple GameController.framework) und
/// übersetzt den linken Analogstick in Dwarf-Joystick-Befehle.
///
/// Polling-Ansatz (150 ms) statt rein event-reaktiv, damit die Sende-Rate mit
/// DPadView übereinstimmt und kurze Deadzone-Unterschreitungen nicht zu Flackern führen.
@MainActor
@Observable
final class GamepadController {

    // MARK: – Öffentlicher Zustand (für UI)

    private(set) var isConnected  = false
    private(set) var controllerName: String?

    // MARK: – Private

    private weak var conn: DeviceConnection?

    /// Rohwerte des linken Analogsticks (−1 … 1), aktualisiert durch valueChangedHandler.
    private var stickX: Float = 0
    private var stickY: Float = 0

    /// D-Pad-Buttons des Controllers (−1/0/1); Fallback wenn Analogstick im Ruhezustand.
    private var dpadX: Float = 0
    private var dpadY: Float = 0

    private var wasActive  = false
    private var pollingTask: Task<Void, Never>?

    // MARK: – Einstellungen (UserDefaults, geschrieben von SettingsView via @AppStorage)

    private var deadzone: Double {
        let v = UserDefaults.standard.double(forKey: "gamepadDeadzone")
        return v > 0 ? v : 0.15
    }

    private var maxSpeed: Double {
        let v = UserDefaults.standard.double(forKey: "gamepadMaxSpeed")
        return v > 0 ? v : 0.5
    }

    // MARK: – Öffentliche API

    /// Verbindung herstellen und Controller-Erkennung starten.
    func attach(conn: DeviceConnection) {
        self.conn = conn
        startObserving()
    }

    // MARK: – Controller-Erkennung

    private func startObserving() {
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // note ignorieren (Notification ist nicht Sendable); stattdessen
            // GCController.controllers() abfragen — die Liste ist vor der Notification aktuell.
            MainActor.assumeIsolated {
                guard let ctrl = GCController.controllers().first else { return }
                self?.setup(ctrl)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isConnected = false
                self?.controllerName = nil
                self?.stickX = 0; self?.stickY = 0
                self?.dpadX  = 0; self?.dpadY  = 0
                self?.stopMovement()
                self?.pollingTask?.cancel()
                self?.pollingTask = nil
            }
        }

        // Bereits angeschlossene Controller sofort einrichten.
        if let ctrl = GCController.controllers().first { setup(ctrl) }
    }

    private func setup(_ controller: GCController) {
        isConnected  = true
        controllerName = controller.vendorName ?? "Gamepad"

        // Linker Analogstick → stickX/Y (Haupt-Eingang)
        controller.extendedGamepad?.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            Task { @MainActor [weak self] in
                self?.stickX = x
                self?.stickY = y
            }
        }

        // D-Pad-Buttons des Controllers → dpadX/Y (Fallback / digitale Präzision)
        controller.extendedGamepad?.dpad.valueChangedHandler = { [weak self] _, x, y in
            Task { @MainActor [weak self] in
                self?.dpadX = x
                self?.dpadY = y
            }
        }

        startPolling()
    }

    // MARK: – Polling-Loop

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(nanoseconds: 150_000_000)   // 150 ms ≈ 6–7 Hz
            }
        }
    }

    /// Wird alle 150 ms aufgerufen. Liest Stick-Zustand, berechnet Winkel + Geschwindigkeit
    /// und sendet den passenden Joystick-Befehl (oder stoppt, wenn im Deadzone-Bereich).
    private func tick() {
        // Analogstick hat Vorrang; D-Pad-Buttons als Fallback wenn Stick in Ruhe.
        let useStick = stickX != 0 || stickY != 0
        let x = Double(useStick ? stickX : dpadX)
        let y = Double(useStick ? stickY : dpadY)
        let mag = (x * x + y * y).squareRoot()
        let dz  = deadzone

        guard mag >= dz else {
            stopMovement()
            return
        }

        // Winkel im Dwarf-Koordinatensystem: rechts=0°, oben=90°, links=180°, unten=270°.
        // atan2(y, x) liefert dasselbe Vorzeichen-Verhalten — nur negative Werte auf 0…360 normieren.
        let angle = (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)

        // Geschwindigkeit: 0 an der Deadzone-Grenze, maxSpeed bei Vollausschlag.
        let normalizedMag = min((mag - dz) / (1.0 - dz), 1.0)
        // D-Pad-Buttons: fester Teilausschlag (~40 % des maxSpeed)
        let speed = useStick ? normalizedMag * maxSpeed : maxSpeed * 0.4

        wasActive = true
        Task { [weak self] in
            try? await self?.conn?.send(DwarfCommands.joystick(angle: angle, speed: speed))
        }
    }

    private func stopMovement() {
        guard wasActive else { return }
        wasActive = false
        Task { [weak self] in
            try? await self?.conn?.send(DwarfCommands.joystickStop())
        }
    }
}
