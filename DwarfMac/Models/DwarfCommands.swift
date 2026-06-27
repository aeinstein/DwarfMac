import Foundation

// Befehls-Builder: erzeugen jeweils einen fertig kodierten WsPacket-Binärframe.
// Das innere Payload wird mit ProtoWriter gebaut und in WsPacket.data gelegt.
//
// Neuen Befehl ergänzen: passenden DwarfCmd + Module wählen, inneres Payload
// gemäß src/proto/*.proto kodieren, in ein WsPacket packen, .encode().

enum DwarfCommands {

    // MARK: - Motor / Steuerkreuz (MODULE_MOTOR)

    /// Joystick: kontinuierliche Bewegung in Richtung `angle` (Grad, 0°=rechts,
    /// gegen den Uhrzeigersinn) mit `speed` (0–1). Payload:
    /// ReqMotorServiceJoystick { double vector_angle=1; double vector_length=2 }.
    static func joystick(angle: Double, speed: Double) -> Data {
        var p = ProtoWriter()
        p.double(1, angle)
        p.double(2, speed)
        return WsPacket(module: .motor, cmd: .stepMotorServiceJoystick, data: p.data).encode()
    }

    /// Joystick stoppen (leeres Payload).
    static func joystickStop() -> Data {
        WsPacket(module: .motor, cmd: .stepMotorServiceJoystickStop).encode()
    }

    // MARK: - Kameras

    /// Telekamera öffnen. ReqOpenCamera { bool binning=1; int32 rtsp_encode_type=2 }.
    static func openTeleCamera(binning: Bool = false, rtspEncodeType: Int32 = 0) -> Data {
        var p = ProtoWriter()
        p.bool(1, binning)
        p.int32(2, rtspEncodeType)
        return WsPacket(module: .cameraTele, cmd: .cameraTeleOpen, data: p.data).encode()
    }

    static func closeTeleCamera() -> Data {
        WsPacket(module: .cameraTele, cmd: .cameraTeleClose).encode()
    }

    static func openWideCamera(binning: Bool = false, rtspEncodeType: Int32 = 0) -> Data {
        var p = ProtoWriter()
        p.bool(1, binning)
        p.int32(2, rtspEncodeType)
        return WsPacket(module: .cameraWide, cmd: .cameraWideOpen, data: p.data).encode()
    }

    static func closeWideCamera() -> Data {
        WsPacket(module: .cameraWide, cmd: .cameraWideClose).encode()
    }

    /// Kamera-/Stream-Betrieb starten (Task-Center, neuere Geräte). Die echte App
    /// sendet dies, um die RTSP-Streams zu starten — `openCamera` allein reicht nicht.
    /// ReqEnterCamera { ClientParams client_param=3 { int32 encode_type=1 } }
    /// (encode_type 0=H264, 1=H265). Die echte App sendet 1 (H265) — passt zum
    /// RTSP-Stream ch0/stream0. client_param wird stets gesendet (auch leer).
    static func enterCamera(encodeType: Int32 = 1) -> Data {
        var cp = ProtoWriter()
        cp.int32(1, encodeType)              // bei 0 leer (proto3-Default)
        var p = ProtoWriter()
        p.message(3, cp.data)                // client_param immer präsent
        return WsPacket(module: .taskCenter, cmd: .enterCamera, data: p.data).encode()
    }

    /// Preview-Pipeline der Telekamera aktivieren. ReqSetPreviewQuality { uint32
    /// level=1; uint32 quality=2 }. Ohne das produziert das Gerät für eine Kamera
    /// KEINE RTP-Frames — die RTSP-Session verbindet, liefert aber kein Bild (VLC
    /// läuft in Buffering → Error). Die App sendet das nach `enterCamera` für beide
    /// Kameras (PCAP-verifiziert 2026-06-27).
    static func teleSetPreviewQuality(level: UInt32 = 1, quality: UInt32 = 0) -> Data {
        var p = ProtoWriter()
        if level > 0 { p.uint32(1, level) }      // proto3: 0 weglassen
        if quality > 0 { p.uint32(2, quality) }
        return WsPacket(module: .cameraTele, cmd: .cameraTeleSetPreviewQuality, data: p.data).encode()
    }

