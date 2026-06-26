import Foundation

// Protokoll-Konstanten des Dwarf-Geräts (Protobuf über WebSocket, Port 9900).
// Quelle: https://github.com/aeinstein/dwarfii_api (Branch apiV2, src/proto/*).
//
// Jede Nachricht ist ein Protobuf-`WsPacket`-Envelope; das eigentliche
// kommando-spezifische Payload steckt protobuf-kodiert im `data`-Feld.
// Versendet werden BINÄRE WebSocket-Frames. Keepalive: Text-Frame "ping".

enum DwarfEndpoint {
    static let defaultIP = "192.168.88.1"

    // Video läuft über RTSP (DwarfMini/Dwarf 3), abgespielt via VLCKit:
    //   Teleobjektiv = ch0/stream0, Weitwinkel = ch1/stream0.
    //
    // WICHTIG: Die echte App verbindet mit ws://ip:9900/?client_id=<UUID>. Ohne
    // diesen Query-Parameter behandelt das Gerät die Verbindung nur als Beobachter
    // (Notifies kommen an, aber Steuerbefehle wie ENTER_CAMERA starten den Stream nicht).
    static func webSocket(ip: String = defaultIP) -> URL {
        URL(string: "ws://\(ip):9900/?client_id=\(DwarfProtocol.clientId)")!
    }
    static func telephotoStream(ip: String = defaultIP) -> URL { URL(string: "rtsp://\(ip):554/ch0/stream0")! }
    static func wideangleStream(ip: String = defaultIP) -> URL { URL(string: "rtsp://\(ip):554/ch1/stream0")! }
}

/// Feste Felder des WsPacket-Envelopes (aus createPacket / api_utils.js).
enum DwarfProtocol {
    static let majorVersion: UInt32 = 1   // WS_MAJOR_VERSION_NUMBER
    static let minorVersion: UInt32 = 9   // WS_MINOR_VERSION_NUMBER
    static let deviceId: UInt32 = 1       // DWARF II

    /// Feste Client-ID für die Verbindung zum DWARF mini.
    static let clientId = "0000DAF2-0000-1000-8000-00805F9B34FB"
}

/// Modul-IDs (protocol.proto: enum ModuleId).
enum Module: UInt32 {
    case cameraTele = 1
    case cameraWide = 2
    case astro = 3
    case system = 4
    case rgbPower = 5
    case motor = 6
    case track = 7
    case focus = 8
    case notify = 9
    case panorama = 10
    // ACHTUNG: Die App sendet als module_id den ORDINAL ihres WsModuleId-Enums,
    // nicht den protocol.proto-Wert. Wegen eines zusätzlichen MODULE_FACTORY_TEST
    // (Index 12) verschieben sich alle Module ab Index 13. Für TASK_CENTER ist der
    // gesendete Wert daher 14 (nicht der Proto-Wert 16). Module 0–10 sind lückenlos
    // und stimmen mit dem Proto überein.
    case taskCenter = 14
    // PARAM-Modul (Ordinal 15): der DWARF mini setzt Bildregler/Weißabgleich hierüber
    // (CMD_PARAM_SET_*, 16700–16706), NICHT über die dedizierten Kamera-cmds.
    case param = 15
}

/// Nachrichtentyp (protocol.proto: enum MessageTypeId).
enum MessageType: UInt32 {
    case request = 0
    case response = 1
    case notification = 2
    case notificationResponse = 3
}

/// Generischer Betriebszustand vieler Notify-Meldungen (notify.proto: OperationState).
enum OperationState: Int {
    case idle = 0, running = 1, stopping = 2, stopped = 3
    /// true, solange eine Aktion aktiv ist (idle/running) – stopping/stopped beenden sie.
    var isActive: Bool { self == .idle || self == .running }
}

/// Astro-spezifischer Zustand (notify.proto: AstroState). Unterscheidet sich von
/// OperationState durch den zusätzlichen `plateSolving`-Zustand.
enum AstroState: Int32 {
    case idle = 0, running = 1, stopping = 2, stopped = 3, plateSolving = 4
    var isActive: Bool { self == .running || self == .plateSolving }
}

