import SwiftUI

/// Halbtransparentes Regler-Icon mittig im Hauptbild. Klick öffnet ein Panel mit
/// den Bildreglern (und im Expertenmodus zusätzlich Fokus/Filter/Belichtung/Gain)
/// über dem Video.
struct CameraSettingsOverlay: View {
    let conn: DeviceConnection
    let state: DeviceState

    @State private var expanded = false

    private var isConnected: Bool { conn.state == .connected }

    var body: some View {
        if expanded {
            panel
        } else {
            iconButton
        }
    }

    private var iconButton: some View {
        Button { expanded = true } label: {
            ZStack {
                Circle().fill(.ultraThinMaterial)
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)
        }
        .buttonStyle(.plain)
        .opacity(0.85)
        .disabled(!isConnected)
        .help("Bildeinstellungen")
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Bild").font(.headline)
                Spacer()
                Button { expanded = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            ScrollView {
                CameraSettingsPanel(conn: conn, state: state)
                    .padding(.trailing, 4)   // Platz für die Scroll-Leiste
            }
        }
        .padding(14)
        .frame(width: 340)
        .frame(maxHeight: 360)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .opacity(0.95)
        .padding(16)
        .disabled(!isConnected)
    }
}

/// Reine Regler-Inhalte + Befehls-Routing. Zielt immer auf die im Hauptbild gezeigte
/// Kamera (`captureCamera`). Werte werden sofort beim Loslassen/Ändern als Einzelbefehl
/// gesendet (gleiches Task-Muster wie DPadView).
///
/// WICHTIG: Der DWARF mini akzeptiert die DEDIZIERTEN Set-Befehle (SET_BRIGHTNESS,
/// SET_WB_*, …) und antwortet darauf. Der „Feature-Param"-Pfad (CMD…SET_FEATURE_PARAM
/// 10037), den der dekompilierte App-Code nutzt, lieferte am Gerät KEINE Antwort und
/// keine Wirkung — daher hier bewusst die dedizierten Befehle. Es gibt auch keine
/// Geräte-Spiegelung des Weißabgleichs (verursachte sporadisch ein blaues Bild).
struct CameraSettingsPanel: View {
    let conn: DeviceConnection
    let state: DeviceState

    @AppStorage("captureCamera")  private var captureCameraRaw = CameraTarget.tele.rawValue
    @AppStorage("captureType")    private var captureTypeRaw   = CaptureType.stacked.rawValue
    @AppStorage("expertMode")     private var expertMode = false

    // Persistenz pro Kamera (Backing Stores). Die UI-Regler lesen aus @State-Vars,
    // die snapParamsToCamera() beim Kamerawechsel neu befüllt.
    @AppStorage("teleExpManual")  private var teleExpManual  = false
    @AppStorage("teleExpIndex")   private var teleExpIndex   = 120
    @AppStorage("teleGainManual") private var teleGainManual = false
    @AppStorage("teleGainIndex")  private var teleGainIndex  = 60
    @AppStorage("teleIrCut")      private var irCut          = 0
    @AppStorage("teleWbMode")     private var teleWbMode     = 0
    @AppStorage("teleWbIndex")    private var teleWbIndex    = 0
    @AppStorage("teleBrightness") private var teleBrightness = 0.0
    @AppStorage("teleContrast")   private var teleContrast   = 0.0
    @AppStorage("teleHue")        private var teleHue        = 0.0
    @AppStorage("teleSaturation") private var teleSaturation = 0.0
    @AppStorage("teleSharpness")  private var teleSharpness  = 50.0

    @AppStorage("wideExpManual")  private var wideExpManual  = false
    @AppStorage("wideExpIndex")   private var wideExpIndex   = 120
    @AppStorage("wideGainIndex")  private var wideGainIndex  = 60
    @AppStorage("wideWbMode")     private var wideWbMode     = 0
    @AppStorage("wideWbIndex")    private var wideWbIndex    = 0
    @AppStorage("wideBrightness") private var wideBrightness = 0.0
    @AppStorage("wideContrast")   private var wideContrast   = 0.0
    @AppStorage("wideHue")        private var wideHue        = 0.0
    @AppStorage("wideSaturation") private var wideSaturation = 0.0
    @AppStorage("wideSharpness")  private var wideSharpness  = 50.0

