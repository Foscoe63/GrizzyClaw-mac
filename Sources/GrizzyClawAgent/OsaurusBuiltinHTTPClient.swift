import Foundation
import GrizzyClawCore

enum OsaurusBuiltinHTTPClient {
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 45
        c.timeoutIntervalForResource = 60
        c.waitsForConnectivity = false
        c.httpShouldSetCookies = false
        c.httpCookieStorage = nil
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    struct HTTPResult {
        let status: Int
        let finalURL: URL?
        let headers: [String: String]
        let body: Data
    }

    static func perform(
        url: URL,
        method: String,
        headers: [String: String],
        body: Data?,
        maxBodyBytes: Int64
    ) async throws -> HTTPResult {
        var req = URLRequest(url: url)
        req.httpMethod = method.uppercased()
        for (k, v) in headers {
            req.setValue(v, forHTTPHeaderField: k)
        }
        req.httpBody = body
        if let h = req.value(forHTTPHeaderField: "Content-Length"), let n = Int64(h), n > maxBodyBytes {
            throw NSError(
                domain: "OsaurusFetch", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Request body too large (\(n) bytes)."]
            )
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw NSError(
                domain: "OsaurusFetch", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Non-HTTP response."]
            )
        }
        if http.expectedContentLength > maxBodyBytes {
            throw NSError(
                domain: "OsaurusFetch", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Response Content-Length exceeds cap."]
            )
        }
        if Int64(data.count) > maxBodyBytes {
            throw NSError(
                domain: "OsaurusFetch", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Response body exceeds \(maxBodyBytes) bytes."]
            )
        }
        var hdr: [String: String] = [:]
        for (k, v) in http.allHeaderFields {
            if let kk = k as? String, let vv = v as? String {
                hdr[kk] = vv
            }
        }
        return HTTPResult(
            status: http.statusCode,
            finalURL: http.url,
            headers: hdr,
            body: data
        )
    }
}
