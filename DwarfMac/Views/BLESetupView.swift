import SwiftUI
import CoreBluetooth

struct BLESetupView: View {
    @Binding var deviceIP: String
    @Environment(\.dismiss) private var dismiss

    @State private var ble = BLESetup()
    @State private var discovery = DeviceDiscovery()
    @AppStorage("blePsd") private var blePsd = "DWARF_12345678"

    @State private var selectedSSID = ""
    @State private var wifiPassword = ""
    @State private var step: Step = .scan
    @State private var resultIP = ""
    @State private var staWasSent = false
    @State private var discovering = false

    private enum Step { case scan, wifi, waitingWifi, success }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .scan:        scanView
                case .wifi:        wifiView
                case .waitingWifi: waitingWifiView
                case .success:     successView
                }
            }
            .navigationTitle(stepTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        ble.disconnect()
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 420, height: 480)
        .onDisappear {
            ble.disconnect()
            discovery.stop()
        }
        .onChange(of: ble.state) { _, new in
            if new == .connected { step = .wifi }
            // BLE trennt nach STA-Befehl → auf UDP-Discovery umschalten
            if new == .idle && staWasSent { startWifiDiscovery() }
        }
        .onAppear {
            ble.onConfigured = { ip in
                resultIP = ip
                step = .success
            }
            ble.onWifiAccepted = {
                startWifiDiscovery()
            }
        }
    }

    // MARK: - Schritt 1: Scan

    private var scanView: some View {
        VStack(spacing: 20) {
            if ble.state == .scanning {
                ProgressView("Suche nach DWARF-Geräten…")
            } else if ble.foundDevices.isEmpty {
                ContentUnavailableView(
                    "Kein Gerät gefunden",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("Stelle sicher, dass das Teleskop eingeschaltet ist und Bluetooth aktiviert ist.")
                )
            }

            if !ble.foundDevices.isEmpty {
                List(ble.foundDevices, id: \.identifier) { p in
                    Button {
                        ble.connect(p)
                    } label: {
                        Label(p.name ?? "Unbekanntes Gerät", systemImage: "telescope")
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.bordered)
            }

            if let err = ble.errorMessage {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            Spacer()

            HStack {
                if ble.state == .scanning {
                    Button("Suche stoppen") { ble.stopScan() }
                } else {
                    Button("Suche starten") { ble.startScan() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.bottom)
        }
        .padding()
    }

    // MARK: - Schritt 2: WLAN

    private var wifiView: some View {
        Form {
            Section("WLAN-Netzwerk") {
                if ble.wifiNetworks.isEmpty {
                    Button("Verfügbare Netze laden") {
                        ble.fetchWifiList()
                    }
                } else {
                    Picker("Netzwerk", selection: $selectedSSID) {
                        ForEach(ble.wifiNetworks, id: \.self) { ssid in
                            Text(ssid).tag(ssid)
                        }
                    }
                    .onAppear {
                        if selectedSSID.isEmpty { selectedSSID = ble.wifiNetworks.first ?? "" }
                    }
                    Button("Neu laden") { ble.fetchWifiList() }
                        .font(.footnote)
                }
                TextField("SSID (manuell)", text: $selectedSSID)
                    .textFieldStyle(.roundedBorder)
            }

            Section("WLAN-Passwort") {
                SecureField("Passwort", text: $wifiPassword)
                    .textFieldStyle(.roundedBorder)
            }

            Section {
                DisclosureGroup("BLE-Passwort") {
                    SecureField("BLE-Passwort", text: $blePsd)
                        .textFieldStyle(.roundedBorder)
                    Text("Standard: DWARF_12345678")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let err = ble.errorMessage {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            Button {
                ble.clearError()
                staWasSent = true
                ble.configureWifi(ssid: selectedSSID, wifiPassword: wifiPassword, blePsd: blePsd)
            } label: {
                Label("WLAN konfigurieren", systemImage: "wifi")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedSSID.isEmpty)
            .padding()
        }
    }

    // MARK: - Schritt 3: Warte auf Gerät im WLAN

    private var waitingWifiView: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("WLAN-Konfiguration gesendet")
                .font(.title3.bold())
            VStack(spacing: 4) {
                Text("Das Teleskop verbindet sich mit \"\(selectedSSID)\".")
                Text("Verbinde deinen Mac mit demselben WLAN —")
                Text("danach wird die IP automatisch erkannt.")
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            if let err = ble.errorMessage {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
            Spacer()
            Button("Manuell suchen") { startWifiDiscovery() }
                .buttonStyle(.bordered)
                .padding(.bottom)
        }
        .padding()
        .onAppear { startWifiDiscovery() }
        .onDisappear { discovery.stop() }
    }

    private func startWifiDiscovery() {
        guard !discovering else { return }
        discovering = true
        step = .waitingWifi
        discovery.onFound = { ip in
            resultIP = ip
            discovering = false
            step = .success
        }
        discovery.start()
    }

    // MARK: - Schritt 4: Erfolg

    private var successView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("WLAN konfiguriert")
                .font(.title2.bold())

            GroupBox {
                LabeledContent("IP-Adresse") {
                    Text(resultIP)
                        .monospaced()
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Neustart erforderlich", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.headline)
                    Text("Der WebSocket-Server startet erst nach einem Neustart auf dem neuen WLAN-Interface. Starte das Teleskop jetzt neu.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    deviceIP = resultIP
                    ble.disconnect()
                    dismiss()
                } label: {
                    Label("IP übernehmen & schließen", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    deviceIP = resultIP
                    ble.resetWifi()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        ble.disconnect()
                        dismiss()
                    }
                } label: {
                    Label("WiFi-Reset & schließen", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .help("Sendet Reset-Befehl an das Teleskop — danach Gerät manuell neustarten")
            }
            .padding()
        }
    }

    private var stepTitle: String {
        switch step {
        case .scan:        "BLE-Gerät suchen"
        case .wifi:        "WLAN einrichten"
        case .waitingWifi: "Warte auf Gerät…"
        case .success:     "Einrichtung abgeschlossen"
        }
    }
}
