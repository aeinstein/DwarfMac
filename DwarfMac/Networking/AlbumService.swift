import Foundation

enum AlbumService {
    private struct APIResponse<T: Decodable>: Decodable {
        let data: T?
        let code: Int
    }

    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()

    static func fetchCounts(host: String) async throws -> [MediaCount] {
        let resp: APIResponse<[MediaCount]> = try await post(host: host, path: "/album/list/mediaCounts", body: EmptyBody())
        return resp.data ?? []
    }

    static func fetchItems(host: String, mediaType: Int, page: Int, pageSize: Int = 50) async throws -> [MediaItem] {
        struct Body: Encodable { let mediaType: Int; let pageIndex: Int; let pageSize: Int }
        let resp: APIResponse<[MediaItem]> = try await post(host: host, path: "/album/list/mediaInfos",
                                                            body: Body(mediaType: mediaType, pageIndex: page, pageSize: pageSize))
        return resp.data ?? []
    }

    static func deleteItems(host: String, items: [MediaItem]) async throws {
        struct Row: Encodable { let mediaType: Int; let filePath: String; let fileName: String; let subType: Int }
        struct Body: Encodable { let datas: [Row] }
        let rows = items.map { Row(mediaType: $0.mediaType, filePath: $0.filePath, fileName: $0.fileName, subType: 0) }
        let _: APIResponse<[String: String]> = try await post(host: host, path: "/album/delete", body: Body(datas: rows))
    }

    /// HTTP-URL für eine Gerätedatei (Thumbnail oder Original).
    static func url(host: String, devicePath: String) -> URL? {
        let p = devicePath.hasPrefix("/") ? devicePath : "/\(devicePath)"
        // Jeden Pfadsegment einzeln enkodieren, Slashes behalten.
        let encoded = p.components(separatedBy: "/")
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0 }
            .joined(separator: "/")
        return URL(string: "http://\(host)\(encoded)")
    }

    // MARK: - Private

    private struct EmptyBody: Encodable {}

    private static func post<Body: Encodable, Response: Decodable>(
        host: String, path: String, body: Body
    ) async throws -> Response {
        let url = URL(string: "http://\(host):8082\(path)")!
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(body)
        let (data, _) = try await URLSession.shared.data(for: req)
        Log.line("[Album] \(path) → \(String(data: data, encoding: .utf8) ?? "<binary>")")
        return try decoder.decode(Response.self, from: data)
    }
}