    /// Preview-Pipeline der Weitwinkelkamera aktivieren (sonst bleibt ch1 ohne Bild).
    static func wideSetPreviewQuality(level: UInt32 = 1, quality: UInt32 = 0) -> Data {
        var p = ProtoWriter()
        if level > 0 { p.uint32(1, level) }
        if quality > 0 { p.uint32(2, quality) }
        return WsPacket(module: .cameraWide, cmd: .cameraWideSetPreviewQuality, data: p.data).encode()
    }

    /// Kamera-/Stream-Betrieb aufsetzen wie die Handy-App: `enterCamera` plus
    /// Preview-Quality für BEIDE Kameras, damit Tele (ch0) UND Weitwinkel (ch1)
    /// tatsächlich Frames liefern. Reihenfolge beibehalten.
    static func startCameraStreams() -> [Data] {
        [enterCamera(),
         teleSetPreviewQuality(level: 1),
         wideSetPreviewQuality(level: 1)]
    }

    /// Master-/Kontroll-Lock übernehmen. `ReqsetMasterLock { bool lock=1 }`.
    /// Nötig, damit der DWARF mini Steuerbefehle (Parameter etc.) annimmt.
    static func setMaster(_ lock: Bool = true) -> Data {
        var p = ProtoWriter()
        p.bool(1, lock)
        return WsPacket(module: .system, cmd: .systemSetMaster, data: p.data).encode()
    }

    /// Geräte-Zustand inkl. Kamera-Parameter-Liste abfragen (leeres Payload).
    /// Die Antwort enthält die echten param_ids/Werte/Bereiche des Geräts.
    static func getDeviceStateInfo() -> Data {
        WsPacket(module: .taskCenter, cmd: .getDeviceStateInfo, data: Data()).encode()
    }

    // Diagnose-GETs (Modul Telekamera, leeres Payload): liefern aktuelle Werte/Skala,
    // um den richtigen Set-Pfad/­Wertebereich für den DWARF mini zu bestimmen.
    static func getTeleAllParams() -> Data {
        WsPacket(module: .cameraTele, cmd: .cameraTeleGetAllParams, data: Data()).encode()
    }
    static func getTeleAllFeatureParams() -> Data {
        WsPacket(module: .cameraTele, cmd: .cameraTeleGetAllFeatureParams, data: Data()).encode()
    }
    static func getTeleSystemWorkingState() -> Data {
        WsPacket(module: .cameraTele, cmd: .cameraTeleGetSystemWorkingState, data: Data()).encode()
    }

    /// Kameramodus wechseln (Task-Center). ReqSwitchShootingMode { int32 mode=1 }.
    static func switchShootingMode(_ mode: Int32) -> Data {
        var p = ProtoWriter()
        p.int32(1, mode)
        return WsPacket(module: .taskCenter, cmd: .switchShootingMode, data: p.data).encode()
    }

    /// Shooting-Technik wählen (Task-Center, cmd 16403). Bei Foto-Modi sendet die
    /// App das direkt nach `switchShootingMode`. ReqSwitchShootingTech { int32 tech=1 }.
    static func switchShootingTech(_ tech: Int32) -> Data {
        var p = ProtoWriter()
        p.int32(1, tech)
        return WsPacket(module: .taskCenter, cmd: .switchShootingTech, data: p.data).encode()
    }

    /// Astro-Belichtungszeit abfragen (cmd 11039). Bei Astro-Modi sendet die App das
    /// nach dem Moduswechsel. Feldwerte PCAP-verifiziert (protocol.md §18a):
    /// f1=f4=-1 (uint64-max), f2=f3=100, f6=Mode-ID.
    static func astroGetShootingTime(mode: Int32) -> Data {
        var p = ProtoWriter()
        p.uint64(1, .max)
        p.uint64(2, 100)
        p.uint64(3, 100)
        p.uint64(4, .max)
        p.int32(6, mode)
        return WsPacket(module: .astro, cmd: .astroGetShootingTime, data: p.data).encode()
    }