/// Befehls-/Notify-Codes (protocol.proto: enum DwarfCMD) — nur die genutzten.
enum DwarfCmd: UInt32 {
    // Kamera (Tele/Weitwinkel)
    case cameraTeleOpen = 10000
    case cameraTeleClose = 10001
    case cameraWideOpen = 12000
    case cameraWideClose = 12001

    // Weitwinkel: Parameter (jeweils int32-Feld 1). Hinweis: Weitwinkel hat KEIN
    // IR-Cut und KEINEN Gain-Mode-Toggle (nur direkter SetGain).
    case cameraWideSetExpMode = 12002    // 0=Auto, 1=Manuell
    case cameraWideSetExp = 12004        // Belichtungs-Index
    case cameraWideSetGain = 12006       // Gain-Index (kein Mode)
    case cameraWideSetBrightness = 12008
    case cameraWideSetContrast = 12010
    case cameraWideSetSaturation = 12012
    case cameraWideSetHue = 12014
    case cameraWideSetSharpness = 12016
    case cameraWideSetWBMode = 12018     // 0=Farbtemperatur, 1=Szene
    case cameraWideSetWBCT = 12020       // Farbtemperatur-Index
    case cameraWideSetWBScene = 12035

    // Weitwinkel: Aufnahme
    case cameraWidePhotograph = 12022
    case cameraWideBurst = 12023
    case cameraWideStopBurst = 12024
    case cameraWideStartTimelapse = 12025
    case cameraWideStopTimelapse = 12026
    case cameraWideStartRecord = 12030
    case cameraWideStopRecord = 12031

    // Telekamera: Aufnahme
    case cameraTelePhotograph = 10002
    case cameraTeleBurst = 10003
    case cameraTeleStopBurst = 10004
    case cameraTeleStartRecord = 10005
    case cameraTeleStopRecord = 10006
    case cameraTeleStartTimelapse = 10033
    case cameraTeleStopTimelapse = 10034

    // Telekamera: Parameter (jeweils int32-Feld 1; Set/Get-Paare im Protokoll)
    case cameraTeleSetExpMode = 10007   // 0=Auto, 1=Manuell
    case cameraTeleSetExp = 10009       // Belichtungs-Index
    case cameraTeleSetGainMode = 10011  // 0=Auto, 1=Manuell
    case cameraTeleSetGain = 10013      // Gain-Index
    case cameraTeleSetBrightness = 10015
    case cameraTeleSetContrast = 10017
    case cameraTeleSetSaturation = 10019
    case cameraTeleSetHue = 10021
    case cameraTeleSetSharpness = 10023
    case cameraTeleSetWBMode = 10025    // 0=Farbtemperatur, 1=Szene
    case cameraTeleSetWBScene = 10027
    case cameraTeleSetWBCT = 10029      // Farbtemperatur-Index
    case cameraTeleSetIRCut = 10031     // 0=CUT (IR-Sperre), 1=PASS
    case cameraTeleSetAllParams = 10035 // ReqSetAllParams { exp_mode…sharpness, jpg_quality } (Sammelbefehl)
    case cameraTeleGetAllParams = 10036 // ResGetAllParams { repeated CommonParam all_params=1; code=2 }
    case cameraTeleSetFeatureParam = 10037  // CMD_CAMERA_TELE_SET_FEATURE_PARAM (ReqSetFeatureParams{CommonParam})
    case cameraTeleGetAllFeatureParams = 10038
    case cameraTeleGetSystemWorkingState = 10039

    // PARAM-Modul (DWARF mini): globale Parameter-Befehle. Bildregler/Weißabgleich
    // laufen hierüber — die dedizierten Kamera-cmds (10015 …) ignoriert der mini.
    case paramSetExposure = 16700        // ReqSetExposure { param_id=1, mode=2, value=3 }
    case paramSetGain = 16701            // ReqSetGain { param_id=1, mode=2, value=3 }
    case paramSetWb = 16702              // ReqSetWb { param_id=1, mode=2, value=3 }
    case paramSetGeneralIntParam = 16703 // ReqSetGeneralIntParam { param_id=1, value=2 }

