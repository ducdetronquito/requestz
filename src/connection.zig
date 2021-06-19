const Allocator = std.mem.Allocator;
const h11 = @import("h11");
const Method = @import("http").Method;
const TcpSocket = @import("socket.zig").TcpSocket;
const Request = @import("request.zig").Request;
const Response = @import("response.zig").Response;
const std = @import("std");
const StreamingResponse = @import("response.zig").StreamingResponse;
const Uri = @import("http").Uri;


pub const TcpConnection = Connection(TcpSocket);

pub fn Connection(comptime SocketType: type) type {
    return struct {
        const Self = @This();
        const H11Client = h11.Client(SocketType.Reader, SocketType.Writer);

        allocator: *Allocator,
        state: H11Client,
        socket: SocketType,

        pub fn init(allocator: *Allocator, socket: SocketType) Self {
            return Self {
                .allocator = allocator,
                .socket = socket,
                .state = H11Client.init(allocator, socket.reader(), socket.writer()),
            };
        }

        pub fn connect(allocator: *Allocator, uri: Uri) !Self {
            var socket = try SocketType.connect(allocator, uri);
            return Self.init(allocator, socket);
        }

        pub fn deinit(self: *Self) void {
            self.state.deinit();
            self.socket.close();
        }

        pub fn request(self: *Self, method: Method, uri: Uri, options: anytype) !Response {
            var _request = try Request.init(self.allocator, method, uri, options);
            defer _request.deinit();

            try self.sendRequest(_request);

            var response = try self.readResponse();
            var body = try self.readResponseBody();

            return Response {
                .allocator = self.allocator,
                .buffer = response.raw_bytes,
                .status = response.statusCode,
                .version = response.version,
                .headers = response.headers,
                .body = body,
            };
        }

        pub fn stream(self: *Self, method: Method, uri: Uri, options: anytype) !StreamingResponse(Self) {
            var _request = try Request.init(self.allocator, method, uri, options);
            defer _request.deinit();

            try self.sendRequest(_request);

            var response = try self.readResponse();

            return StreamingResponse(Self) {
                .allocator = self.allocator,
                .buffer = response.raw_bytes,
                .connection = self,
                .status = response.statusCode,
                .version = response.version,
                .headers = response.headers,
            };
        }

        fn sendRequest(self: *Self, _request: Request) !void {
            var request_event = try h11.Request.init(_request.method, _request.path, _request.version, _request.headers);

            try self.state.send(h11.Event {.Request = request_event });

            switch(_request.body) {
                .Empty => return,
                .ContentLength => |body| {
                    try self.state.send(.{ .Data = h11.Data{ .bytes = body.content } });
                }
            }
        }

        fn readResponse(self: *Self) !h11.Response {
            var event = try self.state.nextEvent(.{});
            return event.Response;
        }

        fn readResponseBody(self: *Self) ![]const u8 {
            var body = std.ArrayList(u8).init(self.allocator);
            errdefer body.deinit();

            while (true) {
                var buffer: [4096]u8 = undefined;
                var event = try self.state.nextEvent(.{ .buffer = &buffer });
                switch(event) {
                    .Data => |data| try body.appendSlice(data.bytes),
                    .EndOfMessage => return body.toOwnedSlice(),
                    else => unreachable,
                }
            }
        }

        pub fn nextEvent(self: *Self, options: anytype) !h11.Event {
            return self.state.nextEvent(options);
        }
    };
}


const ConnectionMock = Connection(SocketMock);
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const Headers = @import("http").Headers;
const SocketMock = @import("socket.zig").SocketMock;

test "Get" {
    const uri = try Uri.parse("http://httpbin.org/get", false);
    var connection = try ConnectionMock.connect(std.testing.allocator, uri);
    defer connection.deinit();

    try connection.socket.target.receive(
        "HTTP/1.1 200 OK\r\nContent-Length: 14\r\nServer: gunicorn/19.9.0\r\n\r\n"
        ++ "Gotta Go Fast!"
    );

    var response = try connection.request(.Get, uri, .{});
    defer response.deinit();

    try expect(response.status == .Ok);
    try expect(response.version == .Http11);

    var headers = response.headers.items();

    try expectEqualStrings(headers[0].name.raw(), "Content-Length");
    try expectEqualStrings(headers[1].name.raw(), "Server");

    try expect(response.body.len == 14);
}

test "Get with headers" {
    const uri = try Uri.parse("http://httpbin.org/get", false);

    var connection = try ConnectionMock.connect(std.testing.allocator, uri);
    defer connection.deinit();
    try connection.socket.target.receive(
        "HTTP/1.1 200 OK\r\nContent-Length: 14\r\nServer: gunicorn/19.9.0\r\n\r\n"
        ++ "Gotta Go Fast!"
    );

    var headers = Headers.init(std.testing.allocator);
    defer headers.deinit();
    try headers.append("Gotta-go", "Fast!");

    var response = try connection.request(.Get, uri, .{ .headers = headers.items()});
    defer response.deinit();

    try expect(connection.socket.target.have_sent("GET /get HTTP/1.1\r\nHost: httpbin.org\r\nGotta-go: Fast!\r\n\r\n"));
}