    /// Moduswechsel-Transaktion wie die Handy-App (protocol.md §18a):
    /// `SWITCH_SHOOTING_MODE` plus bei Astro-Modi (Milchstraße/Sternspuren) die
    /// Astro-Belichtungszeit-Query. Die Shooting-*Technik* (cmd 16403) hängt am
    /// Aufnahme-Typ, NICHT am Szene-Modus — dafür `switchShootingTech(_:)` separat
    /// senden (siehe `shootingTech(for:)`). Reihenfolge beibehalten.
    static func observingMode(_ mode: ObservingMode) -> [Data] {
        var packets = [switchShootingMode(mode.deviceMode)]
        if mode.isAstroMode {
            packets.append(astroGetShootingTime(mode: mode.deviceMode))
        }
        // Der Moduswechsel setzt die Preview-Pipelines zurück → erneut aktivieren,
        // sonst liefern die Streams (v. a. Wide) nach dem Wechsel keine Frames mehr.
        packets.append(teleSetPreviewQuality(level: 1))
        packets.append(wideSetPreviewQuality(level: 1))
        return packets
    }

    /// Shooting-Technik passend zum Aufnahme-Typ setzen (cmd 16403). Muss vor der
    /// jeweiligen Aufnahme gesendet werden — Serienfoto (BURST) wird sonst abgelehnt.
    static func shootingTech(for type: CaptureType) -> Data {
        switchShootingTech(type.shootingTech)
    }

    // MARK: - Telekamera: Aufnahme

    /// Einzelfoto. ReqPhoto {} (leer).
    static func telePhotograph() -> Data {
        WsPacket(module: .cameraTele, cmd: .cameraTelePhotograph).encode()
    }

    /// Stacked-Foto: Live-Stacking starten (leeres Payload, MODULE_ASTRO).
    static func astroStartLiveStacking() -> Data {
        WsPacket(module: .astro, cmd: .astroStartLiveStacking).encode()
    }

    static func astroStopLiveStacking() -> Data {
        WsPacket(module: .astro, cmd: .astroStopLiveStacking).encode()
    }

    /// Tele-Kamera nach dem Stacking zurück auf Live-Stream schalten (ReqGoLive, leer).
    static func astroGoLive() -> Data {
        WsPacket(module: .astro, cmd: .astroGoLive).encode()
    }

    /// Stacking-Preset-Liste vom Gerät abrufen (leeres Payload, antwortet mit cmd=11040).
    static func getStackingList() -> Data {
        WsPacket(module: .astro, cmd: .astroStackingList, data: Data()).encode()
    }

    /// Video aufnehmen. ReqStartRecord { int32 encode_type=1 } (0=H264, 1=H265).
    static func teleStartRecord(encodeType: Int32 = 0) -> Data {
        var p = ProtoWriter()
        p.int32(1, encodeType)
        return WsPacket(module: .cameraTele, cmd: .cameraTeleStartRecord, data: p.data).encode()
    }

    static func teleStopRecord() -> Data {
        WsPacket(module: .cameraTele, cmd: .cameraTeleStopRecord).encode()
    }

    /// Serienfoto. ReqBurstPhoto { int32 count=1 }.
    static func teleBurst(count: Int32) -> Data {
        var p = ProtoWriter()
        p.int32(1, count)
        return WsPacket(module: .cameraTele, cmd: .cameraTeleBurst, data: p.data).encode()
    }

    static func teleStopBurst() -> Data {
        WsPacket(module: .cameraTele, cmd: .cameraTeleStopBurst).encode()
    }

    /// Zeitraffer starten. ReqStartTimelapse { int32 interval=1; int32 count=2 }.
    /// interval = Sekunden zwischen Aufnahmen; count = Gesamtanzahl der Aufnahmen.
    static func teleStartTimelapse(interval: Int32 = 5, count: Int32 = 60) -> Data {
        var p = ProtoWriter()
        p.int32(1, interval)
        p.int32(2, count)
        return WsPacket(module: .cameraTele, cmd: .cameraTeleStartTimelapse, data: p.data).encode()
    }

    static func teleStopTimelapse() -> Data {
        WsPacket(module: .cameraTele, cmd: .cameraTeleStopTimelapse).encode()
    }

