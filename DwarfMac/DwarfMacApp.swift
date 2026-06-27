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

    var body: some Scene {
        WindowGroup {
            ContentView(conn: conn, deviceState: deviceState, gamepad: gamepad)
                .onAppear { gamepad.attach(conn: conn) }
        }
        .windowResizability(.contentMinSize)
        .commands {
            // Selten/gefährliche Aktionen in der Menüleiste verstecken.
            CommandMenu("Gerät") {
                Picker("Modus", selection: $observingModeRaw) {
                    ForEach(ObservingMode.allCases) { m in
                        Text(m.label).tag(m.rawValue)
                    }
                }
                Picker("Aufnahme-Typ", selection: $captureTypeRaw) {
                    ForEach(CaptureType.allCases) { t in
                        Text(t.label).tag(t.rawValue)
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

    private func send(_ packet: Data) {
        Task {
            do {
                try await conn.send(packet)
            } catch {
                Log.line("[DwarfMacApp] Senden fehlgeschlagen: \(error)")
            }
        }
    }
}
