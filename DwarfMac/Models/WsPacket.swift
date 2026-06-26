import Foundation

// WsPacket-Envelope (base.proto). Felder:
//   1 major_version, 2 minor_version, 3 device_id, 4 module_id,
//   5 cmd, 6 type, 7 data (inneres Payload), 8 client_id.

struct WsPacket {
    var module: Module
    var cmd: DwarfCmd
    var type: MessageType
    var data: Data

    /// Roh-Codes für eingehende Pakete (auch wenn Cmd/Module unbekannt sind).
    var moduleId: UInt32
    var cmdId: UInt32
    var typeId: UInt32

    init(module: Module, cmd: DwarfCmd, type: MessageType = .request, data: Data = Data()) {
        self.module = module
        self.cmd = cmd
        self.type = type
        self.data = data
        self.moduleId = module.rawValue
        self.cmdId = cmd.rawValue
        self.typeId = type.rawValue
    }

    private init(moduleId: UInt32, cmdId: UInt32, typeId: UInt32, data: Data) {
        self.moduleId = moduleId
        self.cmdId = cmdId
        self.typeId = typeId
        self.data = data
        self.module = Module(rawValue: moduleId) ?? .notify
        self.cmd = DwarfCmd(rawValue: cmdId) ?? .notifyBattery
        self.type = MessageType(rawValue: typeId) ?? .notification
    }

    /// Vollständiges WsPacket (Envelope) als Binär-Frame kodieren.
    func encode() -> Data {
        var w = ProtoWriter()
        w.uint32(1, DwarfProtocol.majorVersion)
        w.uint32(2, DwarfProtocol.minorVersion)
        w.uint32(3, DwarfProtocol.deviceId)
        w.uint32(4, moduleId)
        w.uint32(5, cmdId)
        w.uint32(6, typeId)
        w.bytes(7, data)
        w.string(8, DwarfProtocol.clientId)
        return w.data
    }

    /// Eingehendes WsPacket dekodieren (nur die für uns relevanten Felder).
    static func decode(_ bytes: Data) -> WsPacket? {
        var reader = ProtoReader(bytes)
        var moduleId: UInt32 = 0, cmdId: UInt32 = 0, typeId: UInt32 = 0
        var payload = Data()
        while !reader.isAtEnd {
            guard let (field, wire) = reader.readTag() else { return nil }
            switch (field, wire) {
            case (4, 0): moduleId = UInt32(truncatingIfNeeded: reader.readVarint() ?? 0)
            case (5, 0): cmdId = UInt32(truncatingIfNeeded: reader.readVarint() ?? 0)
            case (6, 0): typeId = UInt32(truncatingIfNeeded: reader.readVarint() ?? 0)
            case (7, 2): payload = reader.readBytes() ?? Data()
            default: reader.skip(wire)
            }
        }
        guard cmdId != 0 || moduleId != 0 else { return nil }
        return WsPacket(moduleId: moduleId, cmdId: cmdId, typeId: typeId, data: payload)
    }
}
