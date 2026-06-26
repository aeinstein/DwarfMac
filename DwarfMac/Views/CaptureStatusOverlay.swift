import SwiftUI

/// Dezente Status-/Fehlerzeile über dem Video: Aufnahme-Fortschritt, laufende
/// Belichtung und Geräte-Fehlertext aus den Notify-Meldungen.
struct CaptureStatusOverlay: View {
    let state: DeviceState

    var body: some View {
        VStack(spacing: 6) {
            if let kind = state.activeCapture {
                pill {
                    ProgressView().controlSize(.small)
                    Text(statusText(for: kind))
                }
            }
            if let total = state.exposureTotal, total > 0 {
                let elapsed = state.exposureElapsed ?? 0
                pill { Text("Belichtung: \(Int(elapsed))/\(Int(total)) s") }
            }
            if let err = state.lastErrorText {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(err).lineLimit(2)
                }
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.red.opacity(0.85), in: Capsule())
            }
        }
        .padding(8)
    }

    @ViewBuilder
    private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 6) { content() }
            .font(.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.black.opacity(0.5), in: Capsule())
    }

    private func statusText(for kind: CaptureKind) -> String {
        switch kind {
        case .recording:
            if let s = state.recordSeconds { return "Aufnahme läuft – \(s) s" }
            return "Aufnahme läuft …"
        case .burst:
            if let d = state.burstCompleted, let t = state.burstTotal { return "Serienfoto \(d)/\(t)" }
            return "Serienfoto läuft …"
        case .timelapse:
            return "Zeitraffer läuft …"
        case .stacking:
            if let n = state.stackedCount { return "Stacking – \(n) Frames" }
            return "Live-Stacking läuft …"
        }
    }
}
