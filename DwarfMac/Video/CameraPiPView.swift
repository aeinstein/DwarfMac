import SwiftUI

/// Zeigt beide Kameras gleichzeitig: eine groß, die andere als Picture-in-Picture.
///
/// Wichtig: Beide Player behalten ihre feste Kamera-URL und ihre View-Identität.
/// Beim Tausch ändern sich nur Größe/Position/zIndex (animiert) — die RTSP-Streams
/// werden NICHT neu verbunden.
struct CameraPiPView: View {
    let ip: String
    let active: Bool
    let state: DeviceState

    // Welche Kamera groß läuft, teilt sich den @AppStorage-Key mit der Aufnahme:
    // so nimmt die Aufnahme/​der Record-Button immer die im Hauptfenster gezeigte Kamera.
    @AppStorage("captureCamera") private var captureCameraRaw = CameraTarget.tele.rawValue
    @AppStorage("observingMode") private var observingModeRaw = ObservingMode.allgemein.rawValue

    private var mode: ObservingMode { ObservingMode(rawValue: observingModeRaw) ?? .allgemein }
    /// In reinen Weitwinkel-Modi (Milchstraße/Sternspuren) ist Tele aus.
    private var teleActive: Bool { mode.teleActive }
    /// Tele nur dann groß, wenn es auch aktiv ist; sonst läuft Weitwinkel groß.
    private var teleIsMain: Bool { teleActive && captureCameraRaw == CameraTarget.tele.rawValue }

    private var teleURL: URL { DwarfEndpoint.telephotoStream(ip: ip) }
    private var wideURL: URL { DwarfEndpoint.wideangleStream(ip: ip) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let pipW = max(120, w * 0.28)
            let pipH = pipW * 9.0 / 16.0
            let inset: CGFloat = 12

            let mainCenter = CGPoint(x: w / 2, y: h / 2)
            let pipCenter = CGPoint(x: w - inset - pipW / 2, y: h - inset - pipH / 2)

            ZStack {
                camera(title: "Teleobjektiv", url: teleURL, isMain: teleIsMain,
                       cameraActive: active && teleActive, hidden: !teleActive,
                       reloadToken: state.teleStreamReload,
                       full: (w, h), pip: (pipW, pipH),
                       center: teleIsMain ? mainCenter : pipCenter)

                camera(title: "Weitwinkel", url: wideURL, isMain: !teleIsMain,
                       cameraActive: active, hidden: false,
                       reloadToken: state.wideStreamReload,
                       full: (w, h), pip: (pipW, pipH),
                       center: teleIsMain ? pipCenter : mainCenter,
                       showFovRect: teleActive)
            }
            .animation(.easeInOut(duration: 0.25), value: teleIsMain)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
    }

    private func camera(
        title: String,
        url: URL,
        isMain: Bool,
        cameraActive: Bool,
        hidden: Bool,
        reloadToken: Int,
        full: (CGFloat, CGFloat),
        pip: (CGFloat, CGFloat),
        center: CGPoint,
        showFovRect: Bool = false
    ) -> some View {
        // `hidden` = Kamera ist in diesem Modus abgeschaltet (z. B. Tele in
        // Milchstraße/Sternspuren). View-Identität bleibt erhalten (kein if/else),
        // nur url=nil (Player stoppt) + ausgeblendet — so reißt der andere Stream
        // beim Moduswechsel nicht ab.
        RTSPPlayerView(title: title, url: cameraActive ? url : nil, compact: !isMain, reloadToken: reloadToken)
            .frame(width: isMain ? full.0 : pip.0,
                   height: isMain ? full.1 : pip.1)
            .overlay {
                if !isMain && !hidden {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.white.opacity(0.7), lineWidth: 1)
                }
            }
            .overlay { if showFovRect { TeleFovOverlay() } }
            .shadow(radius: isMain ? 0 : 4)
            .position(center)
            .zIndex(isMain ? 0 : 1)
            .opacity(hidden ? 0 : 1)
            .allowsHitTesting(!hidden)
            // Tippen auf das PiP-Inset macht diese Kamera zum Hauptbild.
            .onTapGesture {
                if !isMain {
                    captureCameraRaw = (teleIsMain ? CameraTarget.wide : CameraTarget.tele).rawValue
                }
            }
            .help(isMain ? "" : "Tippen, um diese Kamera groß anzuzeigen")
    }
}
