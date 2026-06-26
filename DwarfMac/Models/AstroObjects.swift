import Foundation
import SQLite3

struct AstroObject: Identifiable, Hashable {
    let id: Int
    let name: String
    let code: String       // z. B. "M 31"; leer für Planeten/Sterne ohne Katalogbezeichnung
    let ra: Double         // Rektaszension in Stunden (J2000), direkt aus DB
    let dec: Double        // Deklination in Grad (J2000)
    let mag: Double
    let category: String   // "planet", "star", "nebula", "galaxy", "cluster", "solar&lunar"
    let categoryInt: Int   // 1=solar&lunar, 2=planet, 3=star, 4=nebula, 5=galaxy, 6=cluster

    var isSolarSystem: Bool { categoryInt == 1 || categoryInt == 2 }

    var raFormatted: String {
        let h = Int(ra)
        let m = Int((ra - Double(h)) * 60)
        return "\(h)h\(String(format: "%02d", m))m"
    }

    var decFormatted: String {
        String(format: "%+.1f°", dec)
    }
}

@Observable
final class AstroDatabase {
    private(set) var objects: [AstroObject] = []

    init() { load() }

    private func load() {
        guard let url = Bundle.module.url(forResource: "astronomy_data", withExtension: "db") else {
            Log.line("[AstroDatabase] astronomy_data.db nicht im Bundle gefunden")
            return
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            Log.line("[AstroDatabase] Datenbankfehler: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT id, COALESCE(star_name,''), COALESCE(name_alias,''),
                   ra_j2000, dec_j2000, mag,
                   COALESCE(category,''), COALESCE(category_int,0)
            FROM astronomy_data ORDER BY category_int, mag
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        var result: [AstroObject] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id          = Int(sqlite3_column_int(stmt, 0))
            let name        = colText(stmt, 1)
            let code        = colText(stmt, 2)
            let ra          = sqlite3_column_double(stmt, 3)
            let dec         = sqlite3_column_double(stmt, 4)
            let mag         = sqlite3_column_double(stmt, 5)
            let category    = colText(stmt, 6)
            let categoryInt = Int(sqlite3_column_int(stmt, 7))
            result.append(AstroObject(
                id: id, name: name, code: code,
                ra: ra, dec: dec, mag: mag,
                category: category, categoryInt: categoryInt
            ))
        }
        objects = result
        Log.line("[AstroDatabase] \(result.count) Objekte geladen")
    }

    func search(_ query: String) -> [AstroObject] {
        guard !query.isEmpty else { return objects }
        let q = query.lowercased()
        return objects.filter {
            $0.name.lowercased().contains(q) || $0.code.lowercased().contains(q)
        }
    }
}

private func colText(_ stmt: OpaquePointer?, _ col: Int32) -> String {
    guard let ptr = sqlite3_column_text(stmt, col) else { return "" }
    return String(cString: ptr)
}
