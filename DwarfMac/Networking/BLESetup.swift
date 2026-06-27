import Foundation
import CoreBluetooth

private let svcUUID   = CBUUID(string: "FFE0")
private let writeUUID = CBUUID(string: "FFE1")
private let notifyUUID = CBUUID(string: "FFE2")
private let dwarfUUID = CBUUID(string: "9999")   // DWARF 3: write+notify

// MARK: - BLESetup

@MainActor
@Observable
final class BLESetup: NSObject, @unchecked Sendable {

    enum State { case idle, scanning, connecting, connected, failed }

    private(set) var state: State = .idle
    private(set) var foundDevices: [CBPeripheral] = []
    private(set) var wifiNetworks: [String] = []
    private(set) var errorMessage: String?

    /// Wird nach erfolgreichem STA-Setup mit der Geräte-IP aufgerufen.
    var onConfigured: ((String) -> Void)?
    /// Wird aufgerufen, wenn das Gerät die WLAN-Konfiguration akzeptiert hat,
    /// aber noch keine IP zurückgegeben hat (UDP-Discovery nötig).
    var onWifiAccepted: (() -> Void)?

    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var writeChar: CBCharacteristic?
    @ObservationIgnored private var notifyChar: CBCharacteristic?
    @ObservationIgnored private var receiveBuffer = [UInt8]()

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Public API

    func startScan() {
        foundDevices = []
        errorMessage = nil
        guard central.state == .poweredOn else {
            errorMessage = "Bluetooth nicht verfügbar"
            state = .failed
            return
        }
        state = .scanning
        // Kein UUID-Filter: viele Geräte annoncieren Service-UUIDs nicht im Advertisement.
        // Stattdessen wird nach dem Gerätenamen ("DWARF…") gefiltert.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        Log.line("[BLE] Scan gestartet")
    }

    func stopScan() {
        central.stopScan()
        if state == .scanning { state = .idle }
    }

