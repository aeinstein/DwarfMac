import SwiftUI

/// Persistente App-Einstellungen (über UserDefaults / `@AppStorage`).
/// Erweiterbar: weitere Sections für künftige Einstellungen ergänzen.
struct SettingsView: View {
    @AppStorage("deviceIP")          private var deviceIP          = DwarfEndpoint.defaultIP

    @State private var discovery    = DeviceDiscovery()
    @State private var discovering  = false
    @State private var showBLESetup = false
    @AppStorage("observerLat")       private var observerLat       = 0.0
    @AppStorage("observerLon")       private var observerLon       = 0.0
    @AppStorage("gamepadDeadzone")   private var gamepadDeadzone   = 0.15
    @AppStorage("gamepadMaxSpeed")   private var gamepadMaxSpeed   = 0.5

    var body: some View {
        Form {
            Section("Verbindung") {
                HStack {
                    TextField("Geräte-IP", text: $deviceIP)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        if discovering {
                            discovery.stop()
                            discovering = false
                        } else {
                            discovering = true
                            discovery.onFound = { ip in
                                deviceIP = ip
                                discovering = false
                            }
                            discovery.start()
                        }
                    } label: {
                        if discovering {
                            Label("Suche läuft…", systemImage: "stop.circle")
                        } else {
                            Label("Suchen", systemImage: "magnifyingglass")
                        }
                    }
                    .help("Dwarf-Gerät im Netz per UDP-Broadcast suchen")
                }
                Text("Änderungen werden beim nächsten Verbindungsaufbau wirksam.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    showBLESetup = true
                } label: {
                    Label("BLE-Einrichtung…", systemImage: "antenna.radiowaves.left.and.right")
                }
                .help("Teleskop erstmalig per Bluetooth mit dem WLAN verbinden")
                .sheet(isPresented: $showBLESetup) {
                    BLESetupView(deviceIP: $deviceIP)
                }
            }
            Section("Beobachter-Standort") {
                LabeledContent("Breitengrad") {
                    TextField("z. B. 48.1370", value: $observerLat, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                }
                LabeledContent("Längengrad") {
                    TextField("z. B. 11.5760", value: $observerLon, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                }
                Text("Wird beim Verbinden an das Gerät gesendet und als Fallback für GoTo/Kalibrierung genutzt. GPS (CoreLocation) hat Vorrang, wenn verfügbar.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Gamepad") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Deadzone") {
                        HStack {
                            Slider(value: $gamepadDeadzone, in: 0.05...0.40, step: 0.01)
                                .frame(width: 160)
                            Text(String(format: "%.0f %%", gamepadDeadzone * 100))
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                    LabeledContent("Max. Geschwindigkeit") {
                        HStack {
                            Slider(value: $gamepadMaxSpeed, in: 0.10...1.00, step: 0.05)
                                .frame(width: 160)
                            Text(String(format: "%.0f %%", gamepadMaxSpeed * 100))
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
                Text("Deadzone: minimaler Stick-Ausschlag, unterhalb dessen keine Bewegung gesendet wird. Max. Geschwindigkeit: Stick-Vollausschlag entspricht diesem vector_length-Wert (0–1).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Zeitzone") {
                LabeledContent("Systemzeitzone") {
                    Text(TimeZone.current.identifier)
                        .foregroundStyle(.secondary)
                }
                Text("Wird beim Verbinden automatisch an das Gerät übertragen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }
}

#Preview {
    SettingsView()
}
