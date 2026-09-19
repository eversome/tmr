import Foundation

/// Minimal client for the BUSY Bar HTTP API.
///
/// Endpoints used here, all under /api on the bar:
///   POST   /display/draw    { application_name, elements: [...] }
///   DELETE /display/draw?application_name=...
///   POST   /audio/play      { application_name, stock_path }
///   POST   /audio/stop
///   GET    /version
///
/// Over USB the bar comes up at 10.0.4.20 and needs no credentials. The access
/// key only applies to connections arriving over Wi-Fi.
public final class BusyBarClient {
    public struct TextElement: Encodable {
        public let id: String
        public let type: String = "text"
        public let x: Int
        public let y: Int
        public let text: String
        public let font: String
        public let display: String

        public init(id: String, x: Int, y: Int, text: String, font: String, display: Display) {
            self.id = id
            self.x = x
            self.y = y
            self.text = text
            self.font = font
            self.display = display.rawValue
        }
    }

    public enum Display: String {
        case front          // 72x16 RGB matrix
        case back           // 160x80, 16 greys
    }

    /// Every sound the firmware ships. No upload needed, referenced by stock path.
    public enum StockSound: String, CaseIterable {
        case event = "shared/sounds/calendar_event_starts.snd"
        case reminder = "shared/sounds/calendar_reminder_ends.snd"
        case volume = "shared/sounds/volume_change.snd"
        case tick = "busy/sounds/countdown_tick.snd"
        case finish = "busy/sounds/countdown_finish.snd"
        case completed = "busy/sounds/session_completed.snd"

        public var shortName: String {
            switch self {
            case .event: return "event"
            case .reminder: return "reminder"
            case .volume: return "volume"
            case .tick: return "tick"
            case .finish: return "finish"
            case .completed: return "completed"
            }
        }

        public static func named(_ name: String) -> StockSound? {
            allCases.first { $0.shortName == name.lowercased() }
                ?? allCases.first { $0.rawValue == name }
        }
    }

    public enum BarError: Error, CustomStringConvertible {
        case badStatus(Int)
        case transport(String)

        public var description: String {
            switch self {
            case .badStatus(409):
                return "the bar is showing another app with a higher priority"
            case .badStatus(403):
                return "the bar refused the request; over Wi-Fi it needs its access key (--bar-token)"
            case .badStatus(let code):
                return "the bar answered HTTP \(code)"
            case .transport(let message):
                return message
            }
        }
    }

    private struct DrawPayload: Encodable {
        let applicationName: String
        let elements: [TextElement]

        enum CodingKeys: String, CodingKey {
            case applicationName = "application_name"
            case elements
        }
    }

    private struct PlayPayload: Encodable {
        let applicationName: String
        let stockPath: String

        enum CodingKeys: String, CodingKey {
            case applicationName = "application_name"
            case stockPath = "stock_path"
        }
    }

    public let applicationName: String
    private let base: URL
    private let token: String?
    private let session: URLSession

    public init?(host: String, token: String?, applicationName: String = "tmr") {
        let normalized = host.contains("://") ? host : "http://\(host)"
        guard let url = URL(string: normalized) else { return nil }

        self.base = url
        self.token = token
        self.applicationName = applicationName

        let configuration = URLSessionConfiguration.ephemeral
        // The bar is on the other end of a USB link; a stuck request must not
        // outlive the frame that sent it.
        configuration.timeoutIntervalForRequest = 2
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Calls

    public func draw(_ elements: [TextElement], completion: @escaping (Result<Void, Error>) -> Void) {
        let payload = DrawPayload(applicationName: applicationName, elements: elements)
        send("POST", path: "/api/display/draw", body: payload, completion: completion)
    }

    public func clear(completion: @escaping (Result<Void, Error>) -> Void) {
        var components = URLComponents(url: base.appendingPathComponent("/api/display/draw"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "application_name", value: applicationName)]
        guard let url = components?.url else {
            completion(.failure(BarError.transport("bad url")))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        authorize(&request)
        perform(request, completion: completion)
    }

    public func play(_ sound: StockSound, completion: @escaping (Result<Void, Error>) -> Void) {
        let payload = PlayPayload(applicationName: applicationName, stockPath: sound.rawValue)
        send("POST", path: "/api/audio/play", body: payload, completion: completion)
    }

    public func stopAudio(completion: @escaping (Result<Void, Error>) -> Void) {
        send("POST", path: "/api/audio/stop", body: EmptyBody(), completion: completion)
    }

    /// GET /api/version doubles as the reachability check.
    public func probe(completion: @escaping (Result<Void, Error>) -> Void) {
        var request = URLRequest(url: base.appendingPathComponent("/api/version"))
        request.httpMethod = "GET"
        authorize(&request)
        perform(request, completion: completion)
    }

    // MARK: - Plumbing

    private struct EmptyBody: Encodable {}

    private func send<Body: Encodable>(
        _ method: String,
        path: String,
        body: Body,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request)

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            completion(.failure(error))
            return
        }

        perform(request, completion: completion)
    }

    /// The wire format of the access key is not documented; this is the usual
    /// bearer shape and is only needed over Wi-Fi. Over USB no key is sent.
    private func authorize(_ request: inout URLRequest) {
        guard let token = token, !token.isEmpty else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func perform(_ request: URLRequest, completion: @escaping (Result<Void, Error>) -> Void) {
        let task = session.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(.failure(BarError.transport(error.localizedDescription)))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(BarError.transport("no response")))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                completion(.failure(BarError.badStatus(http.statusCode)))
                return
            }
            completion(.success(()))
        }
        task.resume()
    }
}
