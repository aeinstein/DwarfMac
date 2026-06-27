import SwiftUI
import VLCKitSPM

/// Spielt einen einzelnen RTSP-Stream via VLCKit ab. Status + Fehler werden
/// beobachtbar bereitgestellt; die VLC-Wiedergabe läuft auf dem MainActor.
@MainActor
@Observable
final class RTSPPlayer: NSObject, VLCMediaPlayerDelegate {
    enum Status { case idle, connecting, playing, error }

    private(set) var status: Status = .idle
    private(set) var errorMessage: String?

    /// Kamera-Bezeichnung fürs Logging (z. B. „Teleobjektiv"/„Weitwinkel").
    @ObservationIgnored var label = "?"

    @ObservationIgnored let videoView = VLCVideoView()
    @ObservationIgnored private let player = VLCMediaPlayer()

    /// Zuletzt angeforderte URL — für den automatischen Neustart bei Fehlern.
    @ObservationIgnored private var currentURL: URL?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var retryCount = 0

    override init() {
        super.init()
        videoView.fillScreen = true
        player.delegate = self
        player.drawable = videoView
    }

    func start(url: URL) {
        Log.line("[RTSP \(label)] start \(url.absoluteString)")
        retryTask?.cancel()
        currentURL = url
        retryCount = 0
        play(url: url)
    }

    func stop() {
        Log.line("[RTSP \(label)] stop")
        retryTask?.cancel()
        currentURL = nil
        player.stop()
        status = .idle
        errorMessage = nil
    }

    /// Startet die VLC-Wiedergabe (ohne den Retry-Zähler zurückzusetzen).
    private func play(url: URL) {
        Log.line("[RTSP \(label)] play (connecting) \(url.absoluteString)")
        status = .connecting
        let media = VLCMedia(url: url)
        // RTSP über TCP (stabiler als UDP) und kurze Pufferzeit für Live-Bild.
        media.addOption(":rtsp-tcp")
        media.addOption(":network-caching=300")
        player.media = media
        player.play()
    }

    /// Plant nach einem Fehler einen Neustart mit exponentiellem Backoff
    /// (1s, 2s, 4s … gedeckelt bei 10s). Wird NICHT aufgegeben, solange eine URL
    /// gesetzt ist — der Player wird beim Trennen via `stop()` sauber beendet.
    /// So kommt das Bild zurück, sobald das Gerät wieder streamt (z. B. nach
    /// `astroGoLive` im Anschluss an Live-Stacking).
    private func scheduleRestart(reason: String) {
        guard let url = currentURL else { return }   // nach stop() kein Neustart
        retryCount += 1
        status = .connecting
        errorMessage = "\(reason) — Neuverbindung …"

        let exponent = min(retryCount - 1, 4)        // 2^0 … 2^4, dann Deckel
        let delay = min(UInt64(1) << exponent, 10) * 1_000_000_000
        Log.line("[RTSP \(label)] scheduleRestart #\(retryCount) in \(delay / 1_000_000_000)s — \(reason)")
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled, self.currentURL == url else { return }
            self.play(url: url)
        }
    }

    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        // VLCKit ruft den Delegate auf dem Main-Thread auf.
        MainActor.assumeIsolated {
            Log.line("[RTSP \(label)] VLC-State → \(Self.stateName(player.state)) (status=\(status))")
            switch player.state {
            case .error:
                scheduleRestart(reason: "RTSP-Wiedergabefehler")
            case .opening, .buffering:
                if status != .playing { status = .connecting }
            case .playing:
                status = .playing
                errorMessage = nil
                retryCount = 0   // erfolgreiche Wiedergabe: Backoff zurücksetzen
            case .ended, .stopped:
                // Unerwartetes Ende während laufender Wiedergabe → neu verbinden.
                if status == .playing {
                    scheduleRestart(reason: "Stream-Verbindung beendet")
                }
            default:
                break
            }
        }
    }

    private static func stateName(_ s: VLCMediaPlayerState) -> String {
        switch s {
        case .stopped: "stopped"
        case .opening: "opening"
        case .buffering: "buffering"
        case .ended: "ended"
        case .error: "error"
        case .playing: "playing"
        case .paused: "paused"
        @unknown default: "unknown(\(s.rawValue))"
        }
    }
}

/// Bettet die VLC-`VLCVideoView` in SwiftUI ein.
private struct VLCVideoContainer: NSViewRepresentable {
    let player: RTSPPlayer
    func makeNSView(context: Context) -> VLCVideoView { player.videoView }
    func updateNSView(_ nsView: VLCVideoView, context: Context) {}
}

/// SwiftUI-Ansicht für einen RTSP-Stream mit Titel, Platzhalter und Fehlerausgabe.
struct RTSPPlayerView: View {
    var title: String
    /// RTSP-URL; bei `nil` wird nichts abgespielt.
    var url: URL?
    var compact: Bool = false
    /// Erzwingt einen Reconnect (fresh DESCRIBE/SETUP/PLAY), wenn der Wert sich
    /// ändert — das Gerät hat den Stream umgestellt (z. B. nach Moduswechsel).
    var reloadToken: Int = 0

    @State private var player = RTSPPlayer()

    var body: some View {
        ZStack {
            Rectangle().fill(.black)

            if url != nil {
                VLCVideoContainer(player: player)
            }

            if player.status != .playing {
                placeholder
            }
        }
        // Titel nur im PiP-Inset (compact); im Hauptbild ohne Beschriftung.
        .overlay(alignment: .topLeading) { if compact { titleBadge } }
        .overlay(alignment: .bottom) { errorBadge }
        .clipShape(RoundedRectangle(cornerRadius: compact ? 6 : 10))
        .onAppear { restart(url) }
        .onDisappear { player.stop() }
        .onChange(of: url) { _, newURL in restart(newURL) }
        .onChange(of: reloadToken) { _, _ in restart(url) }
    }

    private var titleBadge: some View {
        Text(title)
            .font(compact ? .caption2 : .caption.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.black.opacity(0.5), in: Capsule())
            .foregroundStyle(.white)
            .padding(compact ? 4 : 6)
    }

    @ViewBuilder
    private var errorBadge: some View {
        if let error = player.errorMessage {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(error).lineLimit(2)
            }
            .font(compact ? .caption2 : .caption)
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
            .padding(compact ? 4 : 8)
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(compact ? .title3 : .largeTitle)
                .foregroundStyle(.secondary)
            if !compact {
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var icon: String {
        switch player.status {
        case .idle: "video.slash"
        case .connecting: "arrow.triangle.2.circlepath"
        case .error: "exclamationmark.triangle"
        case .playing: "video"
        }
    }

    private var statusText: String {
        switch player.status {
        case .idle: "Kein Stream"
        case .connecting: "Verbinde mit Stream …"
        case .error: "Stream-Fehler"
        case .playing: ""
        }
    }

    private func restart(_ url: URL?) {
        player.label = title
        if let url { player.start(url: url) } else { player.stop() }
    }
}
