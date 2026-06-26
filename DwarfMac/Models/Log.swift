import Foundation

/// Zentrales Logging: schreibt jede Zeile auf stdout UND in eine Datei
/// (`/Users/aeinstein/DwarfMac/dwarfmac.log`), damit die Logs auch außerhalb des
/// Terminals (z. B. zur Analyse) eingesehen werden können. Datei wird je App-Start
/// einmal geleert.
enum Log {
    static let fileURL = URL(fileURLWithPath: "/Users/aeinstein/DwarfMac/dwarfmac.log")

    private static let queue = DispatchQueue(label: "dwarfmac.log")

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    /// Leert die Logdatei (beim App-Start aufzurufen).
    static func reset() {
        queue.async {
            try? "=== DwarfMac Log gestartet ===\n".write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    static func line(_ message: String) {
        let stamped = "\(timeFormatter.string(from: Date())) \(message)"
        print(stamped)
        queue.async {
            guard let handle = try? FileHandle(forWritingTo: fileURL) else {
                // Datei existiert noch nicht → anlegen.
                try? (stamped + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
                return
            }
            handle.seekToEndOfFile()
            handle.write(Data((stamped + "\n").utf8))
            try? handle.close()
        }
    }
}
