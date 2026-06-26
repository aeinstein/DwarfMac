import SwiftUI

/// Zeigt auf dem Weitwinkel-Stream ein grünes Rechteck, das den Bildausschnitt der
/// Telekamera markiert. Größe und Position sind per Drag und Einstellungs-Popover
/// kalibrierbar; alle Werte werden in UserDefaults persistiert.
struct TeleFovOverlay: View {
    /// Horizontaler Mittelpunkt-Versatz (Anteil der View-Breite, −0,5 … 0,5).
    @AppStorage("teleFovOffsetX") private var storedX = 0.0
    /// Vertikaler Mittelpunkt-Versatz (Anteil der View-Höhe, −0,5 … 0,5).
    @AppStorage("teleFovOffsetY") private var storedY = 0.0
    /// Breite des Rechtecks als Anteil der View-Breite.
    @AppStorage("teleFovWidth")   private var fovW    = 0.18
    /// Höhe des Rechtecks als Anteil der View-Höhe.
    @AppStorage("teleFovHeight")  private var fovH    = 0.24
    /// Overlay ein-/ausblenden.
    @AppStorage("teleFovVisible") private var visible = true

    /// Laufender Drag-Versatz (nicht persistiert, nur während des Ziehens gesetzt).
    @State private var dragDelta: CGSize = .zero
    @State private var showCalib = false

    var body: some View {
        GeometryReader { geo in
            let vw = geo.size.width
            let vh = geo.size.height
            let rw = vw * max(0.02, fovW)
            let rh = vh * max(0.02, fovH)
            let cx = vw * (0.5 + storedX) + dragDelta.width
            let cy = vh * (0.5 + storedY) + dragDelta.height

            // Immer sichtbar wenn Overlay ausgeblendet – sonst gibt es kein Weg zurück.
            if !visible {
                Image(systemName: "eye.slash")
                    .font(.system(size: 9))
                    .foregroundStyle(.green.opacity(0.7))
                    .padding(3)
                    .background(.black.opacity(0.55), in: Circle())
                    .position(x: 14, y: 14)
                    .onTapGesture { visible = true }
                    .help("Tele-FOV-Rahmen wieder anzeigen")
            }

            if visible {
                ZStack {
                    // Grüner Rahmen — kein Fill, damit das Video dahinter anklickbar bleibt.
                    Rectangle()
                        .stroke(Color.green.opacity(0.85), lineWidth: 1.5)
                        .frame(width: rw, height: rh)
                        .position(x: cx, y: cy)
                        .allowsHitTesting(false)

                    // Zieh-Griff (oben links an der Ecke)
                    Image(systemName: "arrow.up.and.down.and.left.and.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.green)
                        .padding(3)
                        .background(.black.opacity(0.55), in: Circle())
                        .position(x: cx - rw / 2 - 1, y: cy - rh / 2 - 1)
                        .gesture(
                            DragGesture(minimumDistance: 2)
                                .onChanged { v in dragDelta = v.translation }
                                .onEnded { v in
                                    let nx = storedX + v.translation.width  / vw
                                    let ny = storedY + v.translation.height / vh
                                    storedX    = min(0.48, max(-0.48, nx))
                                    storedY    = min(0.48, max(-0.48, ny))
                                    dragDelta  = .zero
                                }
                        )
                        .help("Ziehen zum Verschieben des Tele-FOV-Rahmens")

                    // Einstellungs-Icon (oben rechts an der Ecke)
                    Image(systemName: "gearshape")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.green)
                        .padding(3)
                        .background(.black.opacity(0.55), in: Circle())
                        .position(x: cx + rw / 2 + 1, y: cy - rh / 2 - 1)
                        .onTapGesture { showCalib = true }
                        .popover(isPresented: $showCalib, arrowEdge: .top) {
                            calibrationPopover
                        }
                        .help("Tele-FOV-Rahmen kalibrieren")
                }
            }
        }
    }

    // MARK: – Kalibrierungs-Popover

    private var calibrationPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tele-FOV kalibrieren")
                .font(.headline)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Rahmengröße").font(.subheadline).foregroundStyle(.secondary)
                sliderRow("Breite", $fovW, 0.02...0.80) { "\(Int($0 * 100)) %" }
                sliderRow("Höhe",   $fovH, 0.02...0.80) { "\(Int($0 * 100)) %" }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Position (Feinabstimmung)").font(.subheadline).foregroundStyle(.secondary)
                sliderRow("Horizontal", $storedX, -0.48...0.48) {
                    let s = $0 >= 0 ? "+" : ""; return "\(s)\(Int($0 * 100)) %"
                }
                sliderRow("Vertikal",   $storedY, -0.48...0.48) {
                    let s = $0 >= 0 ? "+" : ""; return "\(s)\(Int($0 * 100)) %"
                }
                Text("Grob-Positionierung: Pfeil-Symbol im Kamerabild ziehen.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Toggle("Sichtbar", isOn: $visible)
                    .toggleStyle(.switch)
                    .labelsHidden()
                Text("Overlay anzeigen")
                    .font(.caption)
                Spacer()
                Button("Zurücksetzen") {
                    storedX = 0; storedY = 0; fovW = 0.18; fovH = 0.24; visible = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private func sliderRow(
        _ label: String,
        _ binding: Binding<Double>,
        _ range: ClosedRange<Double>,
        format: (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(label): \(format(binding.wrappedValue))").font(.caption)
            Slider(value: binding, in: range)
        }
    }
}