    // Astro: Live-Stacking
    case astroStartLiveStacking = 11005
    case astroStopLiveStacking = 11006
    case astroGoLive = 11010          // CMD_ASTRO_GO_LIVE: Tele-Kamera zurück auf Live-Stream
    case astroStackingList = 11040    // C→D leer = Anfrage; D→C field[2] repeated = Preset-Liste

    // Fokus (MODULE_FOCUS)
    case focusAutoFocus = 15000          // ReqNormalAutoFocus { mode, center_x, center_y }
    case focusManualSingleStep = 15001  // direction: 0=fern, 1=nah
    case focusStartContinu = 15002
    case focusStopContinu = 15003
    case focusStartAstroAutoFocus = 15004 // ReqAstroAutoFocus { mode: 0=langsam, 1=schnell }
    case focusStopAstroAutoFocus = 15005

    // System: Zeit & Standort (MODULE_SYSTEM)
    case systemSetTime = 13000        // ReqSetTime { uint64 timestamp=1; int32 timezone_offset_hours=2 } (Feld 2 = varint, kein double)
    case systemSetTimeZone = 13001    // ReqSetTimeZone { string timezone_name=1 } (PCAP: "Europe/Berlin", kein double)
    case systemSetLocation = 13010    // ReqSetLocation { double lat=1; lon=2; alt=3; string country=4; province=5; city=6; district=7; bool enable=8 }

    // System: Master-/Kontroll-Lock. Nur der „Master"-Client darf Parameter ändern;
    // ohne diesen Lock ignoriert der DWARF mini Steuerbefehle still.
    case systemSetMaster = 13004      // ReqsetMasterLock { bool lock=1 }

    // Astro: Kalibrierung & GoTo (MODULE_ASTRO)
    case astroStartCalibration = 11000  // ReqStartCalibration { double lon=1; double lat=2 }
    case astroStopCalibration = 11001   // (leer)
    case astroStartGotoDSO = 11002      // ReqGotoDSO { double ra=1 (Stunden!); double dec=2 (Grad); string name=3; bool goto_only=4 }
    case astroStartGotoSolarSystem = 11003 // ReqGotoSolarSystem { int32 index=1; double lon=2; double lat=3; string name=4; bool force_start=5 }
    case astroStopGoto = 11004          // (leer)
    case astroStartTrackSpecialTarget = 11011 // (Proto TBD)
    case astroStopTrackSpecialTarget = 11012  // (leer)

    // RGB & Power
    case powerDown = 13502
    case reboot = 13505

    // Task-Center (Global Task Manager) — neuere Geräte (DWARF mini/3) starten
    // hierüber den Kamera-/Stream-Betrieb. openCamera allein genügt NICHT.
    case startTask = 16400            // CMD_GLOBAL_TASK_MANAGER_START_TASK
    case stopTask = 16401             // CMD_GLOBAL_TASK_MANAGER_STOP_TASK
    case switchShootingMode = 16402   // CMD_GLOBAL_TASK_MANAGER_SWITCH_SHOOTING_MODE
    case enterCamera = 16404          // CMD_GLOBAL_TASK_MANAGER_ENTER_CAMERA
    case getDeviceStateInfo = 16405   // CMD_GLOBAL_TASK_GET_DEVICE_STATE_INFO (liefert Param-Liste mit echten ids)

    // Motor / Joystick (Steuerkreuz)
    case stepMotorRun = 14000
    case stepMotorStop = 14002
    case stepMotorServiceJoystick = 14006
    case stepMotorServiceJoystickStop = 14008

    // Notify (eingehend)
    case notifyBattery = 15201        // CMD_NOTIFY_ELE
    case notifyCharge = 15202         // CMD_NOTIFY_CHARGE (Ladezustand)
    case notifySdcardInfo = 15203     // CMD_NOTIFY_SDCARD_INFO
    case notifyTemperature = 15243    // CMD_NOTIFY_TEMPERATURE (Werk/Movement)
    case notifyCmosTemperature = 15292 // CMD_NOTIFY_CMOS_TEMPERATURE (Sensor)
    case notifyPowerOff = 15229       // CMD_NOTIFY_POWER_OFF

