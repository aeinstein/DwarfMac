@preconcurrency import GameController
import Foundation
import IOKit.hid

/// Liest USB/Bluetooth-Gamepad-Eingaben und übersetzt den linken Analogstick in
/// Dwarf-Joystick-Befehle.
///
/// Zwei Eingabe-Backends:
///  - **GameController.framework** (`GCController`) für MFi-/Xbox-/PlayStation- und
///    moderne Standard-HID-Controller.
///  - **IOKit HID** (`IOHIDManager`) als Fallback für generische USB-DirectInput-Gamepads
///    (z. B. Thrustmaster FireStorm), die `GameController.framework` nicht erkennt.
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

    /// True, wenn der aktive Controller über GameController.framework läuft. Dann
    /// wird der HID-Pfad ignoriert (sonst doppelte/konkurrierende Eingaben).
    private var usingGameController = false

    // HID-Fallback (IOHIDManager): rohe Achsen/Buttons generischer USB-Gamepads.
    @ObservationIgnored private var hidManager: IOHIDManager?

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
        startHIDManager()
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
                guard let self, self.usingGameController else { return }
                self.usingGameController = false
                self.isConnected = false
                self.controllerName = nil
                self.stickX = 0; self.stickY = 0
                self.dpadX  = 0; self.dpadY  = 0
                self.stopMovement()
                self.pollingTask?.cancel()
                self.pollingTask = nil
            }
        }

        // Bereits angeschlossene Controller sofort einrichten.
        if let ctrl = GCController.controllers().first { setup(ctrl) }
    }

    private func setup(_ controller: GCController) {
        isConnected  = true
        usingGameController = true
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

    // MARK: – IOKit-HID-Fallback (generische USB-DirectInput-Gamepads)

    /// Erstellt einen IOHIDManager, der auf Joystick-/Gamepad-Geräte (Generic Desktop
    /// usage 0x04/0x05) lauscht. Generische USB-Gamepads (z. B. Thrustmaster FireStorm)
    /// werden von GameController.framework nicht erkannt, von IOKit aber sehr wohl.
    private func startHIDManager() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Joystick],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(mgr, matching as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { ctx, _, _, device in
            guard let ctx else { return }
            let me = Unmanaged<GamepadController>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { me.hidDeviceMatched(device) }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { ctx, _, _, _ in
            guard let ctx else { return }
            let me = Unmanaged<GamepadController>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { me.hidDeviceRemoved() }
        }, context)
        IOHIDManagerRegisterInputValueCallback(mgr, { ctx, _, _, value in
            guard let ctx else { return }
            let me = Unmanaged<GamepadController>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { me.hidInput(value) }
        }, context)

        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = mgr
    }

    private func hidDeviceMatched(_ device: IOHIDDevice) {
        // GameController hat Vorrang; HID nur nutzen, wenn dort nichts läuft.
        guard !usingGameController else { return }
        isConnected = true
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
        controllerName = name ?? "USB-Gamepad"
        startPolling()
    }

    private func hidDeviceRemoved() {
        guard !usingGameController else { return }
        // Nur trennen, wenn kein weiteres HID-Gerät mehr da ist.
        let devices = hidManager.flatMap { IOHIDManagerCopyDevices($0) as? Set<IOHIDDevice> } ?? []
        guard devices.isEmpty else { return }
        isConnected = false
        controllerName = nil
        stickX = 0; stickY = 0
        dpadX  = 0; dpadY  = 0
        stopMovement()
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Verarbeitet einen einzelnen HID-Eingabewert: linker Stick (X/Y) auf −1…1
    /// normiert; Hat-Switch/Buttons als digitales D-Pad (Fallback).
    private func hidInput(_ value: IOHIDValue) {
        guard !usingGameController else { return }
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        guard usagePage == kHIDPage_GenericDesktop else { return }

        let raw = IOHIDValueGetIntegerValue(value)
        let min = IOHIDElementGetLogicalMin(element)
        let max = IOHIDElementGetLogicalMax(element)
        guard max > min else { return }
        // Auf −1…1 normieren.
        let norm = (Double(raw - min) / Double(max - min)) * 2 - 1

        switch Int(usage) {
        case kHIDUsage_GD_X:  stickX = Float(norm)        // links/rechts
        case kHIDUsage_GD_Y:  stickY = Float(-norm)       // HID: oben=min → invertieren (oben=+1, wie GC)
        case kHIDUsage_GD_Hatswitch:
            // Hat-Switch (8 Richtungen): nur grob auf D-Pad-Achsen abbilden.
            let count = max - min + 1
            if count >= 8, raw >= min, raw <= max {
                let dir = Int(raw - min)               // 0=oben, im Uhrzeigersinn
                let dx: [Float] = [0, 1, 1, 1, 0, -1, -1, -1]
                let dy: [Float] = [1, 1, 0, -1, -1, -1, 0, 1]
                dpadX = dx[dir % 8]; dpadY = dy[dir % 8]
            } else {
                dpadX = 0; dpadY = 0
            }
        default:
            break
        }
    }
}