    // MARK: - Telekamera: Parameter
    //
    // Alle Set-Nachrichten tragen genau ein int32-Feld (Nr. 1). Belichtung/Gain/WB
    // nutzen Index- bzw. Mode-Rohwerte; die Bildregler erwarten einen 0–255-Wert,
    // den der Aufrufer aus dem UI-Bereich umrechnet (Formeln aus camera_tele.js).

    /// Belichtungsmodus: 0=Auto, 1=Manuell.
    static func teleSetExpMode(_ mode: Int32) -> Data {
        var p = ProtoWriter()
        p.int32(1, mode)
        return WsPacket(module: .cameraTele, cmd: .cameraTeleSetExpMode, data: p.data).encode()
    }

    /// Belichtungs-Index (nur bei manuellem Modus).
    static func teleSetExp(index: Int32) -> Data {
        var p = ProtoWriter()
        p.int32(1, index)
        return WsPacket(module: .cameraTele, cmd: .cameraTeleSetExp, data: p.data).encode()
    }

    /// Gain-Modus: 0=Auto, 1=Manuell.
    static func teleSetGainMode(_ mode: Int32) -> Data {
        var p = ProtoWriter()
        p.int32(1, mode)
        return WsPacket(module: .cameraTele, cmd: .cameraTeleSetGainMode, data: p.data).encode()
    }

    /// Gain-Index (nur bei manuellem Modus).
    static func teleSetGain(index: Int32) -> Data {
        var p = ProtoWriter()
        p.int32(1, index)
        return WsPacket(module: .cameraTele, cmd: .cameraTeleSetGain, data: p.data).encode()
    }

    /// IR-Filter: 0=CUT (IR-Sperre), 1=PASS.
    static func teleSetIrCut(_ value: Int32) -> Data {
        var p = ProtoWriter()
        p.int32(1, value)
        return WsPacket(module: .cameraTele, cmd: .cameraTeleSetIRCut, data: p.data).encode()
    }

    /// Weißabgleich-Modus: 0=Farbtemperatur, 1=Szene.
    static func teleSetWBMode(_ mode: Int32) -> Data {
        var p = ProtoWriter()
        p.int32(1, mode)
        return WsPacket(module: .cameraTele, cmd: .cameraTeleSetWBMode, data: p.data).encode()
    }

    /// Weißabgleich-Szene (Index).
    static func teleSetWBScene(_ value: Int32) -> Data {
        var p = ProtoWriter()
        p.int32(1, value)
        return WsPacket(module: .cameraTele, cmd: .cameraTeleSetWBScene, data: p.data).encode()
    }

    /// Weißabgleich-Farbtemperatur (Index).
    static func teleSetWBColorTemp(index: Int32) -> Data {
        var p = ProtoWriter()
        p.int32(1, index)
        return WsPacket(module: .cameraTele, cmd: .cameraTeleSetWBCT, data: p.data).encode()
    }

    // Bildregler UND Weißabgleich laufen beim DWARF mini über das globale PARAM-Modul
    // (CMD_PARAM_SET_*), NICHT über die dedizierten Kamera-cmds (die ignoriert der mini
    // stumm → blaues Bild). Die App sendet compound 64-bit param_ids:
    //   compound = 0x0101_0000_0000_0000 | (camera << 44) | paramId
    //   camera: 0 = Tele, 1 = Weitwinkel.
    // Tatsächliche paramId-Nummern (aus PCAP 2026-06-25 bestätigt):
    //   BRIGHTNESS=4, CONTRAST=5, SATURATION=6, HUE=7, SHARPNESS=8.
    // (ParamType.java gibt 3–7 an; das Gerät nutzt aber 4–8, bestätigt via Notify 15264.)
    // Werte: Helligkeit/Kontrast/Sättigung −100…100, Farbton −180…180, Schärfe 0…100.

    // Compound-Basis für param_id: Tele = 0x0101_0000_0000_0000, Wide = +2^44.
    private static let teleParamBase: UInt64 = 0x0101_0000_0000_0000
    private static let wideParamBase: UInt64 = 0x0101_1000_0000_0000

    /// ReqSetGeneralIntParam { param_id=1 (uint64); value=2 (int32) }, cmd 16703.
    static func paramSetGeneralInt(paramId: UInt64, value: Int32) -> Data {
        var p = ProtoWriter()
        p.uint64(1, paramId)
        p.int32(2, value)
        return WsPacket(module: .param, cmd: .paramSetGeneralIntParam, data: p.data).encode()
    }

