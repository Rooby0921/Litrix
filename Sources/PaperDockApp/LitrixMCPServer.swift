import Combine
import Foundation
@preconcurrency import Network

private struct LitrixHTTPRequest {
    var method: String
    var target: String
    var path: String
    var queryItems: [URLQueryItem]
    var headers: [String: String]
    var body: Data
}

private struct LitrixHTTPResponse {
    var statusCode: Int
    var reasonPhrase: String
    var headers: [String: String]
    var body: Data

    static func json(statusCode: Int, object: Any) -> LitrixHTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return LitrixHTTPResponse(
            statusCode: statusCode,
            reasonPhrase: reasonPhrase(for: statusCode),
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: data
        )
    }

    static func plainText(statusCode: Int, body: String, headers: [String: String] = [:]) -> LitrixHTTPResponse {
        LitrixHTTPResponse(
            statusCode: statusCode,
            reasonPhrase: reasonPhrase(for: statusCode),
            headers: ["Content-Type": "text/plain; charset=utf-8"].merging(headers) { _, rhs in rhs },
            body: Data(body.utf8)
        )
    }

    static func empty(statusCode: Int, headers: [String: String] = [:]) -> LitrixHTTPResponse {
        LitrixHTTPResponse(
            statusCode: statusCode,
            reasonPhrase: reasonPhrase(for: statusCode),
            headers: ["Content-Type": "application/json; charset=utf-8"].merging(headers) { _, rhs in rhs },
            body: Data()
        )
    }

    private static func reasonPhrase(for statusCode: Int) -> String {
        switch statusCode {
        case 200: return "OK"
        case 202: return "Accepted"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        case 415: return "Unsupported Media Type"
        case 500: return "Internal Server Error"
        default: return "HTTP \(statusCode)"
        }
    }
}

private final class LitrixHTTPConnectionHandler: @unchecked Sendable {
    typealias RequestHandler = (LitrixHTTPRequest, @escaping (LitrixHTTPResponse) -> Void) -> Void

    private let connection: NWConnection
    private let queue: DispatchQueue
    private let requestHandler: RequestHandler
    private let maximumRequestSize = 80 * 1024 * 1024
    private var buffer = Data()
    private var hasProcessedRequest = false

    init(connection: NWConnection, queue: DispatchQueue, requestHandler: @escaping RequestHandler) {
        self.connection = connection
        self.queue = queue
        self.requestHandler = requestHandler
    }

