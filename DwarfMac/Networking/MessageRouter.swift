import Foundation

/// Dekodiert eingehende WsPackets und verteilt Notify-/Antwort-Meldungen an den DeviceState.
final class MessageRouter {
    private let deviceState: DeviceState

    /// Bereits geloggte unbekannte Notify-Codes (nur einmal pro Code ausgeben).
    private var loggedUnknown: Set<UInt32> = []

    init(deviceState: DeviceState) {
        self.deviceState = deviceState
    }

    func route(_ data: Data) {
        guard let packet = WsPacket.decode(data) else {
            Log.line("[MessageRouter] Kein gültiges WsPacket (\(data.count) Bytes)")
            return
        }

        deviceState.noteMessage(cmdId: packet.cmdId)

        // Geräte-Zustand (GET_DEVICE_STATE_INFO): Baum dumpen + in DeviceState spiegeln.
        if packet.cmdId == DwarfCmd.getDeviceStateInfo.rawValue {
            Log.line("[MessageRouter] DeviceStateInfo-Baum (type=\(packet.typeId)):\n" + ProtoReader.debugTree(packet.data))
            applyDeviceStateInfo(packet.data)
            return
        }

        // Stacking-Preset-Liste (cmd=11040): vor typeId-Dispatch abfangen.
        if packet.cmdId == DwarfCmd.astroStackingList.rawValue {
            applyStackingList(packet.data)
            return
        }

        // Diagnose-GET-Antworten (Kamera-Parameter): Baum dumpen, um Werte/Skala zu sehen.
        let diagCmds: Set<UInt32> = [
            DwarfCmd.cameraTeleGetAllParams.rawValue,
            DwarfCmd.cameraTeleGetAllFeatureParams.rawValue,
            DwarfCmd.cameraTeleGetSystemWorkingState.rawValue,
        ]
        if diagCmds.contains(packet.cmdId) {
            Log.line("[MessageRouter] GET cmd=\(packet.cmdId) (type=\(packet.typeId)) Baum:\n" + ProtoReader.debugTree(packet.data))
            return
        }

        // Antwort auf einen gesendeten Befehl: Fehlercode auswerten.
        if packet.typeId == MessageType.response.rawValue {
            handleResponse(packet)
            return
        }

        routeNotify(packet)
    }

    // MARK: - Befehls-Antworten

    private func handleResponse(_ packet: WsPacket) {
        // Antwort-Payloads tragen üblicherweise int32 code=1 (DwarfErrorCode; 0/OK
        // wird in proto3 weggelassen). Negativ = Fehler.
        let code = Int32(truncatingIfNeeded: ProtoReader.varintFields(in: packet.data)[1] ?? 0)
        deviceState.lastResponseCmd = packet.cmdId
        deviceState.lastResponseCode = code
        deviceState.lastErrorText = code < 0 ? Self.describeError(code) : nil
        // Diagnose: jede Befehls-Antwort loggen (cmd + code), um z. B. zu sehen,
        // ob das Gerät openCamera (10000/12000) annimmt oder ablehnt.
        Log.line("[MessageRouter] Antwort cmd=\(packet.cmdId) code=\(code)")
    }

    // MARK: - Geräte-Zustand (ResGetDeviceStateInfo)

    /// Spiegelt den echten Geräte-Zustand aus GET_DEVICE_STATE_INFO in den DeviceState.
    /// ResGetDeviceStateInfo { shooting_mode=1; tele_camera_state_info=2;
    ///   wide_camera_state_info=3; focus_motor_state_info=4; …; device_state_info=6 }.
    /// CameraStateInfo { exclusive_state=1; stream_type=2{type=1}; double h_fov=3;
    ///   double v_fov=4; resolution_width=5; resolution_height=6; cmos_temperature=7{temperature=…} }.
    private func applyDeviceStateInfo(_ data: Data) {
        let top = ProtoReader.messageFields(in: data)
        if let m = ProtoReader.varintFields(in: data)[1] {
            deviceState.shootingModeId = Int(Int32(truncatingIfNeeded: m))
        }
        if let tele = top[2]?.first { applyCameraStateInfo(tele, wide: false) }
        if let wide = top[3]?.first { applyCameraStateInfo(wide, wide: true) }
        if let focus = top[4]?.first, let pos = ProtoReader.varintFields(in: focus)[1] {
            deviceState.focusValue = Int(Int32(truncatingIfNeeded: pos))
        }
    }