    /// ReqSetWb { param_id=1 (uint64); mode=2 (int32); value=3 (int32) }, cmd 16702.
    /// WBMode: AUTO=0, MANUAL=1 (Farbtemperatur/Gear), SCENE=2.
    static func paramSetWb(mode: Int32, value: Int32) -> Data {
        var p = ProtoWriter()
        p.uint64(1, 2)        // param_id WB = 2
        p.int32(2, mode)
        p.int32(3, value)
        return WsPacket(module: .param, cmd: .paramSetWb, data: p.data).encode()
    }

    static func teleSetBrightness(_ ui: Int32) -> Data { paramSetGeneralInt(paramId: teleParamBase | 4, value: ui) }
    static func teleSetContrast(_ ui: Int32) -> Data   { paramSetGeneralInt(paramId: teleParamBase | 5, value: ui) }
    static func teleSetSaturation(_ ui: Int32) -> Data { paramSetGeneralInt(paramId: teleParamBase | 6, value: ui) }
    static func teleSetHue(_ ui: Int32) -> Data        { paramSetGeneralInt(paramId: teleParamBase | 7, value: ui) }
    static func teleSetSharpness(_ ui: Int32) -> Data  { paramSetGeneralInt(paramId: teleParamBase | 8, value: ui) }

    // MARK: - Weitwinkelkamera: Aufnahme & Parameter
    //
    // Gleiche Payload-Messages wie Tele (camera.proto), aber Modul .cameraWide.
    // Weitwinkel hat KEIN IR-Cut und KEINEN Gain-Mode; Bildregler nutzen dieselben
    // 0–255-Umrechnungen wie die Tele-Pendants.

    /// Einzelfoto. ReqPhoto {} (leer).
    static func widePhotograph() -> Data {
        WsPacket(module: .cameraWide, cmd: .cameraWidePhotograph).encode()
    }

    /// Video aufnehmen. ReqStartRecord { int32 encode_type=1 } (0=H264, 1=H265).
    static func wideStartRecord(encodeType: Int32 = 0) -> Data {
        var p = ProtoWriter()
        p.int32(1, encodeType)
        return WsPacket(module: .cameraWide, cmd: .cameraWideStartRecord, data: p.data).encode()
    }

    static func wideStopRecord() -> Data {
        WsPacket(module: .cameraWide, cmd: .cameraWideStopRecord).encode()
    }

    /// Serienfoto. ReqBurstPhoto { int32 count=1 }.
    static func wideBurst(count: Int32) -> Data {
        var p = ProtoWriter()
        p.int32(1, count)
        return WsPacket(module: .cameraWide, cmd: .cameraWideBurst, data: p.data).encode()
    }

    static func wideStopBurst() -> Data {
        WsPacket(module: .cameraWide, cmd: .cameraWideStopBurst).encode()
    }

    static func wideStartTimelapse(interval: Int32 = 5, count: Int32 = 60) -> Data {
        var p = ProtoWriter()
        p.int32(1, interval)
        p.int32(2, count)
        return WsPacket(module: .cameraWide, cmd: .cameraWideStartTimelapse, data: p.data).encode()
    }

    static func wideStopTimelapse() -> Data {
        WsPacket(module: .cameraWide, cmd: .cameraWideStopTimelapse).encode()
    }

    /// Belichtungsmodus: 0=Auto, 1=Manuell.
    static func wideSetExpMode(_ mode: Int32) -> Data {
        var p = ProtoWriter()
        p.int32(1, mode)
        return WsPacket(module: .cameraWide, cmd: .cameraWideSetExpMode, data: p.data).encode()
    }

    /// Belichtungs-Index (nur bei manuellem Modus).
    static func wideSetExp(index: Int32) -> Data {
        var p = ProtoWriter()
        p.int32(1, index)
        return WsPacket(module: .cameraWide, cmd: .cameraWideSetExp, data: p.data).encode()
    }

    /// Gain-Index (Weitwinkel ohne Auto/Manuell-Modus).
    static func wideSetGain(index: Int32) -> Data {
        var p = ProtoWriter()
        p.int32(1, index)
        return WsPacket(module: .cameraWide, cmd: .cameraWideSetGain, data: p.data).encode()
    }