test "Get with compile-time headers" {
    const uri = try Uri.parse("http://httpbin.org/get", false);

    var connection = try ConnectionMock.connect(std.testing.allocator, uri);
    defer connection.deinit();
    try connection.socket.target.receive(
        "HTTP/1.1 200 OK\r\nContent-Length: 14\r\nServer: gunicorn/19.9.0\r\n\r\n"
        ++ "Gotta Go Fast!"
    );

    var headers = .{
        .{"Gotta-go", "Fast!"}
    };

    var response = try connection.request(.Get, uri, .{ .headers = headers});
    defer response.deinit();

    try expect(connection.socket.target.have_sent("GET /get HTTP/1.1\r\nHost: httpbin.org\r\nGotta-go: Fast!\r\n\r\n"));
}

test "Post binary data" {
    const uri = try Uri.parse("http://httpbin.org/post", false);

    var connection = try ConnectionMock.connect(std.testing.allocator, uri);
    defer connection.deinit();
    try connection.socket.target.receive(
        "HTTP/1.1 200 OK\r\nContent-Length: 14\r\nServer: gunicorn/19.9.0\r\n\r\n"
        ++ "Gotta Go Fast!"
    );

    var response = try connection.request(.Post, uri, .{ .content = "Gotta go fast!"});
    defer response.deinit();

    try expect(connection.socket.target.have_sent("POST /post HTTP/1.1\r\nHost: httpbin.org\r\nContent-Length: 14\r\n\r\nGotta go fast!"));
}

test "Head request has no message body" {
    const uri = try Uri.parse("http://httpbin.org/head", false);
    var connection = try ConnectionMock.connect(std.testing.allocator, uri);
    defer connection.deinit();

    try connection.socket.target.receive("HTTP/1.1 200 OK\r\nContent-Length: 14\r\nServer: gunicorn/19.9.0\r\n\r\n");

    var response = try connection.request(.Head, uri, .{});
    defer response.deinit();

    try expect(response.body.len == 0);
}

test "IP address and a port should be set in HOST headers" {
    const uri = try Uri.parse("http://127.0.0.1:8080/", false);

    var connection = try ConnectionMock.connect(std.testing.allocator, uri);
    defer connection.deinit();

    try connection.socket.target.receive("HTTP/1.1 200 OK\r\n\r\n");

    var response = try connection.request(.Get, uri, .{});
    defer response.deinit();

    try expect(connection.socket.target.have_sent("GET / HTTP/1.1\r\nHost: 127.0.0.1:8080\r\n\r\n"));
}

test "Request a URI without path defaults to /" {
    const uri = try Uri.parse("http://httpbin.org", false);

    var connection = try ConnectionMock.connect(std.testing.allocator, uri);
    defer connection.deinit();

    try connection.socket.target.receive("HTTP/1.1 200 OK\r\n\r\n");

    var response = try connection.request(.Get, uri, .{});
    defer response.deinit();

    try expect(connection.socket.target.have_sent("GET / HTTP/1.1\r\nHost: httpbin.org\r\n\r\n"));
}

test "Get a response in multiple socket read" {
    const uri = try Uri.parse("http://httpbin.org", false);

    var connection = try ConnectionMock.connect(std.heap.page_allocator, uri);
    defer connection.deinit();

    try connection.socket.target.receive("HTTP/1.1 200 OK\r\nContent-Length: 14\r\n\r\n");
    try connection.socket.target.receive("Gotta go fast!");

    var response = try connection.request(.Get, uri, .{});
    defer response.deinit();

    try expect(response.status == .Ok);
    try expect(response.version == .Http11);

    var headers = response.headers.items();

    try expectEqualStrings(headers[0].name.raw(), "Content-Length");
    try expectEqualStrings(headers[0].value, "14");

    try expect(response.body.len == 14);
}

test "Get a streaming response" {
    const uri = try Uri.parse("http://httpbin.org", false);

    var connection = try ConnectionMock.connect(std.heap.page_allocator, uri);

    try connection.socket.target.receive("HTTP/1.1 200 OK\r\nContent-Length: 12288\r\n\r\n");

    var body = "a" ** 12288;
    try connection.socket.target.receive(body);

    var response = try connection.stream(.Get, uri, .{});
    defer response.deinit();

    try expect(response.status == .Ok);
    try expect(response.version == .Http11);

    var headers = response.headers.items();
    try expectEqualStrings(headers[0].name.raw(), "Content-Length");
    try expectEqualStrings(headers[0].value, "12288");

    var result = std.ArrayList(u8).init(std.testing.allocator);
    defer result.deinit();

    while(true) {
        var buffer: [4096]u8 = undefined;
        var bytesRead = try response.read(&buffer);
        if (bytesRead == 0) {
            break;
        }
        try result.appendSlice(buffer[0..bytesRead]);
    }

    try expectEqualStrings(result.items, body);
}

test "Get a chunk encoded response" {
    const uri = try Uri.parse("http://httpbin.org/get", false);
    var connection = try ConnectionMock.connect(std.testing.allocator, uri);
    defer connection.deinit();

    try connection.socket.target.receive(
        "HTTP/1.1 200 OK\r\n"
        ++ "Transfer-Encoding: chunked\r\n\r\n"
        ++ "7\r\nMozilla\r\n"
        ++ "9\r\nDeveloper\r\n"
        ++ "7\r\nNetwork\r\n"
        ++ "0\r\n\r\n"
    );

    var response = try connection.request(.Get, uri, .{});
    defer response.deinit();

    try expect(response.status == .Ok);
    try expect(response.version == .Http11);

    var headers = response.headers.items();

    try expectEqualStrings(headers[0].name.raw(), "Transfer-Encoding");
    try expectEqualStrings(headers[0].value, "chunked");

    try expectEqualStrings(response.body, "MozillaDeveloperNetwork");
}