    private func applyCameraStateInfo(_ data: Data, wide: Bool) {
        let v = ProtoReader.varintFields(in: data)
        let d = ProtoReader.doubleFields(in: data)
        let m = ProtoReader.messageFields(in: data)
        let excl = v[1].map { Int($0) }
        let streamType = m[2]?.first.flatMap { ProtoReader.varintFields(in: $0)[1] }.map { Int($0) }
        let temp = m[7]?.first.flatMap { ProtoReader.varintFields(in: $0)[1] }.map { Int(Int32(truncatingIfNeeded: $0)) }
        let width = v[5].map { Int($0) }
        let height = v[6].map { Int($0) }
        let res = (width != nil && height != nil) ? "\(width!)×\(height!)" : nil
        if wide {
            deviceState.wideExclusiveState = excl
            if let streamType, let old = deviceState.wideStreamType, streamType != old { deviceState.wideStreamReload += 1 }
            deviceState.wideStreamType = streamType
            deviceState.wideResolution = res
            if let t = temp { deviceState.wideTemperature = t }
        } else {
            deviceState.teleExclusiveState = excl
            if let streamType, let old = deviceState.teleStreamType, streamType != old { deviceState.teleStreamReload += 1 }
            deviceState.teleStreamType = streamType
            deviceState.teleResolution = res
            deviceState.teleHFov = d[3]
            deviceState.teleVFov = d[4]
            if let t = temp { deviceState.sensorTemperature = t }
        }
    }

    // MARK: - Stacking-Presets (ResNotifyLiveStackingList, cmd=11040)

    private func applyStackingList(_ data: Data) {
        let entries = ProtoReader.messageFields(in: data)[2] ?? []
        guard !entries.isEmpty else { return }  // field[3]=1 Status-Variant ignorieren
        var presets: [StackingPreset] = []
        for entry in entries {
            let sv = ProtoReader.varintFields(in: entry)
            let sm = ProtoReader.messageFields(in: entry)
            guard let id = sv[2].map({ Int($0) }),
                  let frames = sv[3].map({ Int($0) }) else { continue }
            let nameBytes = sm[1]?.first
            let name = nameBytes.flatMap { String(data: $0, encoding: .utf8) } ?? "\(id)"
            presets.append(StackingPreset(id: id, name: name, frames: frames))
        }
        guard !presets.isEmpty else { return }
        deviceState.stackingPresets = presets
        if deviceState.selectedStackingPresetId == nil {
            deviceState.selectedStackingPresetId = presets.first?.id
        }
        Log.line("[MessageRouter] Stacking-Presets: \(presets.map { "\($0.name)s/\($0.frames)×" })")
    }

    // MARK: - Notify-Verteilung