    /// Weißabgleich-Modus: 0=Farbtemperatur, 1=Szene.
    static func wideSetWBMode(_ mode: Int32) -> Data {
        var p = ProtoWriter()
        p.int32(1, mode)
        return WsPacket(module: .cameraWide, cmd: .cameraWideSetWBMode, data: p.data).encode()
    }

    /// Weißabgleich-Szene (Index).
    static func wideSetWBScene(_ value: Int32) -> Data {
        var p = ProtoWriter()
        p.int32(1, value)
        return WsPacket(module: .cameraWide, cmd: .cameraWideSetWBScene, data: p.data).encode()
    }

    /// Weißabgleich-Farbtemperatur (Index).
    static func wideSetWBColorTemp(index: Int32) -> Data {
        var p = ProtoWriter()
        p.int32(1, index)
        return WsPacket(module: .cameraWide, cmd: .cameraWideSetWBCT, data: p.data).encode()
    }

    // Weitwinkel-Bildregler: gleiches PARAM-Modul, aber anderen Kamera-Prefix im compound-ID.
    static func wideSetBrightness(_ ui: Int32) -> Data { paramSetGeneralInt(paramId: wideParamBase | 4, value: ui) }
    static func wideSetContrast(_ ui: Int32) -> Data   { paramSetGeneralInt(paramId: wideParamBase | 5, value: ui) }
    static func wideSetSaturation(_ ui: Int32) -> Data { paramSetGeneralInt(paramId: wideParamBase | 6, value: ui) }
    static func wideSetHue(_ ui: Int32) -> Data        { paramSetGeneralInt(paramId: wideParamBase | 7, value: ui) }
    static func wideSetSharpness(_ ui: Int32) -> Data  { paramSetGeneralInt(paramId: wideParamBase | 8, value: ui) }

    // MARK: - Fokus (MODULE_FOCUS)

    /// Einzelschritt-Fokus. ReqManualSingleStepFocus { uint32 direction=1 } (0=fern, 1=nah).
    static func focusManualStep(direction: UInt32) -> Data {
        var p = ProtoWriter()
        p.uint32(1, direction)
        return WsPacket(module: .focus, cmd: .focusManualSingleStep, data: p.data).encode()
    }

    /// Kontinuierlichen Fokus starten (0=fern, 1=nah).
    static func focusStartContinu(direction: UInt32) -> Data {
        var p = ProtoWriter()
        p.uint32(1, direction)
        return WsPacket(module: .focus, cmd: .focusStartContinu, data: p.data).encode()
    }

    static func focusStopContinu() -> Data {
        WsPacket(module: .focus, cmd: .focusStopContinu).encode()
    }

    /// Einmaliger Autofokus. ReqNormalAutoFocus { uint32 mode=1; uint32 center_x=2;
    /// uint32 center_y=3 } (mode 0=global, 1=Bereich). Global → Mittenkoordinaten 0.
    static func autoFocus(mode: UInt32 = 0, centerX: UInt32 = 0, centerY: UInt32 = 0) -> Data {
        var p = ProtoWriter()
        p.uint32(1, mode)
        p.uint32(2, centerX)
        p.uint32(3, centerY)
        return WsPacket(module: .focus, cmd: .focusAutoFocus, data: p.data).encode()
    }

    /// Astro-Autofokus starten. ReqAstroAutoFocus { uint32 mode=1 } (0=langsam, 1=schnell).
    static func astroAutoFocusStart(mode: UInt32 = 0) -> Data {
        var p = ProtoWriter()
        p.uint32(1, mode)
        return WsPacket(module: .focus, cmd: .focusStartAstroAutoFocus, data: p.data).encode()
    }

    static func astroAutoFocusStop() -> Data {
        WsPacket(module: .focus, cmd: .focusStopAstroAutoFocus).encode()
    }

    // MARK: - System: Zeit & Standort

