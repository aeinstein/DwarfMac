import SwiftUI
import AppKit

/// Als SwiftPM-Executable (ohne .app-Bundle) startet macOS die App sonst als
/// „accessory" — ohne Menüleiste und Dock-Icon. Hier auf reguläre App umstellen.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.reset()   // Logdatei bei jedem Start leeren
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct DwarfMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // Verbindung + Telemetrie auf App-Ebene, damit auch die Menüleiste
    // („Gerät" → Neustart/Ausschalten) darauf zugreifen kann.
    @State private var conn        = DeviceConnection()
    @State private var deviceState = DeviceState()
    @State private var gamepad     = GamepadController()

    // Modus & Aufnahme-Typ teilen sich denselben @AppStorage-Key mit CaptureView/RecordButton.
    @AppStorage("observingMode") private var observingModeRaw = ObservingMode.allgemein.rawValue
    @AppStorage("captureType")   private var captureTypeRaw   = CaptureType.stacked.rawValue
    @AppStorage("expertMode")    private var expertMode = false

    private var isConnected: Bool { conn.state == .connected }
    private var currentMode: ObservingMode { ObservingMode(rawValue: observingModeRaw) ?? .allgemein }

    var body: some Scene {
        WindowGroup {
            ContentView(conn: conn, deviceState: deviceState, gamepad: gamepad)
                .onAppear { gamepad.attach(conn: conn) }
        }
        .windowResizability(.contentMinSize)
        .commands {
            // Selten/gefährliche Aktionen in der Menüleiste verstecken.
            CommandMenu("Gerät") {
                // ACHTUNG: KEIN `Picker` im CommandMenu! Ein `Picker` setzt beim
                // Menü-Öffnen seine Selection auf den ersten Wert (0) zurück und feuert
                // ein Spurious-`onChange` — das löste einen ungewollten Moduswechsel aus
                // und ließ den Stream einfrieren (verifiziert 2026-06-27). Buttons nicht.
                Menu("Modus") {
                    ForEach(ObservingMode.allCases) { m in
                        Button { selectObservingMode(m) } label: {
                            if observingModeRaw == m.rawValue {
                                Label(m.label, systemImage: "checkmark")
                            } else {
                                Text(m.label)
                            }
                        }
                    }
                }
                Menu("Aufnahme-Typ") {
                    ForEach(currentMode.allowedCaptureTypes) { t in
                        Button { captureTypeRaw = t.rawValue } label: {
                            if captureTypeRaw == t.rawValue {
                                Label(t.label, systemImage: "checkmark")
                            } else {
                                Text(t.label)
                            }
                        }
                    }
                }
                Divider()
                Toggle("Expertenmodus", isOn: $expertMode)
                Divider()
                Button("LED-Ring ein") { send(DwarfCommands.ledRingOn()) }
                    .disabled(!isConnected)
                Button("LED-Ring aus") { send(DwarfCommands.ledRingOff()) }
                    .disabled(!isConnected)
                Divider()
                Button("Akkuanzeige ein") { send(DwarfCommands.batteryIndicatorOn()) }
                    .disabled(!isConnected)
                Button("Akkuanzeige aus") { send(DwarfCommands.batteryIndicatorOff()) }
                    .disabled(!isConnected)
                Divider()
                Button("Neustart") { send(DwarfCommands.reboot()) }
                    .disabled(!isConnected)
                Button("Ausschalten") { send(DwarfCommands.powerDown()) }
                    .disabled(!isConnected)
            }
        }

        Settings {
            SettingsView()
        }
    }

    /// Beobachtungsmodus per Menü-Button wählen (explizite Nutzeraktion). Setzt den
    /// gespeicherten Modus und sendet die Wechsel-Transaktion nur bei echtem Wechsel.
    private func selectObservingMode(_ mode: ObservingMode) {
        observingModeRaw = mode.rawValue
        // Ungültige Aufnahme-Typ-Auswahl im neuen Modus auf einen gültigen Typ zurücksetzen.
        captureTypeRaw = mode.validCaptureType(CaptureType(rawValue: captureTypeRaw) ?? .stacked).rawValue
        guard isConnected, mode.rawValue != deviceState.lastSentObservingMode else { return }
        deviceState.lastSentObservingMode = mode.rawValue
        send(DwarfCommands.observingMode(mode))
    }

    private func send(_ packet: Data) {
        Task {
            do {
                try await conn.send(packet)
            } catch {
                Log.line("[DwarfMacApp] Senden fehlgeschlagen: \(error)")
            }
        }
    }

    /// Mehrere Pakete der Reihe nach senden (z. B. die Moduswechsel-Transaktion).
    private func send(_ packets: [Data]) {
        Task {
            for packet in packets {
                do {
                    try await conn.send(packet)
                } catch {
                    Log.line("[DwarfMacApp] Senden fehlgeschlagen: \(error)")
                }
            }
        }
    }
}
