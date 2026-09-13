import Foundation
import Security

public enum JellyfinError: Error, LocalizedError {
    case badURL
    case http(Int, String)
    case notAuthenticated
    case decoding(String)
    case keychain(OSStatus)
    case noDirectPlaySource

    public var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid server URL."
        case .http(let code, let msg): return "Server error \(code): \(msg)"
        case .notAuthenticated: return "Not signed in."
        case .decoding(let d): return "Failed to decode response: \(d)"
        case .keychain(let status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown Keychain error"
            return "Could not securely save your session: \(detail) (\(status))."
        case .noDirectPlaySource: return "No direct-play source available for this item."
        }
    }
}

/// Identifies this client in the MediaBrowser `Authorization` header.
public struct ClientInfo: Sendable {
    public var client: String
    public var device: String
    public var deviceId: String
    public var version: String

    public init(client: String = "solfin",
                device: String = Host.current().localizedName ?? "Mac",
                deviceId: String,
                version: String = "1.0.0") {
        self.client = client
        self.device = device
        self.deviceId = deviceId
        self.version = version
    }
}

/// Async REST client for a single Jellyfin server. Immutable auth state; sign-in
/// produces a new authenticated client via `authenticated(with:)`.
public final class APIClient: Sendable {
    public let baseURL: URL
    public let clientInfo: ClientInfo
    public let session: ServerSession?
    private let urlSession: URLSession

    public init(baseURL: URL, clientInfo: ClientInfo, session: ServerSession? = nil,
                urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.clientInfo = clientInfo
        self.session = session
        self.urlSession = urlSession
    }

    public func authenticated(with session: ServerSession) -> APIClient {
        APIClient(baseURL: session.serverURL, clientInfo: clientInfo,
                  session: session, urlSession: urlSession)
    }

    public var userId: String? { session?.userId }

    // MARK: - Header

    var authorizationHeaderValue: String {
        var parts = [
            "MediaBrowser Client=\"\(clientInfo.client)\"",
            "Device=\"\(clientInfo.device)\"",
            "DeviceId=\"\(clientInfo.deviceId)\"",
            "Version=\"\(clientInfo.version)\"",
        ].joined(separator: ", ")
        if let token = session?.accessToken, !token.isEmpty {
            parts += ", Token=\"\(token)\""
        }
        return parts
    }

    // MARK: - Core request

    func makeRequest(path: String, method: String = "GET",
                     query: [URLQueryItem] = [], body: Data? = nil) throws -> URLRequest {
        guard var comps = URLComponents(url: baseURL.appendingPathComponent(path),
                                        resolvingAgainstBaseURL: false) else {
            throw JellyfinError.badURL
        }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw JellyfinError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    @discardableResult
    func send(_ req: URLRequest) async throws -> Data {
        let (data, resp) = try await urlSession.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw JellyfinError.http(-1, "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw JellyfinError.http(http.statusCode, String(msg.prefix(200)))
        }
        return data
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw JellyfinError.decoding("\(error)") }
    }

    // MARK: - Public info & auth

    public func publicSystemInfo() async throws -> PublicSystemInfo {
        let req = try makeRequest(path: "System/Info/Public")
        return try decode(PublicSystemInfo.self, from: try await send(req))
    }

    /// Authenticate by username/password. Returns a session; caller persists it.
    public func login(username: String, password: String) async throws -> ServerSession {
        let payload = ["Username": username, "Pw": password]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let req = try makeRequest(path: "Users/AuthenticateByName", method: "POST", body: body)
        let result = try decode(AuthenticationResult.self, from: try await send(req))
        return ServerSession(serverURL: baseURL, userId: result.user.id,
                             userName: result.user.name, accessToken: result.accessToken)
    }
}