    private func routeNotify(_ packet: WsPacket) {
        let f = ProtoReader.varintFields(in: packet.data)

        switch DwarfCmd(rawValue: packet.cmdId) {

        // --- Telemetrie ---
        case .notifyBattery:
            if let pct = f[1] { deviceState.batteryPercent = Int(pct) }
        case .notifyCharge:
            if let c = f[1] { deviceState.isCharging = c != 0 }
        case .notifySdcardInfo:
            // ResNotifySDcardInfo { uint32 available_size=1; uint32 total_size=2; }
            if let avail = f[1], let total = f[2] {
                deviceState.sdAvailableGB = Int(avail)
                deviceState.sdTotalGB = Int(total)
            }
        case .notifyCmosTemperature:
            if let t = f[1] { deviceState.sensorTemperature = Int(Int32(truncatingIfNeeded: t)) }
            if let flag = f[2] { deviceState.sensorTemperatureAlert = flag != 0 }
        case .notifyTemperature:
            // ResNotifyTemperature { int32 code=1; int32 temperature=2; }
            if let t = f[2] { deviceState.systemTemperature = Int(Int32(truncatingIfNeeded: t)) }
        case .notifyPowerOff:
            deviceState.isPoweringOff = true

        // --- Aufnahme-Fortschritt (laufende Aktion) ---
        // Das DWARF mini sendet die generischen Codes (15285–15287); die
        // tele/wide-spezifischen sind für ältere/andere Geräte mit abgedeckt.
        case .notifyRecordTime, .notifyTeleRecordTime, .notifyWideRecordTime:
            // ResNotifyRecordTime { int32 record_time=1 } — kommt periodisch während der Aufnahme.
            deviceState.setCapture(.recording, active: true)
            if let s = f[1] { deviceState.recordSeconds = Int(Int32(truncatingIfNeeded: s)) }

        case .notifyBurstProgress, .notifyTeleBurstProgress, .notifyWideBurstProgress:
            // ResNotifyBurstProgress { uint32 total_count=1; uint32 completed_count=2 }
            let total = f[1].map { Int($0) }
            let done  = f[2].map { Int($0) }
            deviceState.burstTotal = total
            deviceState.burstCompleted = done
            // Abgeschlossen, sobald alle Bilder da sind.
            let finished = (total != nil && done != nil && done! >= total! && total! > 0)
            deviceState.setCapture(.burst, active: !finished)

        case .notifyTimelapseOutTime, .notifyTeleTimelapseOutTime, .notifyWideTimelapseOutTime:
            deviceState.setCapture(.timelapse, active: true)

        case .notifyLongExpProgress:
            // ResNotifyLongExpPhotoProgress { function_id=1; double total_time=2; double exposured_time=3 }
            let d = ProtoReader.doubleFields(in: packet.data)
            deviceState.exposureTotal = d[2]
            deviceState.exposureElapsed = d[3]

        case .notifyStreamType:
            // StreamType { int32 stream_type=1; int32 cam_id=2 } — das Gerät meldet
            // einen Stream-Wechsel (z. B. nach Moduswechsel). Betroffene Kamera
            // (cam_id 0=Tele, 1=Wide) neu verbinden lassen, aber nur bei echter
            // Änderung (sonst Reconnect-Thrash bei wiederholten Notifies).
            let streamType = f[1].map { Int(Int32(truncatingIfNeeded: $0)) }
            let camId = f[2].map { Int(Int32(truncatingIfNeeded: $0)) } ?? 0
            if camId == 1 {
                if let streamType, let old = deviceState.wideStreamType, streamType != old { deviceState.wideStreamReload += 1 }
                deviceState.wideStreamType = streamType
            } else {
                if let streamType, let old = deviceState.teleStreamType, streamType != old { deviceState.teleStreamReload += 1 }
                deviceState.teleStreamType = streamType
            }

        // --- Fokus / Autofokus ---
        case .notifyFocus:
            if let v = f[1] { deviceState.focusValue = Int(Int32(truncatingIfNeeded: v)) }
        case .notifyNormalAutoFocusState, .notifyAstroAutoFocusState, .notifyAstroAutoFocusFastState:
            if let raw = f[1], let s = OperationState(rawValue: Int(Int32(truncatingIfNeeded: raw))) {
                deviceState.isAutoFocusing = s.isActive
            }

        // --- Generisches Parameter-System (Diagnose) ---
        case .notifyGeneralIntParam:
            // ResNotifyGeneralIntParam { id=1 (uint64 compound); value=2 (int32) }
            let id = f[1] ?? 0
            let value = Int32(truncatingIfNeeded: f[2] ?? 0)
            Log.line("[MessageRouter] GeneralIntParam id=0x\(String(id, radix: 16)) value=\(value)")
            applyGeneralIntParam(paramId: id, value: value)
        case .notifyGeneralFloatParam, .notifyGeneralBoolParam, .notifyWaitShootingProgress,
             .notifyLowTempProtectionMode, .notifyExclusiveSystemIoTaskState,
             .notifyBodyStatus, .notifyHostSlaveMode:
            break   // bekannt, (noch) nicht ausgewertet

        case .notifySwitchShootingMode:
            if let m = f[1] { deviceState.shootingModeId = Int(Int32(truncatingIfNeeded: m)) }

        case .notifyWb:
            // ResNotifyParam { repeated CommonParam param=1 } — ersten Eintrag auswerten.
            // CommonParam { bool hasAuto=1; int32 auto_mode=2; int32 id=3;
            //               int32 mode_index=4; int32 index=5; double continue_value=6 }
            // Rohstruktur loggen (Diagnose: top-level Varints + ggf. eingebettete CommonParam).
            let topVarints = ProtoReader.varintFields(in: packet.data)
            Log.line("[MessageRouter] NotifyWB top-varints=\(topVarints) bytes=\(packet.data.map { String(format: "%02x", $0) }.joined())")
            if let first = ProtoReader.messageFields(in: packet.data)[1]?.first {
                let cp = ProtoReader.varintFields(in: first)
                Log.line("[MessageRouter] NotifyWB CommonParam=\(cp)")
                if let m = cp[4] { deviceState.wbMode = Int(Int32(truncatingIfNeeded: m)) }
                if let i = cp[5] { deviceState.wbIndex = Int(Int32(truncatingIfNeeded: i)) }
                deviceState.wbAuto = (cp[1] ?? 0) != 0
            }

        case .notifyProgressLiveStacking:
            // total_count=1, update_count_type=2, current_count=3, stacked_count=4, …
            deviceState.setCapture(.stacking, active: true)
            if let n = f[4] { deviceState.stackedCount = Int(Int32(truncatingIfNeeded: n)) }

        // --- Aufnahme-Status (OperationState; autoritatives Start/Stop) ---
        case .notifyStateLiveStacking:
            applyState(f[1], to: .stacking)
        case .notifyRecordState:
            applyState(f[1], to: .recording)
        case .notifyBurstState:
            applyState(f[1], to: .burst)
        case .notifyTimelapseState:
            applyState(f[1], to: .timelapse)
        case .notifyPhotoState:
            break   // Einzelfoto ist eine Einmal-Aktion ohne Lauf-Zustand

        // --- Astro GoTo / Kalibrierung ---
        case .notifyStateAstroCalibration:
            // ResNotifyAstroCalibration { AstroState state=1; int plate_solving_times=2 }
            if let raw = f[1] {
                deviceState.calibrationState = AstroState(rawValue: Int32(truncatingIfNeeded: raw)) ?? .idle
            }
            if let n = f[2] { deviceState.calibrationPlateSolvingTimes = Int(n) }

        case .notifyStateAstroGoto:
            // ResNotifyAstroGoto { AstroState state=1; string target_name=2 }
            if let raw = f[1] {
                deviceState.gotoState = AstroState(rawValue: Int32(truncatingIfNeeded: raw)) ?? .idle
            }
            if let nameData = ProtoReader.messageFields(in: packet.data)[2]?.first {
                deviceState.gotoTargetName = String(data: nameData, encoding: .utf8)
            }

        case .notifyStateAstroTracking, .notifyStateAstroTrackingSpecial:
            if let raw = f[1] {
                deviceState.trackingState = AstroState(rawValue: Int32(truncatingIfNeeded: raw)) ?? .idle
            }

        case .notifyStateAstroOneClickGoto, .notifyCalibrationResult:
            Log.line("[MessageRouter] Astro Notify cmd=\(packet.cmdId) data=\(ProtoReader.debugTree(packet.data))")

        default:
            logUnknownNotify(packet.cmdId)
        }
    }

