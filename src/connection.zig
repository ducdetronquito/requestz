const Allocator = std.mem.Allocator;
const h11 = @import("h11");
const Method = @import("http").Method;
const Socket = @import("socket.zig").Socket;
const Request = @import("request.zig").Request;
const Response = @import("response.zig").Response;
const std = @import("std");
const Uri = @import("http").Uri;


pub const TcpConnection = Connection(Socket);


pub fn Connection(comptime SocketType: type) type {
    return struct {
        const Self = @This();

        allocator: *Allocator,
        state: h11.Client,
        socket: SocketType,

        pub fn init(allocator: *Allocator, socket: SocketType) Self {
            return Self {
                .allocator = allocator,
                .socket = socket,
                .state = h11.Client.init(allocator),
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

        fn sendRequest(self: *Self, _request: Request) !void {
            var request_event = try h11.Request.init(_request.method, _request.path, _request.version, _request.headers);

            var bytes = try self.state.send(h11.Event {.Request = request_event });
            try self.socket.write(bytes);
            self.allocator.free(bytes);

            switch(_request.body) {
                .Empty => return,
                .ContentLength => |body| {
                    var data_event = h11.Data.to_event(null, body.content);
                    bytes = try self.state.send(data_event);
                    try self.socket.write(bytes);
                }
            }
        }

        fn readResponse(self: *Self) !h11.Response {
            var event = try self.nextEvent();
            switch (event) {
                .Response => |response| {
                    return response;
                },
                else => unreachable,
            }
        }

        fn readResponseBody(self: *Self) ![]const u8 {
            var event = try self.nextEvent();
            return switch (event) {
                .Data => |data| data.content,
                .EndOfMessage => "",
                else => unreachable,
            };
        }

        fn nextEvent(self: *Self) !h11.Event {
            while (true) {
                var event = self.state.nextEvent() catch |err| switch (err) {
                    error.NeedData => {
                        var buffer: [1024]u8 = undefined;
                        const bytesReceived = try self.socket.receive(&buffer);
                        var content = buffer[0..bytesReceived];
                        try self.state.receive(content);
                        continue;
                    },
                    else => {
                        return err;
                    }
                };
                return event;
            }
        }
    };
}


const ConnectionMock = Connection(SocketMock);
const expect = std.testing.expect;
const Headers = @import("http").Headers;
const SocketMock = @import("socket.zig").SocketMock;

test "Get" {
    const uri = try Uri.parse("http://httpbin.org/get", false);
    var connection = try ConnectionMock.connect(std.testing.allocator, uri);
    defer connection.deinit();

    try connection.socket.have_received(
        "HTTP/1.1 200 OK\r\nContent-Length: 14\r\nServer: gunicorn/19.9.0\r\n\r\n"
        ++ "Gotta Go Fast!"
    );

    var response = try connection.request(.Get, uri, .{});
    defer response.deinit();

    expect(response.status == .Ok);
    expect(response.version == .Http11);

    var headers = response.headers.items();

    expect(std.mem.eql(u8, headers[0].name.raw(), "Content-Length"));
    expect(std.mem.eql(u8, headers[1].name.raw(), "Server"));

    expect(response.body.len == 14);
}

test "Get with headers" {
    const uri = try Uri.parse("http://httpbin.org/get", false);

    var connection = try ConnectionMock.connect(std.testing.allocator, uri);
    defer connection.deinit();
    try connection.socket.have_received(
        "HTTP/1.1 200 OK\r\nContent-Length: 14\r\nServer: gunicorn/19.9.0\r\n\r\n"
        ++ "Gotta Go Fast!"
    );

    var headers = Headers.init(std.testing.allocator);
    defer headers.deinit();
    try headers.append("Gotta-go", "Fast!");

    var response = try connection.request(.Get, uri, .{ .headers = headers.items()});
    defer response.deinit();

    expect(connection.socket.have_sent("GET /get HTTP/1.1\r\nHost: httpbin.org\r\nGotta-go: Fast!\r\n\r\n"));
}

test "Get with compile-time headers" {
    const uri = try Uri.parse("http://httpbin.org/get", false);

    var connection = try ConnectionMock.connect(std.testing.allocator, uri);
    defer connection.deinit();
    try connection.socket.have_received(
        "HTTP/1.1 200 OK\r\nContent-Length: 14\r\nServer: gunicorn/19.9.0\r\n\r\n"
        ++ "Gotta Go Fast!"
    );

    var headers = .{
        .{"Gotta-go", "Fast!"}
    };

    var response = try connection.request(.Get, uri, .{ .headers = headers});
    defer response.deinit();

    expect(connection.socket.have_sent("GET /get HTTP/1.1\r\nHost: httpbin.org\r\nGotta-go: Fast!\r\n\r\n"));
}

test "Post binary data" {
    const uri = try Uri.parse("http://httpbin.org/post", false);

    var connection = try ConnectionMock.connect(std.testing.allocator, uri);
    defer connection.deinit();
    try connection.socket.have_received(
        "HTTP/1.1 200 OK\r\nContent-Length: 14\r\nServer: gunicorn/19.9.0\r\n\r\n"
        ++ "Gotta Go Fast!"
    );

    var response = try connection.request(.Post, uri, .{ .content = "Gotta go fast!"});
    defer response.deinit();

    expect(connection.socket.have_sent("POST /post HTTP/1.1\r\nHost: httpbin.org\r\nContent-Length: 14\r\n\r\nGotta go fast!"));
}


test "Head request has no message body" {
    const uri = try Uri.parse("http://httpbin.org/head", false);
    var connection = try ConnectionMock.connect(std.testing.allocator, uri);
    defer connection.deinit();

    try connection.socket.have_received("HTTP/1.1 200 OK\r\nContent-Length: 14\r\nServer: gunicorn/19.9.0\r\n\r\n");

    var response = try connection.request(.Head, uri, .{});
    defer response.deinit();

    expect(response.body.len == 0);
}

test "Requesting an IP address and a port should be in HOST headers" {
    const uri = try Uri.parse("http://127.0.0.1:8080/", false);

    var connection = try ConnectionMock.connect(std.testing.allocator, uri);
    defer connection.deinit();

    try connection.socket.have_received("HTTP/1.1 200 OK\r\n\r\n");

    var response = try connection.request(.Get, uri, .{});
    defer response.deinit();

    expect(connection.socket.have_sent("GET / HTTP/1.1\r\nHost: 127.0.0.1:8080\r\n\r\n"));
}


test "Request a URI without path defaults to /" {
    const uri = try Uri.parse("http://httpbin.org", false);

    var connection = try ConnectionMock.connect(std.testing.allocator, uri);
    defer connection.deinit();

    try connection.socket.have_received("HTTP/1.1 200 OK\r\n\r\n");

    var response = try connection.request(.Get, uri, .{});
    defer response.deinit();

    expect(connection.socket.have_sent("GET / HTTP/1.1\r\nHost: httpbin.org\r\n\r\n"));
}


test "Get a response in multiple socket read" {
    const uri = try Uri.parse("http://httpbin.org", false);

    var connection = try ConnectionMock.connect(std.heap.page_allocator, uri);
    defer connection.deinit();

    try connection.socket.have_received("HTTP/1.1 200 OK\r\nContent-Length: 14\r\n\r\n");
    try connection.socket.have_received("Gotta go fast!");

    var response = try connection.request(.Get, uri, .{});
    defer response.deinit();

    expect(response.status == .Ok);
    expect(response.version == .Http11);

    var headers = response.headers.items();

    expect(std.mem.eql(u8, headers[0].name.raw(), "Content-Length"));

    expect(response.body.len == 14);
}
