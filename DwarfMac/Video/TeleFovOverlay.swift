import SwiftUI

/// Zeigt auf dem Weitwinkel-Stream ein grünes Rechteck, das den Bildausschnitt der
/// Telekamera markiert. Position und Größe sind hardcodiert (per Messung kalibriert).
struct TeleFovOverlay: View {
    private let offsetX = -0.006221973094170441
    private let offsetY =  0.011000000000000003
    private let fovW    =  0.028
    private let fovH    =  0.028

    var body: some View {
        GeometryReader { geo in
            let vw = geo.size.width
            let vh = geo.size.height
            let rw = vw * fovW
            let rh = vh * fovH
            let cx = vw * (0.5 + offsetX)
            let cy = vh * (0.5 + offsetY)

            Rectangle()
                .stroke(Color.green.opacity(0.85), lineWidth: 1.5)
                .frame(width: rw, height: rh)
                .position(x: cx, y: cy)
                .allowsHitTesting(false)
        }
    }
}