    // Aktive UI-Werte (kamera-unabhängig; werden in snapParamsToCamera geladen).
    @State private var expManual  = false
    @State private var expIndex   = 120
    @State private var gainManual = false
    @State private var gainIndex  = 60
    @State private var wbMode     = 0
    @State private var wbIndex    = 0
    @State private var brightness = 0.0
    @State private var contrast   = 0.0
    @State private var hue        = 0.0
    @State private var saturation = 0.0
    @State private var sharpness  = 50.0

    @State private var focusDir: UInt32?

    /// Zielkamera = die im Hauptbild gezeigte Kamera.
    private var camera: CameraTarget { CameraTarget(rawValue: captureCameraRaw) ?? .tele }
    private var capture: CaptureType { CaptureType(rawValue: captureTypeRaw) ?? .stacked }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if expertMode {
                if camera == .tele { focusControl }
                if camera == .tele { filterControl }
                exposureControl
                gainControl
                Divider()
            }
            whiteBalanceControl
            imageSlider("Helligkeit", $brightness, -100...100) {
                if camera == .tele { teleBrightness = $0 } else { wideBrightness = $0 }
                setBrightness(Int32($0))
            }
            imageSlider("Kontrast", $contrast, -100...100) {
                if camera == .tele { teleContrast = $0 } else { wideContrast = $0 }
                setContrast(Int32($0))
            }
            imageSlider("Farbton", $hue, -180...180) {
                if camera == .tele { teleHue = $0 } else { wideHue = $0 }
                setHue(Int32($0))
            }
            imageSlider("Sättigung", $saturation, -100...100) {
                if camera == .tele { teleSaturation = $0 } else { wideSaturation = $0 }
                setSaturation(Int32($0))
            }
            imageSlider("Schärfe", $sharpness, 0...100) {
                if camera == .tele { teleSharpness = $0 } else { wideSharpness = $0 }
                setSharpness(Int32($0))
            }
        }
        .onAppear { snapParamsToCamera() }
        .onChange(of: captureCameraRaw) { _, _ in snapParamsToCamera() }
        // Gezielte Einzel-Sync wenn das Gerät via 15264 einen Wert meldet.
        // Kein globaler paramGeneration-Trigger (würde alle Schieberegler auf 0 reset-ten,
        // weil AppStorage-Defaults 0 sind solange das Gerät noch nicht alle Werte gemeldet hat).
        .onChange(of: state.teleBrightness) { _, v in
            guard camera == .tele, let v else { return }
            brightness = Double(v); teleBrightness = Double(v)
        }
        .onChange(of: state.teleContrast) { _, v in
            guard camera == .tele, let v else { return }
            contrast = Double(v); teleContrast = Double(v)
        }
        .onChange(of: state.teleSaturation) { _, v in
            guard camera == .tele, let v else { return }
            saturation = Double(v); teleSaturation = Double(v)
        }
        .onChange(of: state.teleHue) { _, v in
            guard camera == .tele, let v else { return }
            hue = Double(v); teleHue = Double(v)
        }
        .onChange(of: state.teleSharpness) { _, v in
            guard camera == .tele, let v else { return }
            sharpness = Double(v); teleSharpness = Double(v)
        }
        .onChange(of: state.wideBrightness) { _, v in
            guard camera == .wide, let v else { return }
            brightness = Double(v); wideBrightness = Double(v)
        }
        .onChange(of: state.wideContrast) { _, v in
            guard camera == .wide, let v else { return }
            contrast = Double(v); wideContrast = Double(v)
        }
        .onChange(of: state.wideSaturation) { _, v in
            guard camera == .wide, let v else { return }
            saturation = Double(v); wideSaturation = Double(v)
        }
        .onChange(of: state.wideHue) { _, v in
            guard camera == .wide, let v else { return }
            hue = Double(v); wideHue = Double(v)
        }
        .onChange(of: state.wideSharpness) { _, v in
            guard camera == .wide, let v else { return }
            sharpness = Double(v); wideSharpness = Double(v)
        }
        // Belichtung / Gain / IR-Cut (vom Gerät via 15264 gemeldet, paramId 1/2/13).
        .onChange(of: state.teleExposure) { _, v in
            guard camera == .tele, let v else { return }
            let snapped = Int(CameraParams.snap(Int32(v), to: CameraParams.exposures(for: .tele)))
            expIndex = snapped; teleExpIndex = snapped
        }
        .onChange(of: state.wideExposure) { _, v in
            guard camera == .wide, let v else { return }
            let snapped = Int(CameraParams.snap(Int32(v), to: CameraParams.exposures(for: .wide)))
            expIndex = snapped; wideExpIndex = snapped
        }
        .onChange(of: state.teleGain) { _, v in
            guard camera == .tele, let v else { return }
            let snapped = Int(CameraParams.snap(Int32(v), to: CameraParams.gains(for: .tele)))
            gainIndex = snapped; teleGainIndex = snapped
        }
        .onChange(of: state.wideGain) { _, v in
            guard camera == .wide, let v else { return }
            let snapped = Int(CameraParams.snap(Int32(v), to: CameraParams.gains(for: .wide)))
            gainIndex = snapped; wideGainIndex = snapped
        }
        .onChange(of: state.teleIrCut) { _, v in
            guard camera == .tele, let v else { return }
            irCut = v
        }
    }

    // MARK: Fokus

    // Fokus: Drücken-und-halten für kontinuierlichen Fokus (0=fern, 1=nah),
    // plus einmaliger bzw. Astro-Autofokus.
    private var focusControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Fokus").font(.headline)
                if let fv = state.focusValue {
                    Text("(\(fv))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if state.isAutoFocusing { ProgressView().controlSize(.small) }
            }
            HStack {
                focusButton("Fokus fern", direction: 0)
                focusButton("Fokus nah", direction: 1)
            }
            autoFocusButton
        }
    }

    /// Einmaliger Autofokus (Allgemein) bzw. Astro-Autofokus (StackedFoto, start/stop).
    @ViewBuilder
    private var autoFocusButton: some View {
        if capture == .stacked {
            Button(state.isAutoFocusing ? "Astro-Autofokus stoppen" : "Astro-Autofokus") {
                send(state.isAutoFocusing ? DwarfCommands.astroAutoFocusStop()
                                          : DwarfCommands.astroAutoFocusStart(mode: 0))
            }
            .buttonStyle(.bordered)
        } else {
            Button("Autofokus") { send(DwarfCommands.autoFocus()) }
                .buttonStyle(.bordered)
                .disabled(state.isAutoFocusing)
        }
    }

    private func focusButton(_ label: String, direction: UInt32) -> some View {
        Text(label)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(focusDir == direction ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard focusDir != direction else { return }
                        focusDir = direction
                        send(DwarfCommands.focusStartContinu(direction: direction))
                    }
                    .onEnded { _ in
                        focusDir = nil
                        send(DwarfCommands.focusStopContinu())
                    }
            )
    }

    // MARK: Filter / Belichtung / Verstärkung

    private var filterControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Filter").font(.headline)
            Picker("Filter", selection: $irCut) {
                Text("IR-Sperre").tag(0)
                Text("IR-Durchlass").tag(1)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .onChange(of: irCut) { _, new in send(DwarfCommands.teleSetIrCut(Int32(new))) }
        }
    }

    private var exposureControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Belichtung manuell", isOn: $expManual)
                .onChange(of: expManual) { _, on in
                    if camera == .tele { teleExpManual = on } else { wideExpManual = on }
                    setExpMode(on ? 1 : 0)
                    if on { setExp(index: Int32(expIndex)) }
                }
            if expManual {
                Picker("Belichtung", selection: $expIndex) {
                    ForEach(CameraParams.exposures(for: camera)) { e in
                        Text(e.label).tag(Int(e.value))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: expIndex) { _, new in
                    if camera == .tele { teleExpIndex = new } else { wideExpIndex = new }
                    setExp(index: Int32(new))
                }
            }
        }
    }

    /// Verstärkung. Telekamera hat einen Auto/Manuell-Modus, Weitwinkel sendet
    /// den Wert direkt (kein Gain-Mode-Befehl im Protokoll).
    @ViewBuilder
    private var gainControl: some View {
        if camera == .tele {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Verstärkung manuell", isOn: $gainManual)
                    .onChange(of: gainManual) { _, on in
                        teleGainManual = on
                        send(DwarfCommands.teleSetGainMode(on ? 1 : 0))
                        if on { send(DwarfCommands.teleSetGain(index: Int32(gainIndex))) }
                    }
                if gainManual { gainPicker }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Verstärkung").font(.headline)
                gainPicker
            }
        }
    }

    private var gainPicker: some View {
        Picker("Verstärkung", selection: $gainIndex) {
            ForEach(CameraParams.gains(for: camera)) { g in
                Text(g.label).tag(Int(g.value))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .onChange(of: gainIndex) { _, new in
            if camera == .tele { teleGainIndex = new } else { wideGainIndex = new }
            setGain(index: Int32(new))
        }
    }

    /// Lädt alle Regler-Werte der aktiven Kamera aus den Backing Stores (und
    /// aus DeviceState wenn bereits synchronisiert). Wird beim Kamerawechsel
    /// und bei eingehenden Param-Notifys (15264) aufgerufen.
    private func snapParamsToCamera() {
        let exps  = CameraParams.exposures(for: camera)
        let gains = CameraParams.gains(for: camera)
        if camera == .tele {
            expManual  = teleExpManual
            expIndex   = Int(CameraParams.snap(Int32(state.teleExposure ?? teleExpIndex), to: exps))
            gainManual = teleGainManual
            gainIndex  = Int(CameraParams.snap(Int32(state.teleGain ?? teleGainIndex), to: gains))
            if let ir = state.teleIrCut { irCut = ir }
            wbMode     = teleWbMode
            wbIndex    = teleWbIndex
            brightness = state.teleBrightness.map(Double.init) ?? teleBrightness
            contrast   = state.teleContrast.map(Double.init)   ?? teleContrast
            saturation = state.teleSaturation.map(Double.init) ?? teleSaturation
            hue        = state.teleHue.map(Double.init)        ?? teleHue
            sharpness  = state.teleSharpness.map(Double.init)  ?? teleSharpness
        } else {
            expManual  = wideExpManual
            expIndex   = Int(CameraParams.snap(Int32(state.wideExposure ?? wideExpIndex), to: exps))
            gainManual = false          // Weitwinkel hat keinen Manuell-Modus
            gainIndex  = Int(CameraParams.snap(Int32(state.wideGain ?? wideGainIndex), to: gains))
            wbMode     = wideWbMode
            wbIndex    = wideWbIndex
            brightness = state.wideBrightness.map(Double.init) ?? wideBrightness
            contrast   = state.wideContrast.map(Double.init)   ?? wideContrast
            saturation = state.wideSaturation.map(Double.init) ?? wideSaturation
            hue        = state.wideHue.map(Double.init)        ?? wideHue
            sharpness  = state.wideSharpness.map(Double.init)  ?? wideSharpness
        }
        snapWb()
    }

    // MARK: Weißabgleich + Bildregler

    private var whiteBalanceControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Weißabgleich").font(.headline)
            Picker("Weißabgleich-Modus", selection: $wbMode) {
                Text("Farbtemperatur").tag(0)
                Text("Szene").tag(1)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .onChange(of: wbMode) { _, new in
                // Auf gültigen Default des neuen Modus schnappen, dann senden.
                wbIndex = Int(new == 0 ? CameraParams.defaultWbColorTemp : CameraParams.defaultWbScene)
                if camera == .tele { teleWbMode = new } else { wideWbMode = new }
                sendWb()
            }
            Picker("Weißabgleich-Wert", selection: $wbIndex) {
                ForEach(wbMode == 0 ? CameraParams.wbColorTemps : CameraParams.wbScenes) { e in
                    Text(e.label).tag(Int(e.value))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .onChange(of: wbIndex) { _, _ in sendWb() }
        }
        .onAppear { snapWb() }
    }

    /// Weißabgleich via PARAM-Modul: Modus 0=Farbtemperatur→WBMode.MANUAL(1),
    /// 1=Szene→WBMode.SCENE(2); value = Farbtemperatur-Gear-Index bzw. Szenen-Index.
    private func sendWb() {
        if camera == .tele { teleWbMode = wbMode; teleWbIndex = wbIndex }
        else               { wideWbMode = wbMode; wideWbIndex = wbIndex }
        send(DwarfCommands.paramSetWb(mode: wbMode == 0 ? 1 : 2, value: Int32(wbIndex)))
    }

    /// Schnappt wbIndex beim Öffnen auf einen für den aktuellen Modus gültigen Wert.
    private func snapWb() {
        let entries = wbMode == 0 ? CameraParams.wbColorTemps : CameraParams.wbScenes
        if !entries.contains(where: { Int($0.value) == wbIndex }) {
            wbIndex = Int(wbMode == 0 ? CameraParams.defaultWbColorTemp : CameraParams.defaultWbScene)
        }
    }

    /// Einen Bildregler mit Beschriftung; sendet beim Loslassen den ganzzahligen Wert.
    private func imageSlider(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                             onCommit: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(label): \(Int(value.wrappedValue))").font(.caption)
            Slider(value: value, in: range, step: 1) { editing in
                if !editing { onCommit(value.wrappedValue) }
            }
        }
    }

    // MARK: Befehls-Routing nach Zielkamera

    private func setExpMode(_ mode: Int32) {
        send(camera == .tele ? DwarfCommands.teleSetExpMode(mode) : DwarfCommands.wideSetExpMode(mode))
    }
    private func setExp(index: Int32) {
        send(camera == .tele ? DwarfCommands.teleSetExp(index: index) : DwarfCommands.wideSetExp(index: index))
    }
    private func setGain(index: Int32) {
        send(camera == .tele ? DwarfCommands.teleSetGain(index: index) : DwarfCommands.wideSetGain(index: index))
    }
    private func setBrightness(_ ui: Int32) {
        send(camera == .tele ? DwarfCommands.teleSetBrightness(ui) : DwarfCommands.wideSetBrightness(ui))
    }
    private func setContrast(_ ui: Int32) {
        send(camera == .tele ? DwarfCommands.teleSetContrast(ui) : DwarfCommands.wideSetContrast(ui))
    }
    private func setHue(_ ui: Int32) {
        send(camera == .tele ? DwarfCommands.teleSetHue(ui) : DwarfCommands.wideSetHue(ui))
    }
    private func setSaturation(_ ui: Int32) {
        send(camera == .tele ? DwarfCommands.teleSetSaturation(ui) : DwarfCommands.wideSetSaturation(ui))
    }
    private func setSharpness(_ ui: Int32) {
        send(camera == .tele ? DwarfCommands.teleSetSharpness(ui) : DwarfCommands.wideSetSharpness(ui))
    }

    private func send(_ packet: Data) {
        Task {
            do {
                try await conn.send(packet)
            } catch {
                Log.line("[CameraSettingsPanel] Senden fehlgeschlagen: \(error)")
            }
        }
    }
}
