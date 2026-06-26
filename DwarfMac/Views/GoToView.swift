import SwiftUI

struct GoToView: View {
    let conn: DeviceConnection
    let state: DeviceState
    let location: LocationManager
    let database: AstroDatabase

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedId: Int?

    @AppStorage("observerLat") private var observerLat = 0.0
    @AppStorage("observerLon") private var observerLon = 0.0

    private var displayLat: Double { location.lat ?? observerLat }
    private var displayLon: Double { location.lon ?? observerLon }
    private var hasLocation: Bool   { location.lat != nil || (observerLat != 0 || observerLon != 0) }

    private var selectedObject: AstroObject? {
        guard let id = selectedId else { return nil }
        return database.objects.first { $0.id == id }
    }

    private var filteredObjects: [AstroObject] { database.search(searchText) }

    private var categoryGroups: [(Int, [AstroObject])] {
        let grouped = Dictionary(grouping: filteredObjects, by: \.categoryInt)
        return [1, 2, 3, 4, 5, 6].compactMap { k in
            guard let v = grouped[k], !v.isEmpty else { return nil }
            return (k, v)
        }
    }

    private func categoryLabel(_ catInt: Int) -> String {
        switch catInt {
        case 1: return "Sonne & Mond"
        case 2: return "Planeten"
        case 3: return "Sterne"
        case 4: return "Nebel"
        case 5: return "Galaxien"
        case 6: return "Sternhaufen"
        default: return "Sonstige"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            locationBar
            Divider()
            searchBar
            Divider()
            objectList
            Divider()
            controlPanel
        }
        .frame(minWidth: 500, minHeight: 620)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "scope")
                .foregroundStyle(.tint)
            Text("GoTo")
                .font(.headline)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var locationBar: some View {
        HStack(spacing: 10) {
            Image(systemName: location.lat != nil ? "location.fill" : "location.slash")
                .foregroundStyle(location.lat != nil ? .green : .secondary)
                .font(.caption)
            if displayLat != 0 || displayLon != 0 {
                Text(String(format: "%.4f°N  %.4f°E", displayLat, displayLon))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("Kein Standort – bitte in Einstellungen eingeben")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
            Button("Aktualisieren") { location.requestOnce() }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.mini)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField("Suche …", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 7)
    }

    private var objectList: some View {
        List(selection: $selectedId) {
            ForEach(categoryGroups, id: \.0) { catInt, objs in
                Section(categoryLabel(catInt)) {
                    ForEach(objs) { obj in
                        ObjectRow(obj: obj)
                            .tag(obj.id)
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private var controlPanel: some View {
        VStack(spacing: 8) {
            // Ausgewähltes Objekt
            if let obj = selectedObject {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(obj.name).font(.callout.bold())
                        if !obj.code.isEmpty {
                            Text(obj.code).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("RA \(obj.raFormatted)  Dec \(obj.decFormatted)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if obj.mag != 0 {
                            Text("mag \(String(format: "%.1f", obj.mag))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.horizontal)
            }

            // Kalibrierung + GoTo
            HStack(spacing: 10) {
                Button("Kalibrieren") { startCalibration() }
                    .buttonStyle(.bordered)
                    .disabled(!hasLocation)

                Text(calibrationStatusText)
                    .font(.caption)
                    .foregroundStyle(calibrationStatusColor)
                    .frame(maxWidth: .infinity, alignment: .center)

                Button("GoTo starten") { startGoto() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedObject == nil || state.gotoState.isActive)

                if state.gotoState.isActive || state.calibrationState.isActive {
                    Button("Abbrechen") { cancel() }
                        .buttonStyle(.bordered)
                        .tint(.red)
                }
            }
            .padding(.horizontal)

            // GoTo-Status
            if state.gotoState != .idle || state.gotoState == .stopped {
                HStack(spacing: 4) {
                    Image(systemName: gotoStatusIcon)
                        .foregroundStyle(gotoStatusColor)
                    Text(gotoStatusText)
                        .font(.caption)
                        .foregroundStyle(gotoStatusColor)
                }
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - Status-Texte

    private var calibrationStatusText: String {
        switch state.calibrationState {
        case .idle:        return "Bereit"
        case .running:     return "Kalibriert …"
        case .plateSolving:
            let n = state.calibrationPlateSolvingTimes
            return n > 0 ? "Plate-Solving (\(n)×)" : "Plate-Solving …"
        case .stopping, .stopped: return "Kalibrierung fertig"
        }
    }

    private var calibrationStatusColor: Color {
        switch state.calibrationState {
        case .idle:                return .secondary
        case .running, .plateSolving: return .orange
        case .stopping, .stopped: return .green
        }
    }

    private var gotoStatusText: String {
        switch state.gotoState {
        case .idle:        return ""
        case .running:
            if let n = state.gotoTargetName, !n.isEmpty { return "GoTo: \(n) …" }
            return "GoTo läuft …"
        case .plateSolving: return "Plate-Solving …"
        case .stopping:    return "Wird gestoppt …"
        case .stopped:     return "GoTo abgeschlossen"
        }
    }

    private var gotoStatusIcon: String {
        switch state.gotoState {
        case .running, .plateSolving: return "arrow.triangle.2.circlepath"
        case .stopped:                return "checkmark.circle"
        default:                      return "scope"
        }
    }

    private var gotoStatusColor: Color {
        switch state.gotoState {
        case .running, .plateSolving: return .orange
        case .stopped:                return .green
        default:                      return .secondary
        }
    }

    // MARK: - Aktionen

    private func send(_ packet: Data) {
        Task {
            do {
                try await conn.send(packet)
            } catch {
                Log.line("[GoToView] Senden fehlgeschlagen: \(error)")
            }
        }
    }

    private func startCalibration() {
        send(DwarfCommands.setTime())
        send(DwarfCommands.setLocation(lat: displayLat, lon: displayLon, alt: location.altitude))
        send(DwarfCommands.astroStartCalibration(lon: displayLon, lat: displayLat))
    }

    private func startGoto() {
        guard let obj = selectedObject else { return }
        if obj.isSolarSystem {
            send(DwarfCommands.astroGotoSolarSystem(
                index: Int32(obj.id - 1),
                lon: displayLon,
                lat: displayLat,
                name: obj.name
            ))
        } else {
            send(DwarfCommands.astroGotoDSO(ra: obj.ra, dec: obj.dec, name: obj.name))
        }
    }

    private func cancel() {
        if state.gotoState.isActive {
            send(DwarfCommands.astroStopGoto())
        } else if state.calibrationState.isActive {
            send(DwarfCommands.astroStopCalibration())
        }
    }
}

// MARK: - Objektzeile

private struct ObjectRow: View {
    let obj: AstroObject

    var body: some View {
        HStack(spacing: 0) {
            Text(obj.code)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            Text(obj.name)
                .font(.callout)
            Spacer()
            Text(obj.raFormatted)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .trailing)
            Text(obj.decFormatted)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .trailing)
            Group {
                if obj.mag != 0 {
                    Text(String(format: "%.1f", obj.mag))
                } else {
                    Text("")
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.tertiary)
            .frame(width: 36, alignment: .trailing)
        }
    }
}