    func start() {
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                self.receiveNextChunk()
            case .failed, .cancelled:
                self.finish()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveNextChunk() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
            if let data, !data.isEmpty {
                self.buffer.append(data)
            }

            if self.buffer.count > self.maximumRequestSize {
                self.send(LitrixHTTPResponse.plainText(statusCode: 413, body: "Request body too large"))
                return
            }

            switch Self.parseRequest(from: self.buffer) {
            case .request(let request):
                guard !self.hasProcessedRequest else { return }
                self.hasProcessedRequest = true
                self.requestHandler(request) { response in
                    self.queue.async {
                        self.send(response)
                    }
                }
            case .invalid(let message):
                self.send(LitrixHTTPResponse.plainText(statusCode: 400, body: message))
            case .needMoreData:
                if isComplete {
                    self.send(LitrixHTTPResponse.plainText(statusCode: 400, body: "Incomplete HTTP request"))
                    return
                }
                if error == nil {
                    self.receiveNextChunk()
                } else {
                    self.finish()
                }
            }
        }
    }

    private func send(_ response: LitrixHTTPResponse) {
        let head = buildHTTPHead(for: response)
        let payload = head + response.body
        connection.send(content: payload, completion: .contentProcessed { _ in
            self.finish()
        })
    }

    private func finish() {
        connection.stateUpdateHandler = nil
        connection.cancel()
    }

    private func buildHTTPHead(for response: LitrixHTTPResponse) -> Data {
        var lines = [
            "HTTP/1.1 \(response.statusCode) \(response.reasonPhrase)",
            "Content-Length: \(response.body.count)",
            "Connection: close"
        ]

        for (key, value) in response.headers.sorted(by: { $0.key < $1.key }) {
            lines.append("\(key): \(value)")
        }
        lines.append("")
        lines.append("")
        return Data(lines.joined(separator: "\r\n").utf8)
    }

    private enum ParseOutcome {
        case needMoreData
        case invalid(String)
        case request(LitrixHTTPRequest)
    }

    private static func parseRequest(from buffer: Data) -> ParseOutcome {
        let headerDelimiter = Data("\r\n\r\n".utf8)
        guard let headerRange = buffer.range(of: headerDelimiter) else {
            return .needMoreData
        }

        let headerData = buffer[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return .invalid("Unable to decode request headers as UTF-8")
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return .invalid("Missing HTTP request line")
        }

        let requestLineParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestLineParts.count >= 2 else {
            return .invalid("Malformed HTTP request line")
        }

        let method = String(requestLineParts[0]).uppercased()
        let target = String(requestLineParts[1])
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separatorIndex = line.firstIndex(of: ":") else { continue }
            let key = line[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separatorIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerRange.upperBound
        guard buffer.count >= bodyStart + contentLength else {
            return .needMoreData
        }

        let body = Data(buffer[bodyStart..<(bodyStart + contentLength)])
        let urlString = target.hasPrefix("http://") || target.hasPrefix("https://")
            ? target
            : "http://localhost\(target)"
        let components = URLComponents(string: urlString)
        let path = components?.path.isEmpty == false ? components?.path ?? "/" : "/"
        let queryItems = components?.queryItems ?? []

        return .request(
            LitrixHTTPRequest(
                method: method,
                target: target,
                path: path,
                queryItems: queryItems,
                headers: headers,
                body: body
            )
        )
    }
}

@MainActor
final class LitrixMCPServerController: ObservableObject {
    @Published private(set) var runtimeStatusText = "MCP disabled"
    @Published private(set) var runtimeListening = false

    private let settings: SettingsStore
    private let store: LibraryStore
    private let service: LitrixMCPToolService
    private let webImportService: LitrixWebImportService
    private let mcpSessionID = "litrix-local"
    private let listenerQueue = DispatchQueue(label: "Litrix.MCP.Listener", qos: .userInitiated)
    private let supportedProtocolVersions = [
        "2025-06-18",
        "2025-03-26",
        "2024-11-05",
        "2025-11-05"
    ]
    private var listener: NWListener?
    private var cancellables: Set<AnyCancellable> = []
    private var pendingRestartTask: Task<Void, Never>?

    init(settings: SettingsStore, store: LibraryStore) {
        self.settings = settings
        self.store = store
        self.service = LitrixMCPToolService(settings: settings, store: store)
        self.webImportService = LitrixWebImportService(store: store)
        bindSettings()
        restartListener()
    }

    deinit {
        listener?.cancel()
        pendingRestartTask?.cancel()
    }

