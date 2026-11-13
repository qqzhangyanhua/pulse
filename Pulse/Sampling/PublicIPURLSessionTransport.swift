import Foundation

/// One-shot session for a click. Ephemeral: no disk cache and no stored cookies.
struct PublicIPURLSessionTransport: PublicIPTransport {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    func body(from url: URL) async throws -> String {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw PublicIPURLSessionError.rejectedStatus
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw PublicIPURLSessionError.undecodable
        }
        return text
    }
}

private enum PublicIPURLSessionError: Error {
    case rejectedStatus
    case undecodable
}