    /// Überträgt einen OperationState-Wert auf die zugehörige Aufnahmeart.
    private func applyState(_ raw: UInt64?, to kind: CaptureKind) {
        guard let raw, let state = OperationState(rawValue: Int(Int32(truncatingIfNeeded: raw))) else { return }
        deviceState.setCapture(kind, active: state.isActive)
    }

    /// Mappt compound param_id → DeviceState-Param-Felder und inkrementiert paramGeneration.
    /// paramId: 1=Belichtung, 2=Gain, 4=Helligkeit, 5=Kontrast, 6=Sättigung,
    /// 7=Farbton, 8=Schärfe, 13=IR-Cut (filterType).
    private func applyGeneralIntParam(paramId compound: UInt64, value: Int32) {
        // Compound-Layout (dwarflab-sdk utils/param-id.ts):
        //   Bits 56–63 modeId · 48–55 sectionId · 44–47 cameraId · 0–15 paramId.
        // Modus/Section bewusst ignorieren — sonst greift die Spiegelung nur in
        // „Allgemein" (modeId 0x01) und nicht in DeepSky/Astro-Modi.
        let isTele = ((compound >> 44) & 0xf) == 0      // 0=Tele, 1=Weitwinkel
        let v = Int(value)
        var changed = true
        switch compound & 0xffff {
        case 1:  if isTele { deviceState.teleExposure   = v } else { deviceState.wideExposure   = v }  // angenommen, am Gerät prüfen
        case 2:  if isTele { deviceState.teleGain       = v } else { deviceState.wideGain       = v }  // angenommen, am Gerät prüfen
        case 4:  if isTele { deviceState.teleBrightness = v } else { deviceState.wideBrightness = v }
        case 5:  if isTele { deviceState.teleContrast   = v } else { deviceState.wideContrast   = v }
        case 6:  if isTele { deviceState.teleSaturation = v } else { deviceState.wideSaturation = v }
        case 7:  if isTele { deviceState.teleHue        = v } else { deviceState.wideHue        = v }
        case 8:  if isTele { deviceState.teleSharpness  = v } else { deviceState.wideSharpness  = v }
        case 13: if isTele { deviceState.teleIrCut      = v } else { deviceState.wideIrCut      = v }   // filterType
        default: changed = false
        }
        if changed { deviceState.paramGeneration += 1 }
    }

