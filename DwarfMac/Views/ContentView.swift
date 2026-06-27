import SwiftUI

struct ContentView: View {
    let conn: DeviceConnection
    let deviceState: DeviceState
    let gamepad: GamepadController

    @AppStorage("deviceIP")    private var deviceIP    = DwarfEndpoint.defaultIP
    @AppStorage("observerLat") private var observerLat = 0.0
    @AppStorage("observerLon") private var observerLon = 0.0
    @AppStorage("observingMode") private var observingModeRaw = ObservingMode.allgemein.rawValue
    private var router: MessageRouter { MessageRouter(deviceState: deviceState) }

    @State private var showGoTo = false
    @State private var showAlbum = false
    private let locationManager = LocationManager()
    private let database = AstroDatabase()

    var body: some View {
        VStack(spacing: 0) {
            ConnectionBar(
                state: conn.state,
                errorMessage: conn.lastError,
                sentCount: conn.sentCount,
                receivedCount: conn.receivedCount,
                gamepad: gamepad,
                onConnect: {
                    conn.onMessage = { data in
                        router.route(data)
                    }
                    conn.host = deviceIP
                    conn.connect()
                },
                onDisconnect: { conn.disconnect() },
                onGoTo: { showGoTo = true }
            )
            .task {
                // Location einmalig beim Start anfordern, damit sie beim Connect verfügbar ist.
                locationManager.requestOnce()
            }
            .onChange(of: conn.state) { _, newState in
                guard newState == .connected else { return }
                // Guard gegen Spurious-Moduswechsel beim Menü-Öffnen seeden, damit der
                // erste Menü-Aufruf nach Connect nichts (Re-)Sendet.
                deviceState.lastSentObservingMode = observingModeRaw
                Task {
                    try? await conn.send(DwarfCommands.setTime())
                    try? await conn.send(DwarfCommands.setTimezone())
                    let lat = locationManager.lat ?? (observerLat != 0 ? observerLat : nil)
                    let lon = locationManager.lon ?? (observerLon != 0 ? observerLon : nil)
                    if let lat, let lon {
                        try? await conn.send(DwarfCommands.setLocation(
                            lat: lat, lon: lon, alt: locationManager.altitude))
                    }
                    try? await conn.send(DwarfCommands.getDeviceStateInfo())
                    try? await conn.send(DwarfCommands.getStackingList())
                    // Kamera-/Stream-Betrieb aufsetzen (enterCamera + Preview-Quality
                    // für beide Kameras) — sonst liefert ch1 (Weitwinkel) keine Frames.
                    for packet in DwarfCommands.startCameraStreams() {
                        try? await conn.send(packet)
                    }
                }
            }
            .sheet(isPresented: $showGoTo) {
                GoToView(conn: conn, state: deviceState,
                         location: locationManager, database: database)
            }
            .sheet(isPresented: $showAlbum) {
                NavigationStack {
                    AlbumView(host: conn.host)
                }
                .frame(minWidth: 1000, idealWidth: 1200, minHeight: 650, idealHeight: 800)
            }

            Divider()

            if conn.state == .connected {
                HStack {
                    CameraControlBar(conn: conn, state: deviceState)
                    Spacer()
                    Button { showAlbum = true } label: {
                        Label("Archiv", systemImage: "photo.on.rectangle.angled")
                    }
                    .buttonStyle(.bordered)
                    .padding(.trailing, 8)
                }
                Divider()
            }

            ScrollView {
                VStack(spacing: 20) {
                    CameraPiPView(ip: conn.host, active: conn.state == .connected, state: deviceState)
                        // Telemetrie links oben halbtransparent über das Video legen.
                        .overlay(alignment: .topLeading) {
                            StatusBar(state: deviceState)
                                .padding(8)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                                .opacity(0.85)
                                .padding(12)
                        }
                        // Steuerkreuz links unten halbtransparent über das große Video legen.
                        .overlay(alignment: .bottomLeading) {
                            DPadView(conn: conn)
                                .padding(12)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                .opacity(0.8)
                                .padding(16)
                                .disabled(conn.state != .connected)
                        }
                        // Großer runder Aufnahme-Button rechts mittig über dem Video.
                        .overlay(alignment: .trailing) {
                            RecordButton(conn: conn, state: deviceState)
                        }
                        // Bildeinstellungen: Icon oben rechts, klappt zum Regler-Panel auf.
                        .overlay(alignment: .topTrailing) {
                            CameraSettingsOverlay(conn: conn, state: deviceState)
                                .padding(12)
                        }
                        // Dezente Status-/Fehlerzeile oben mittig.
                        .overlay(alignment: .top) {
                            CaptureStatusOverlay(state: deviceState)
                        }
                        .padding(.horizontal)

                    if let t = deviceState.lastMessageTime {
                        Text("Letzte Nachricht: \(t.formatted(date: .omitted, time: .standard))  (\(deviceState.rawMessageCount) gesamt)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical)
            }
        }
    }
}

#Preview {
    ContentView(conn: DeviceConnection(), deviceState: DeviceState(), gamepad: GamepadController())
}
