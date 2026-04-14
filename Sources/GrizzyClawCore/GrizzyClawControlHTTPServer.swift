import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix

/// Osaurus-style localhost HTTP control plane: `GET /health`, `GET /doctor` (JSON). No remote tunnel; bind defaults to loopback only.
public final class GrizzyClawControlHTTPServer: @unchecked Sendable {
    public static var defaultPort: Int { GrizzyClawRuntimeConstants.controlHTTPPort }

    private let group: EventLoopGroup
    private var channel: Channel?
    private var bindDescription: String = ""

    public init(eventLoopThreads: Int = 2) {
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: max(1, eventLoopThreads))
    }

    deinit {
        try? channel?.close().wait()
        try? group.syncShutdownGracefully()
    }

    /// Binds `host:port` and serves until `stop()` is called.
    public func start(host: String = "127.0.0.1", port: Int = GrizzyClawRuntimeConstants.controlHTTPPort) async throws {
        guard channel == nil else { return }

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(GrizzyClawHTTP1Router())
                }
            }

        let ch = try await bootstrap.bind(host: host, port: port).get()
        channel = ch
        bindDescription = "\(host):\(port)"
    }

    /// Closes the listening socket. The event loop group is shut down in `deinit`.
    public func stop() async throws {
        if let ch = channel {
            _ = try await ch.close()
            channel = nil
        }
    }

    public var listenDescription: String { bindDescription.isEmpty ? "not bound" : bindDescription }
}

// MARK: - HTTP/1 handler

private final class GrizzyClawHTTP1Router: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private var requestHead: HTTPRequestHead?
    private var bodyBuffer = ByteBuffer()

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            requestHead = head
            bodyBuffer.clear()
        case .body(var buf):
            bodyBuffer.writeBuffer(&buf)
        case .end:
            guard let head = requestHead else {
                respond(context: context, status: .badRequest, body: "bad request")
                return
            }
            handle(context: context, head: head)
            requestHead = nil
        }
    }

    private func handle(context: ChannelHandlerContext, head: HTTPRequestHead) {
        let rawPath = head.uri.split(separator: "?").first.map(String.init) ?? head.uri
        let path =
            rawPath.hasSuffix("/") && rawPath.count > 1
            ? String(rawPath.dropLast())
            : rawPath

        guard head.method == .GET else {
            respond(context: context, status: .methodNotAllowed, body: "method not allowed")
            return
        }

        switch path {
        case "/health":
            let body = #"{"status":"ok","service":"grizzyclaw"}"#
            respondJSON(context: context, status: .ok, string: body)
        case "/doctor":
            let report = GrizzyClawDoctorService.buildReport()
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            do {
                let data = try enc.encode(report)
                let str = String(decoding: data, as: UTF8.self)
                respondJSON(context: context, status: .ok, string: str)
            } catch {
                respond(context: context, status: .internalServerError, body: "encode failed")
            }
        default:
            respond(context: context, status: .notFound, body: "not found")
        }
    }

    private func respondJSON(context: ChannelHandlerContext, status: HTTPResponseStatus, string: String) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json; charset=utf-8")
        let data = Data(string.utf8)
        headers.add(name: "Content-Length", value: "\(data.count)")
        let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        var buf = context.channel.allocator.buffer(capacity: data.count)
        buf.writeBytes(data)
        context.write(wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    private func respond(context: ChannelHandlerContext, status: HTTPResponseStatus, body: String) {
        let data = Data(body.utf8)
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
        headers.add(name: "Content-Length", value: "\(data.count)")
        let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        var buf = context.channel.allocator.buffer(capacity: data.count)
        buf.writeBytes(data)
        context.write(wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }
}