    /// Loggt einen noch nicht behandelten Notify-Code genau einmal (Geräte-Diagnose).
    private func logUnknownNotify(_ cmdId: UInt32) {
        guard (15200...15999).contains(cmdId), loggedUnknown.insert(cmdId).inserted else { return }
        Log.line("[MessageRouter] Unbehandeltes Notify cmd=\(cmdId)")
    }

    // MARK: - Fehlercodes (protocol.proto: DwarfErrorCode)

    static func describeError(_ code: Int32) -> String {
        switch code {
        case -1:     return "Protobuf-Parse-Fehler"
        case -2:     return "Keine SD-Karte"
        case -3:     return "Ungültiger Parameter"
        case -4:     return "SD-Karte: Schreibfehler"
        case -10504: return "Telekamera konnte nicht geöffnet werden"
        case -10506: return "Telekamera nimmt bereits auf"
        case -10507, -10511: return "Telekamera ist beschäftigt"
        case -11500: return "Plate-Solving fehlgeschlagen"
        case -11501: return "Astro-Funktion beschäftigt"
        case -11504: return "Kalibrierung fehlgeschlagen"
        case -11505: return "GoTo fehlgeschlagen"
        case -12503: return "Weitwinkelkamera konnte nicht geöffnet werden"
        case -12506: return "Weitwinkelkamera nimmt bereits auf"
        case -12508: return "Weitwinkel: Belichtung zu lang"
        case -13300: return "Zeit setzen fehlgeschlagen"
        case -14519: return "Motor: Endlage erreicht"
        case -14520: return "Motor muss zurückgesetzt werden"
        default:     return "Gerätefehler (Code \(code))"
        }
    }
}