    // Notify: Aufnahme-Fortschritt (gerätegeführt)
    case notifyTeleRecordTime = 15204         // ResNotifyRecordTime { int32 record_time=1 }
    case notifyTeleTimelapseOutTime = 15205   // ResNotifyTimeLapseOutTime { interval=1, out_time=2, total_time=3 }
    case notifyStateLiveStacking = 15208      // CMD_NOTIFY_STATE_CAPTURE_RAW_LIVE_STACKING
    case notifyProgressLiveStacking = 15209   // total_count=1 … stacked_count=4 …
    case notifyTeleBurstProgress = 15218      // ResNotifyBurstProgress { total_count=1, completed_count=2 }
    case notifyWideBurstProgress = 15220
    case notifyWideTimelapseOutTime = 15226
    case notifyWideRecordTime = 15235

    // Notify: Aufnahme-Status (OperationState; neuere Firmware/Dwarf3)
    case notifyPhotoState = 15273
    case notifyBurstState = 15274
    case notifyRecordState = 15275
    case notifyTimelapseState = 15276

    // Notify: generische Fortschritts-Codes — diese sendet das DWARF mini
    // tatsächlich (statt der tele/wide-spezifischen 15204/15218/15235).
    case notifyStreamType = 15234         // CMD_NOTIFY_STREAM_TYPE (beim Kamerastart)
    case notifyBurstProgress = 15285      // ResNotifyBurstProgress
    case notifyRecordTime = 15286         // ResNotifyRecordTime
    case notifyTimelapseOutTime = 15287   // ResNotifyTimeLapseOutTime
    case notifyLongExpProgress = 15288    // ResNotifyLongExpPhotoProgress { function_id=1, total_time=2, exposured_time=3 }

    // Notify: Fokus
    case notifyFocus = 15257              // ResNotifyFocus { int32 focus=1 } (Fokusposition)
    case notifyAstroAutoFocusState = 15278
    case notifyNormalAutoFocusState = 15279
    case notifyAstroAutoFocusFastState = 15280

    // Notify: generisches Parameter-System (das DWARF mini meldet hierüber u. a.
    // Fokus/Belichtung). ResNotifyGeneral*Param { id=1; value=2 }.
    case notifyWaitShootingProgress = 15255
    case notifyGeneralIntParam = 15264
    case notifyGeneralFloatParam = 15265
    case notifyGeneralBoolParam = 15266
    case notifySwitchShootingMode = 15267  // aktueller Kameramodus (nach ENTER_CAMERA)
    case notifyWb = 15270                  // CMD_NOTIFY_WB: ResNotifyParam { repeated CommonParam param=1 }

    // Notify: Astro GoTo / Kalibrierung (MODULE_ASTRO via NOTIFY)
    case notifyStateAstroCalibration = 15210   // ResNotifyAstroCalibration { AstroState state=1; int plate_solving_times=2 }
    case notifyStateAstroGoto = 15211          // ResNotifyAstroGoto { AstroState state=1; string target_name=2 }
    case notifyStateAstroTracking = 15212      // ResNotifyAstroTracking { AstroState state=1 }
    case notifyStateAstroTrackingSpecial = 15228
    case notifyStateAstroOneClickGoto = 15233  // OneOf-Composite (vorerst nur loggen)
    case notifyCalibrationResult = 15256       // (vorerst nur loggen)

    // Weitere bekannte Status-Notifies (nicht ausgewertet, nur bekannt)
    case notifyLowTempProtectionMode = 15260
    case notifyExclusiveSystemIoTaskState = 15261  // exklusiver System-IO-Task (Belegung)
    case notifyBodyStatus = 15262
    case notifyHostSlaveMode = 15223               // Host/Slave-Kontrollstatus
}