    /// Zeit des Mac-Systems an das Gerät senden.
    /// ReqSetTime { uint64 timestamp=1; int32 timezone_offset_hours=2 }.
    /// Feld 2 = varint (kein double) — PCAP bestätigt: phone sendet 2 für UTC+2.
    static func setTime() -> Data {
        let ts = UInt64(Date().timeIntervalSince1970)
        let offsetHours = Int32(round(Double(TimeZone.current.secondsFromGMT()) / 3600.0))
        var p = ProtoWriter()
        p.uint64(1, ts)
        p.int32(2, offsetHours)
        return WsPacket(module: .system, cmd: .systemSetTime, data: p.data).encode()
    }

    /// IANA-Zeitzone des Mac an das Gerät senden (z. B. "Europe/Berlin").
    /// ReqSetTimeZone { string timezone_name=1 } — PCAP: phone sendet String, kein Double.
    static func setTimezone() -> Data {
        var p = ProtoWriter()
        p.string(1, TimeZone.current.identifier)
        return WsPacket(module: .system, cmd: .systemSetTimeZone, data: p.data).encode()
    }

    /// Beobachterstandort senden (WGS84-Dezimalgrad).
    /// ReqSetLocation { double lat=1; lon=2; alt=3; bool enable=8 }.
    static func setLocation(lat: Double, lon: Double, alt: Double = 0) -> Data {
        var p = ProtoWriter()
        p.double(1, lat)
        p.double(2, lon)
        if alt != 0 { p.double(3, alt) }
        p.bool(8, true)
        return WsPacket(module: .system, cmd: .systemSetLocation, data: p.data).encode()
    }

    // MARK: - Astro: Kalibrierung & GoTo

    /// Kalibrierung starten. ReqStartCalibration { double lon=1; double lat=2 }.
    static func astroStartCalibration(lon: Double, lat: Double) -> Data {
        var p = ProtoWriter()
        p.double(1, lon)
        p.double(2, lat)
        return WsPacket(module: .astro, cmd: .astroStartCalibration, data: p.data).encode()
    }

    static func astroStopCalibration() -> Data {
        WsPacket(module: .astro, cmd: .astroStopCalibration).encode()
    }

    /// GoTo Deep-Sky-Objekt.
    /// ReqGotoDSO { double ra=1 (Stunden, 0–24); double dec=2 (Grad); string name=3; bool goto_only=4 }.
    static func astroGotoDSO(ra: Double, dec: Double, name: String, gotoOnly: Bool = false) -> Data {
        var p = ProtoWriter()
        p.double(1, ra)
        p.double(2, dec)
        p.string(3, name)
        if gotoOnly { p.bool(4, true) }
        return WsPacket(module: .astro, cmd: .astroStartGotoDSO, data: p.data).encode()
    }

    /// GoTo Sonnensystem-Objekt (Planeten, Sonne, Mond).
    /// ReqGotoSolarSystem { int32 index=1; double lon=2; double lat=3; string name=4 }.
    /// `index`: 0-basierter Planeten-Index (0=Merkur … 6=Neptun; Sonne/Mond gesondert).
    static func astroGotoSolarSystem(index: Int32, lon: Double, lat: Double, name: String) -> Data {
        var p = ProtoWriter()
        p.int32(1, index)
        p.double(2, lon)
        p.double(3, lat)
        p.string(4, name)
        return WsPacket(module: .astro, cmd: .astroStartGotoSolarSystem, data: p.data).encode()
    }

    static func astroStopGoto() -> Data {
        WsPacket(module: .astro, cmd: .astroStopGoto).encode()
    }

    // MARK: - RGB & Power (leere Payloads)

    static func reboot() -> Data {
        WsPacket(module: .rgbPower, cmd: .reboot).encode()
    }

    static func powerDown() -> Data {
        WsPacket(module: .rgbPower, cmd: .powerDown).encode()
    }

    static func ledRingOn() -> Data {
        WsPacket(module: .rgbPower, cmd: .rgbOpen).encode()
    }

    static func ledRingOff() -> Data {
        WsPacket(module: .rgbPower, cmd: .rgbClose).encode()
    }

    static func batteryIndicatorOn() -> Data {
        WsPacket(module: .rgbPower, cmd: .powerIndicatorOn).encode()
    }

    static func batteryIndicatorOff() -> Data {
        WsPacket(module: .rgbPower, cmd: .powerIndicatorOff).encode()
    }
}