    func connect(_ p: CBPeripheral) {
        stopScan()
        peripheral = p
        p.delegate = self
        state = .connecting
        central.connect(p, options: nil)
        Log.line("[BLE] Verbinde mit \(p.name ?? "?")")
    }

    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        writeChar = nil
        notifyChar = nil
        receiveBuffer = []
        state = .idle
    }

    func fetchWifiList() {
        let payload = buildGetWifiListPayload()
        send(cmd: 6, payload: payload)
    }

    func fetchConfig(blePsd: String) {
        let payload = buildGetConfigPayload(blePsd: blePsd)
        send(cmd: 1, payload: payload)
    }

    func clearError() { errorMessage = nil }

    func resetWifi() {
        var w = ProtoWriter()
        w.int32(1, 5)   // cmd = 5 (ReqReset)
        send(cmd: 5, payload: w.data)
        Log.line("[BLE] WiFi-Reset gesendet")
    }

    func configureWifi(ssid: String, wifiPassword: String, blePsd: String) {
        let payload = buildStaPayload(ssid: ssid, psd: wifiPassword, blePsd: blePsd)
        send(cmd: 3, payload: payload)
    }

    // MARK: - BLE Frame Encoding

    private func buildGetConfigPayload(blePsd: String) -> Data {
        var w = ProtoWriter()
        w.int32(1, 1)           // cmd = 1
        w.string(2, blePsd)
        return w.data
    }

    private func buildGetWifiListPayload() -> Data {
        var w = ProtoWriter()
        w.int32(1, 6)           // cmd = 6
        return w.data
    }

    private func buildStaPayload(ssid: String, psd: String, blePsd: String) -> Data {
        var w = ProtoWriter()
        w.int32(1, 3)           // cmd = 3
        w.int32(2, 1)           // auto_start = 1
        w.string(3, blePsd)
        w.string(4, ssid)
        w.string(5, psd)
        return w.data
    }

    private func buildFrame(cmd: UInt8, payload: Data) -> Data {
        var buf: [UInt8] = [
            0xAA, 0x01, cmd, 0x00, 0x01, 0x00, 0x00,
            UInt8(payload.count >> 8 & 0xFF),
            UInt8(payload.count & 0xFF),
        ]
        buf.append(contentsOf: payload)
        let crc = crc16Modbus(buf)
        buf.append(UInt8(crc >> 8 & 0xFF))
        buf.append(UInt8(crc & 0xFF))
        buf.append(0x0D)
        return Data(buf)
    }

    private func crc16Modbus(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                if crc & 0x0001 != 0 { crc = (crc >> 1) ^ 0xA001 }
                else { crc >>= 1 }
            }
        }
        return crc
    }

    // MARK: - Send

    private func send(cmd: UInt8, payload: Data) {
        guard let p = peripheral, let wc = writeChar, state == .connected else {
            Log.line("[BLE] Senden fehlgeschlagen: nicht verbunden")
            return
        }
        let frame = buildFrame(cmd: cmd, payload: payload)
        Log.line("[BLE] → TX cmd=\(cmd) (\(frame.count) B)")
        p.writeValue(frame, for: wc, type: .withResponse)
    }

    // MARK: - Response Parsing

    private func handleReceivedData(_ data: Data) {
        receiveBuffer.append(contentsOf: data)
        // Mindestgröße: 7 Header + 2 Länge + 0 Payload + 2 CRC + 1 Ende = 12
        // [UInt8] hat immer startIndex=0 nach removeFirst — kein Data-Slice-Problem.
        while receiveBuffer.count >= 12 {
            guard receiveBuffer[0] == 0xAA else {
                receiveBuffer.removeFirst()
                continue
            }
            let dataLen = Int(receiveBuffer[7]) << 8 | Int(receiveBuffer[8])
            let frameLen = 9 + dataLen + 3
            guard receiveBuffer.count >= frameLen else { break }
            let cmd = receiveBuffer[2]
            let payload = Data(receiveBuffer[9..<9 + dataLen])
            receiveBuffer.removeFirst(frameLen)
            dispatchResponse(cmd: cmd, payload: payload)
        }
    }

    private func dispatchResponse(cmd: UInt8, payload: Data) {
        Log.line("[BLE] ← RX cmd=\(cmd) (\(payload.count) B)")
        switch cmd {
        case 1: handleResGetconfig(payload)
        case 3: handleResSta(payload)
        case 6: handleResWifilist(payload)
        default: break
        }
    }

    private func handleResGetconfig(_ data: Data) {
        // ResGetconfig: field 2 = code (varint), field 10 = ip (string)
        let fields = ProtoReader.messageFields(in: data)
        if let ipData = fields[10]?.first, let ip = String(data: ipData, encoding: .utf8), !ip.isEmpty {
            Log.line("[BLE] Aktuelle IP: \(ip)")
        }
    }

    private func handleResSta(_ data: Data) {
        Log.line("[BLE] ResSta raw: \(data.map { String(format: "%02x", $0) }.joined(separator: " "))")
        let strFields = ProtoReader.messageFields(in: data)
        let intFields = ProtoReader.varintFields(in: data)
        let code = Int64(bitPattern: intFields[2] ?? 0)
        Log.line("[BLE] STA code=\(code)")

        // IP direkt vom Gerät erhalten → fertig
        if let ipData = strFields[5]?.first, let ip = String(data: ipData, encoding: .utf8), !ip.isEmpty {
            Log.line("[BLE] STA konfiguriert, IP: \(ip)")
            onConfigured?(ip)
            return
        }

        // SSID wird echoed zurück → Gerät hat Config akzeptiert, verbindet sich gerade.
        // Code < 0 bedeutet hier "pending" (z. B. -20 = DWARF-mini-spezifisch), kein Fehler.
        if let ssidData = strFields[3]?.first, let ssid = String(data: ssidData, encoding: .utf8), !ssid.isEmpty {
            Log.line("[BLE] STA akzeptiert (SSID=\(ssid), code=\(code)) → UDP-Discovery starten")
            onWifiAccepted?()
            return
        }

        // Echter Fehler: weder IP noch SSID zurück
        let realErrors: Set<Int> = [-1, -3, -4, -8, -9, -10]
        if realErrors.contains(Int(code)) {
            errorMessage = bleErrorMessage(Int(code))
        } else {
            // Unbekannter Code ohne SSID-Echo → trotzdem Discovery versuchen
            Log.line("[BLE] STA unbekannter Code \(code), starte Discovery")
            onWifiAccepted?()
        }
    }

    private func handleResWifilist(_ data: Data) {
        // ResWifilist: field 4 = repeated string ssid
        let fields = ProtoReader.messageFields(in: data)
        let ssids = (fields[4] ?? []).compactMap { String(data: $0, encoding: .utf8) }.filter { !$0.isEmpty }
        Log.line("[BLE] WLAN-Netze: \(ssids)")
        wifiNetworks = ssids
    }

    private func bleErrorMessage(_ code: Int) -> String {
        switch code {
        case -1: return "Falsches BLE-Passwort"
        case -5: return "WLAN wird konfiguriert…"
        case -8: return "WLAN-Passwort fehlt"
        case -9: return "Falsches WLAN-Passwort"
        case -10: return "SSID/Passwort konnte nicht gesetzt werden"
        default: return "Fehler \(code)"
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLESetup: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            if central.state != .poweredOn && state == .scanning {
                state = .failed
                errorMessage = "Bluetooth nicht verfügbar"
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            guard peripheral.name?.hasPrefix("DWARF") == true else { return }
            guard !foundDevices.contains(where: { $0.identifier == peripheral.identifier }) else { return }
            Log.line("[BLE] Gerät gefunden: \(peripheral.name ?? "?") (\(peripheral.identifier))")
            foundDevices.append(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            Log.line("[BLE] Verbunden mit \(peripheral.name ?? "?")")
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            state = .failed
            errorMessage = "Verbindung fehlgeschlagen: \(error?.localizedDescription ?? "unbekannt")"
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            Log.line("[BLE] Getrennt von \(peripheral.name ?? "?")")
            writeChar = nil
            notifyChar = nil
            if state == .connected { state = .idle }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLESetup: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            let all = peripheral.services ?? []
            Log.line("[BLE] Services: \(all.map { $0.uuid.uuidString })")
            guard let svc = all.first(where: { $0.uuid == svcUUID || $0.uuid == CBUUID(string: "FFE0") })
                           ?? all.first(where: { !$0.uuid.uuidString.hasPrefix("00001800") && !$0.uuid.uuidString.hasPrefix("00001801") })
            else {
                errorMessage = "Kein BLE-Service gefunden (Log prüfen)"
                state = .failed
                return
            }
            Log.line("[BLE] Verwende Service: \(svc.uuid.uuidString)")
            peripheral.discoverCharacteristics(nil, for: svc)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        MainActor.assumeIsolated {
            let chars = service.characteristics ?? []
            Log.line("[BLE] Characteristics: \(chars.map { "\($0.uuid.uuidString) props=\($0.properties.rawValue)" })")
            // DWARF 3: kombinierte 9999-Characteristic
            if let combined = chars.first(where: { $0.uuid == dwarfUUID }) {
                writeChar = combined
                notifyChar = combined
            } else {
                writeChar = chars.first(where: { $0.uuid == writeUUID })
                notifyChar = chars.first(where: { $0.uuid == notifyUUID })
            }
            guard writeChar != nil, let nc = notifyChar else {
                errorMessage = "Erforderliche BLE-Characteristics nicht gefunden"
                state = .failed
                return
            }
            peripheral.setNotifyValue(true, for: nc)
            Log.line("[BLE] Characteristics bereit (write=\(writeChar!.uuid), notify=\(nc.uuid))")
            state = .connected
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        MainActor.assumeIsolated {
            guard let data = characteristic.value, error == nil else { return }
            handleReceivedData(data)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didWriteValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        if let error {
            MainActor.assumeIsolated {
                Log.line("[BLE] Schreibfehler: \(error.localizedDescription)")
            }
        }
    }
}
