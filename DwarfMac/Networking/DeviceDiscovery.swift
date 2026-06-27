import Foundation
import Network

/// Erkennt Dwarf-Teleskope im lokalen Netz via UDP-Broadcast auf Port 9900.
///
/// Protokoll (aus PCAP-Analyse, 2026-06-26):
///   Phone sendet UDP-Broadcast → 255.255.255.255:9900, 15-Byte Protobuf:
///     Field 1 (varint) = 1
///     Field 2 (varint) = aktueller Unix-Timestamp in Millisekunden
///     Field 3 (string) = "txtl"
///   Gerät antwortet per UDP-Unicast; wir nehmen die Quell-IP des ersten
///   eingehenden Pakets auf Port 9900 als Geräte-IP.
@MainActor
final class DeviceDiscovery: @unchecked Sendable {

    private var sendConnection: NWConnection?
    private var listener: NWListener?
    private var repeatTask: Task<Void, Never>?

    /// Wird aufgerufen, sobald eine Geräte-IP gefunden wurde (Main-Thread).
    var onFound: ((String) -> Void)?

    // MARK: - Public

    func start() {
        stop()
        openListener()
        repeatTask = Task {
            while !Task.isCancelled {
                sendBroadcast()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func stop() {
        repeatTask?.cancel()
        repeatTask = nil
        listener?.cancel()
        listener = nil
        sendConnection?.cancel()
        sendConnection = nil
    }

    // MARK: - Broadcast senden

    private func sendBroadcast() {
        let payload = buildPayload()
        let conn = NWConnection(
            host: "255.255.255.255",
            port: 9900,
            using: udpParams()
        )
        sendConnection?.cancel()
        sendConnection = conn
        conn.start(queue: .global())
        conn.send(content: payload, completion: .contentProcessed { _ in })
        Log.line("[Discovery] → Broadcast gesendet (\(payload.count) B)")
    }

    private func buildPayload() -> Data {
        var w = ProtoWriter()
        w.uint64(1, 1)                                  // field 1 = 1
        let ms = UInt64(Date().timeIntervalSince1970 * 1000)
        w.uint64(2, ms)                                 // field 2 = Unix-ms
        w.string(3, "txtl")                             // field 3 = "txtl"
        return w.data
    }

    // MARK: - Listener (eingehende Unicast-Antwort)

    private func openListener() {
        guard let l = try? NWListener(using: udpParams(), on: NWEndpoint.Port(rawValue: 9900)!) else {
            Log.line("[Discovery] Listener konnte nicht geöffnet werden")
            return
        }
        listener = l
        l.newConnectionHandler = { [weak self] conn in
            Task { @MainActor in self?.handleIncoming(conn) }
        }
        l.start(queue: .global())
        Log.line("[Discovery] Listener auf UDP:9900 geöffnet")
    }

    private func handleIncoming(_ conn: NWConnection) {
        conn.start(queue: .global())
        conn.receiveMessage { [weak self] data, ctx, _, _ in
            guard let self, let data else { return }
            // Quell-IP aus dem NWConnection-Endpoint extrahieren
            if case .hostPort(let host, _) = conn.endpoint {
                let ip = "\(host)"
                Log.line("[Discovery] ← Antwort von \(ip) (\(data.count) B): \(data.hexString)")
                Task { @MainActor in
                    self.onFound?(ip)
                    self.stop()
                }
            }
            conn.cancel()
        }
    }

    // MARK: - Hilfsmethoden

    private func udpParams() -> NWParameters {
        let p = NWParameters.udp
        p.allowLocalEndpointReuse = true
        // Broadcast erlauben
        if let opts = p.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            opts.version = .v4
        }
        return p
    }
}

private extension Data {
    var hexString: String {
        prefix(64).map { String(format: "%02x", $0) }.joined(separator: " ")
            + (count > 64 ? "…" : "")
    }
}
