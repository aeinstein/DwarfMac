import Foundation

@MainActor
@Observable
final class DeviceConnection: NSObject {
    enum State { case disconnected, connecting, connected }
    private(set) var state: State = .disconnected

    /// Letzte Fehlerursache (z. B. „Gerät nicht erreichbar"), für die UI.
    private(set) var lastError: String?

    /// Nachrichtenzähler für die UI (gesendete Binär-Frames bzw. empfangene
    /// Nachrichten ohne Ping/Pong-Keepalive).
    private(set) var sentCount = 0
    private(set) var receivedCount = 0

    /// Geräte-IP/Host; wird bei jedem `connect()` zum Aufbau der URL genutzt.
    var host: String

    private let maxRetries = 6
    private var retryCount = 0

    private var task: URLSessionWebSocketTask?
    @ObservationIgnored
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    private var reconnectTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var manualDisconnect = false

    var onMessage: ((Data) -> Void)?

    init(host: String = DwarfEndpoint.defaultIP) {
        self.host = host
        super.init()
    }

    func connect() {
        manualDisconnect = false
        retryCount = 0
        lastError = nil
        sentCount = 0
        receivedCount = 0
        startConnection()
    }

    func disconnect() {
        manualDisconnect = true
        reconnectTask?.cancel()
        pingTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        state = .disconnected
    }

    /// Sendet ein bereits kodiertes WsPacket als Binär-Frame.
    func send(_ packet: Data) async throws {
        guard let task, state == .connected else { throw URLError(.notConnectedToInternet) }
        try await task.send(.data(packet))
        sentCount += 1
        Self.log("→ TX", packet)
    }

    /// Loggt eine WS-Nachricht auf stdout: Richtung, dekodierter cmd/Modul/Typ,
    /// Bytezahl und vollständiger Hex-Dump (für Vergleich mit der Handy-App).
    private static func log(_ direction: String, _ data: Data) {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        if let p = WsPacket.decode(data) {
            Log.line("[WS] \(direction) cmd=\(p.cmdId) \(DwarfCmd.name(for: p.cmdId)) module=\(p.moduleId) \(Module.name(for: p.moduleId)) type=\(p.typeId) (\(data.count) B) data=\(p.data.map { String(format: "%02x", $0) }.joined()) | frame=\(hex)")
        } else {
            Log.line("[WS] \(direction) \(data.count) B (kein WsPacket) frame=\(hex)")
        }
    }

    private func startConnection() {
        state = .connecting
        let url = DwarfEndpoint.webSocket(ip: host)
        Log.line("[WS] → CONNECT \(url.absoluteString)")
        let wsTask = session.webSocketTask(with: url)
        self.task = wsTask
        wsTask.resume()
        // .connected wird erst im didOpen-Delegate gesetzt, sobald der
        // WebSocket-Handshake tatsächlich erfolgreich war.
        Task { await receiveLoop() }
    }

    // Dwarf-Keepalive auf Anwendungsebene: "81 04 ping" → mit "81 04 pong" antworten.
    private static let pingFrame = Data([0x81, 0x04, 0x70, 0x69, 0x6E, 0x67]) // "ping"
    private static let pongFrame = Data([0x81, 0x04, 0x70, 0x6F, 0x6E, 0x67]) // "pong"

    private func receiveLoop() async {
        guard let task else { return }
        do {
            while true {
                let msg = try await task.receive()
                switch msg {
                case .data(let data):
                    await handleIncoming(data)
                case .string(let str):
                    await handleIncoming(Data(str.utf8))
                @unknown default:
                    break
                }
            }
        } catch {
            // Statuswechsel/Reconnect werden zentral im didComplete-Delegate behandelt.
        }
    }

    private func handleIncoming(_ data: Data) async {
        // Geräte-Ping beantworten, Pong/Keepalive ignorieren.
        if data == Self.pingFrame {
            try? await task?.send(.data(Self.pongFrame))
            Log.line("[WS] → TX pong (app-ping beantwortet)")
            return
        }
        if data == Self.pongFrame { return }
        if let text = String(data: data, encoding: .utf8), text == "ping" || text == "pong" { return }

        receivedCount += 1
        Self.log("← RX", data)
        onMessage?(data)
    }

    // MARK: - Statusübergänge (vom Delegate aufgerufen, auf dem MainActor)

    private func handleOpen() {
        retryCount = 0
        lastError = nil
        state = .connected
        Log.line("[WS] ✓ OPEN — WebSocket verbunden")
        startPing()
        // Direkt nach dem Verbinden Master-Kontrolle übernehmen (sonst ignoriert der
        // mini Steuerbefehle, protocol.md 4.3), dann Geräte-Zustand + Kamera-Parameter abfragen.
        Task {
            try? await send(DwarfCommands.setMaster(true))
            try? await send(DwarfCommands.getDeviceStateInfo())
            try? await send(DwarfCommands.getTeleAllParams())
            try? await send(DwarfCommands.getTeleAllFeatureParams())
        }
    }

    private func handleClose(error: Error?) {
        pingTask?.cancel()
        task = nil
        state = .disconnected
        if let error {
            let ns = error as NSError
            Log.line("[WS] ✗ CLOSE — \(ns.domain) code=\(ns.code): \(ns.localizedDescription)")
        } else {
            Log.line("[WS] ✗ CLOSE — ohne Fehler (\(manualDisconnect ? "manuell getrennt" : "vom Gerät geschlossen"))")
        }
        guard !manualDisconnect else { return }
        if let error { lastError = describe(error) }
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard retryCount < maxRetries else {
            let base = lastError ?? "Verbindung fehlgeschlagen"
            lastError = "\(base) — nach \(maxRetries) Versuchen aufgegeben."
            state = .disconnected
            return
        }
        retryCount += 1
        state = .connecting

        // Exponentielles Backoff: 2s, 4s, 8s … (max 30s).
        let delay = min(UInt64(2) << (retryCount - 1), 30) * 1_000_000_000
        Log.line("[WS] ↻ Reconnect-Versuch \(retryCount)/\(maxRetries) in \(delay / 1_000_000_000)s")
        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: delay)
            if Task.isCancelled || manualDisconnect { return }
            startConnection()
        }
    }

    private func startPing() {
        pingTask?.cancel()
        pingTask = Task {
            while true {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 s wie websocket_class.js
                if Task.isCancelled { return }
                try? await task?.send(.string("ping"))
                Log.line("[WS] → TX ping (keepalive, Text-Frame)")
            }
        }
    }

    /// Übersetzt häufige Netzwerkfehler in verständliche deutsche Meldungen.
    private func describe(_ error: Error) -> String {
        guard let urlError = error as? URLError else {
            return (error as NSError).localizedDescription
        }
        switch urlError.code {
        case .cannotConnectToHost, .cannotFindHost:
            return "Gerät nicht erreichbar (\(host):9900) — eingeschaltet und im selben WLAN?"
        case .timedOut:
            return "Zeitüberschreitung beim Verbinden mit \(host)."
        case .notConnectedToInternet:
            return "Keine Netzwerkverbindung."
        case .networkConnectionLost:
            return "Verbindung verloren."
        case .cancelled:
            return "Verbindung abgebrochen."
        default:
            return urlError.localizedDescription
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension DeviceConnection: URLSessionWebSocketDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task { @MainActor in self.handleOpen() }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        Task { @MainActor in self.handleClose(error: error) }
    }

    // WebSocket-Close mit Code + optionalem Grund-Payload des Geräts (z. B. „belegt").
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "—"
        Log.line("[WS] ✗ CLOSE-FRAME code=\(closeCode.rawValue) reason=\(reasonText)")
    }
}