    private func bindSettings() {
        settings.$mcpEnabled
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleRestart() }
            .store(in: &cancellables)
        settings.$mcpServerHost
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleRestart() }
            .store(in: &cancellables)
        settings.$mcpServerPort
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleRestart() }
            .store(in: &cancellables)
        settings.$mcpServerPath
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleRestart() }
            .store(in: &cancellables)
    }

    private func scheduleRestart(immediate: Bool = false) {
        pendingRestartTask?.cancel()
        pendingRestartTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if !immediate {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            self.restartListener()
        }
    }

    private func restartListener() {
        listener?.cancel()
        listener = nil

        guard settings.mcpEnabled else {
            runtimeListening = false
            runtimeStatusText = "MCP disabled"
            return
        }

        let portValue = settings.resolvedMCPServerPort
        guard let port = NWEndpoint.Port(rawValue: UInt16(portValue)) else {
            runtimeListening = false
            runtimeStatusText = "Invalid MCP port: \(portValue)"
            return
        }

        do {
            let listener = try NWListener(using: .tcp, on: port)
            let endpointDescription = "\(settings.resolvedMCPServerHost):\(settings.resolvedMCPServerPort)\(settings.resolvedMCPServerPath)"
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.acceptConnection(connection)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.handleListenerState(state, endpointDescription: endpointDescription, portValue: portValue)
                }
            }
            listener.start(queue: listenerQueue)
            self.listener = listener
            runtimeListening = false
            runtimeStatusText = "Starting MCP listener on \(endpointDescription)"
        } catch {
            runtimeListening = false
            runtimeStatusText = "Failed to start MCP listener: \(error.localizedDescription)"
        }
    }

    private func handleListenerState(_ state: NWListener.State, endpointDescription: String, portValue: Int) {
        switch state {
        case .ready:
            runtimeListening = true
            runtimeStatusText = "Listening on \(endpointDescription)"
        case .failed(let error):
            runtimeListening = false
            listener = nil
            if settings.mcpEnabled,
               (portValue == SettingsStore.legacyMCPServerPort || portValue == SettingsStore.officeAddinStaticServerPort) {
                runtimeStatusText = "MCP port \(portValue) is unavailable; switching to \(SettingsStore.defaultMCPServerPort)."
                settings.mcpServerPort = SettingsStore.defaultMCPServerPort
                return
            }
            runtimeStatusText = "MCP listener failed: \(error.localizedDescription)"
        case .cancelled:
            runtimeListening = false
            if settings.mcpEnabled {
                runtimeStatusText = "MCP listener cancelled"
            } else {
                runtimeStatusText = "MCP disabled"
            }
        default:
            break
        }
    }

    private func acceptConnection(_ connection: NWConnection) {
        let expectedPath = settings.resolvedMCPServerPath
        let handler = LitrixHTTPConnectionHandler(connection: connection, queue: listenerQueue) { [weak self] request, completion in
            Task { @MainActor [weak self] in
                guard let self else {
                    completion(.plainText(statusCode: 500, body: "MCP server unavailable"))
                    return
                }
                let response = await self.processHTTPRequest(request, expectedPath: expectedPath)
                completion(response)
            }
        }
        handler.start()
    }

    private func processHTTPRequest(_ request: LitrixHTTPRequest, expectedPath: String) async -> LitrixHTTPResponse {
        let webImportPath = normalizedChildPath(base: expectedPath, child: "web-import")
        let webImportContextPath = normalizedChildPath(base: webImportPath, child: "context")
        guard request.path == expectedPath || request.path == webImportPath || request.path == webImportContextPath else {
            return .plainText(statusCode: 404, body: "Not found")
        }

        guard isAllowedOrigin(request.headers["origin"]) else {
            return .plainText(statusCode: 403, body: "Origin not allowed")
        }

        if request.method == "OPTIONS" {
            return responseWithCORS(
                .empty(
                    statusCode: 204,
                    headers: ["Allow": "GET, POST, OPTIONS"]
                ),
                originHeader: request.headers["origin"]
            )
        }

        let response: LitrixHTTPResponse
        if request.path == webImportContextPath {
            response = processWebImportContextRequest(request)
        } else if request.path == webImportPath {
            response = await processWebImportRequest(request)
        } else {
            switch request.method {
            case "POST":
                response = processJSONRPCRequest(request)
            case "GET":
                response = .json(
                    statusCode: 200,
                    object: [
                        "endpoint": expectedPath,
                        "protocol": "MCP (Model Context Protocol)",
                        "transport": "Streamable HTTP",
                        "version": supportedProtocolVersions.first ?? "2025-03-26",
                        "description": "This endpoint accepts MCP protocol requests via POST.",
                        "usage": [
                            "method": "POST",
                            "contentType": "application/json",
                            "body": "MCP JSON-RPC 2.0 formatted requests"
                        ],
                        "status": "available"
                    ]
                )
            case "DELETE":
                response = .plainText(statusCode: 405, body: "DELETE not supported", headers: ["Allow": "POST, OPTIONS"])
            default:
                response = .plainText(statusCode: 405, body: "Unsupported method", headers: ["Allow": "POST, OPTIONS"])
            }
        }

        return responseWithCORS(response, originHeader: request.headers["origin"])
    }

    private func processJSONRPCRequest(_ request: LitrixHTTPRequest) -> LitrixHTTPResponse {
        let contentType = request.headers["content-type"]?.lowercased() ?? "application/json"
        guard contentType.contains("application/json") else {
            return .plainText(statusCode: 415, body: "MCP requests must use application/json")
        }

        let responseObject: Any
        do {
            let json = try JSONSerialization.jsonObject(with: request.body, options: [])
            guard let payload = json as? [String: Any] else {
                return jsonRPCErrorResponse(id: nil, code: -32600, message: "Only single JSON-RPC objects are supported")
            }
            responseObject = handleJSONRPCPayload(payload)
        } catch {
            return jsonRPCErrorResponse(id: nil, code: -32700, message: "Invalid JSON payload")
        }

        if responseObject is NSNull {
            return .empty(
                statusCode: 202,
                headers: ["Content-Type": "application/json; charset=utf-8"]
            )
        }
        return .json(statusCode: 200, object: responseObject)
    }

    private func processWebImportRequest(_ request: LitrixHTTPRequest) async -> LitrixHTTPResponse {
        guard request.method == "POST" else {
            return .plainText(
                statusCode: 405,
                body: "Web import only supports POST",
                headers: ["Allow": "POST, OPTIONS"]
            )
        }

        let contentType = request.headers["content-type"]?.lowercased() ?? "application/json"
        guard contentType.contains("application/json") else {
            return .plainText(statusCode: 415, body: "Web import requests must use application/json")
        }

        do {
            let payload = try await webImportService.importFromJSONData(request.body)
            return .json(statusCode: 200, object: payload)
        } catch let error as LitrixWebImportError {
            return .plainText(statusCode: error.statusCode, body: error.localizedDescription)
        } catch {
            return .plainText(statusCode: 500, body: "Web import failed: \(error.localizedDescription)")
        }
    }

    private func processWebImportContextRequest(_ request: LitrixHTTPRequest) -> LitrixHTTPResponse {
        guard request.method == "GET" else {
            return .plainText(
                statusCode: 405,
                body: "Web import context only supports GET",
                headers: ["Allow": "GET, OPTIONS"]
            )
        }

        let tags = store.tags.map { tag -> [String: Any] in
            var item: [String: Any] = ["name": tag]
            if let color = store.tagColorHexes[tag] {
                item["color"] = color
            }
            return item
        }

        return .json(
            statusCode: 200,
            object: [
                "collections": store.collections,
                "tags": tags
            ]
        )
    }

    private func handleJSONRPCPayload(_ payload: [String: Any]) -> Any {
        let id = payload["id"]
        guard (payload["jsonrpc"] as? String) == "2.0" else {
            return jsonRPCErrorObject(id: id, code: -32600, message: "jsonrpc must equal 2.0")
        }
        guard let method = payload["method"] as? String else {
            return jsonRPCErrorObject(id: id, code: -32600, message: "Missing JSON-RPC method")
        }
        let params = payload["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            return jsonRPCResultObject(id: id, result: initializeResult(params: params))
        case "notifications/initialized":
            return NSNull()
        case "ping":
            return jsonRPCResultObject(id: id, result: [:])
        case "tools/list":
            return jsonRPCResultObject(id: id, result: ["tools": service.toolDefinitions()])
        case "tools/call":
            return handleToolCall(id: id, params: params)
        case "resources/list":
            return jsonRPCResultObject(id: id, result: ["resources": []])
        case "prompts/list":
            return jsonRPCResultObject(id: id, result: ["prompts": []])
        default:
            if id == nil {
                return NSNull()
            }
            return jsonRPCErrorObject(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private func initializeResult(params: [String: Any]) -> [String: Any] {
        let requestedVersion = params["protocolVersion"] as? String
        let negotiatedVersion: String
        if let requestedVersion, supportedProtocolVersions.contains(requestedVersion) {
            negotiatedVersion = requestedVersion
        } else {
            negotiatedVersion = supportedProtocolVersions.first ?? "2025-03-26"
        }

        let versionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return [
            "protocolVersion": negotiatedVersion,
            "capabilities": [
                "tools": [
                    "listChanged": false
                ]
            ],
            "serverInfo": [
                "name": "Litrix MCP",
                "version": versionString
            ],
            "instructions": "Litrix MCP exposes local library search, metadata editing, notes, collections, tags, and PDF full-text access."
        ]
    }

    private func handleToolCall(id: Any?, params: [String: Any]) -> Any {
        guard let name = params["name"] as? String, !name.isEmpty else {
            return jsonRPCErrorObject(id: id, code: -32602, message: "tools/call requires a tool name")
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        let payload = service.callTool(name: name, arguments: arguments)
        let result: [String: Any] = [
            "content": [
                [
                    "type": "text",
                    "text": service.renderPayloadText(payload)
                ]
            ],
            "structuredContent": payload.structuredContent,
            "isError": payload.isError
        ]
        return jsonRPCResultObject(id: id, result: result)
    }

    private func isAllowedOrigin(_ originHeader: String?) -> Bool {
        guard let originHeader, !originHeader.isEmpty else {
            return true
        }
        guard let originURL = URL(string: originHeader) else {
            return false
        }
        let scheme = originURL.scheme?.lowercased() ?? ""
        if ["chrome-extension", "moz-extension", "safari-web-extension"].contains(scheme) {
            return true
        }
        guard let host = originURL.host?.lowercased() else {
            return false
        }
        let allowedHosts = Set([
            "127.0.0.1",
            "localhost",
            settings.resolvedMCPServerHost.lowercased()
        ])
        return allowedHosts.contains(host)
    }

    private func responseWithCORS(_ response: LitrixHTTPResponse, originHeader: String?) -> LitrixHTTPResponse {
        var headers = response.headers
        headers["Mcp-Session-Id"] = mcpSessionID
        for (key, value) in corsHeaders(originHeader: originHeader) {
            headers[key] = value
        }
        return LitrixHTTPResponse(
            statusCode: response.statusCode,
            reasonPhrase: response.reasonPhrase,
            headers: headers,
            body: response.body
        )
    }

    private func corsHeaders(originHeader: String?) -> [String: String] {
        let allowOrigin = (originHeader?.isEmpty == false ? originHeader : nil) ?? "*"
        return [
            "Access-Control-Allow-Origin": allowOrigin,
            "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Litrix-Source, Mcp-Session-Id",
            "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
            "Access-Control-Max-Age": "86400",
            "Vary": "Origin"
        ]
    }

    private func normalizedChildPath(base: String, child: String) -> String {
        let trimmedBase = base == "/" ? "" : base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "/\(trimmedBase.isEmpty ? child : "\(trimmedBase)/\(child)")"
    }

    private func jsonRPCResultObject(id: Any?, result: [String: Any]) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": result
        ]
    }

    private func jsonRPCErrorObject(id: Any?, code: Int, message: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": [
                "code": code,
                "message": message
            ]
        ]
    }

    private func jsonRPCErrorResponse(id: Any?, code: Int, message: String) -> LitrixHTTPResponse {
        .json(statusCode: 200, object: jsonRPCErrorObject(id: id, code: code, message: message))
    }
}
