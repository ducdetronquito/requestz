const Allocator = std.mem.Allocator;
const h11 = @import("h11");
const Header = @import("http").Header;
const Headers = @import("http").Headers;
const HeaderName = @import("http").HeaderName;
const HeaderType = @import("http").HeaderType;
const HeaderValue = @import("http").HeaderValue;
const Method = @import("http").Method;
const Socket = @import("socket.zig").Socket;
const Response = @import("response.zig").Response;
const std = @import("std");
const Uri = @import("http").Uri;
const Version = @import("http").Version;


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
            const port = uri.port orelse 80;
            var socket = try SocketType.connect(allocator, uri.host.name, port);
            return Self.init(allocator, socket);
        }

        pub fn deinit(self: *Self) void {
            self.state.deinit();
            self.socket.close();
        }

        pub fn request(self: *Self, method: Method, uri: Uri, options: anytype) !Response {
            var version = Version.Http11;
            if (@hasField(@TypeOf(options), "version")) {
                version = options.version;
            }

            var headers = Headers.init(self.allocator);
            try headers.append("Host", uri.host.name);
            if (@hasField(@TypeOf(options), "headers")) {
                var user_headers = self.getUserHeaders(options.headers);
                try headers._items.appendSlice(user_headers);
            }

            var content: ?[]const u8 = null;
            if (@hasField(@TypeOf(options), "content")) {
                content = options.content;
            }

            var _request = try h11.Request.init(method, uri.path, version, headers);
            defer _request.deinit();

            var content_length = try self.frameRequestBody(&_request, content);
            try self.sendRequest(_request);
            try self.sendRequestData(content);

            var response = try self.readResponse();
            var body = try self.readResponseBody();

            if (content_length != null) {
                self.allocator.free(content_length.?);
            }

            return Response {
                .allocator = self.allocator,
                .buffer = response.raw_bytes,
                .status = response.statusCode,
                .version = response.version,
                .headers = response.headers,
                .body = body,
            };
        }

        // TODO:
        // This function provides compile-time evaluation of headers.
        // It should probably be located within the http package.
        fn getUserHeaders(self: Self, user_headers: anytype) []Header {
            const typeof = @TypeOf(user_headers);
            const typeinfo = @typeInfo(typeof);

            switch(typeinfo) {
                .Struct => |obj| {
                    comptime {
                        var i = 0;
                        while (i < obj.fields.len) {
                            _ = HeaderName.parse(user_headers[i][0]) catch |err| {
                                @compileError("Invalid header name: " ++ user_headers[i][0]);
                            };

                            _ = HeaderValue.parse(user_headers[i][1]) catch |err| {
                                @compileError("Invalid header value: " ++ user_headers[i][1]);
                            };
                            i += 1;
                        }
                    }

                    comptime {
                        var result: [obj.fields.len]Header = undefined;
                        var i: usize = 0;
                        while (i < obj.fields.len) {
                            var _type = HeaderType.from_bytes(user_headers[i][0]);
                            var name = user_headers[i][0];
                            var value = user_headers[i][1];
                            result[i] = Header { .name = .{.type = _type, .value = name}, .value = value};
                            i += 1;
                        }
                        return &result;
                    }
                },
                .Pointer => |ptr| {
                    return user_headers;
                },
                else => {
                    @compileError("Invalid headers type: You must provide either a http.Headers or an anonymous struct literal.");
                }
            }
        }

        fn frameRequestBody(self: *Self, _request: *h11.Request, content: ?[]const u8) !?[]const u8 {
            if (content == null) {
                return null;
            }

            var content_length = try std.fmt.allocPrint(self.allocator, "{d}", .{content.?.len});
            try _request.headers.append("Content-Length", content_length);
            return content_length;
        }

        fn sendRequest(self: *Self, _request: h11.Request) !void {
            var bytes = try self.state.send(h11.Event {.Request = _request });
            defer self.allocator.free(bytes);

            try self.socket.write(bytes);
        }

        fn sendRequestData(self: *Self, content: ?[]const u8) !void {
            if (content == null or content.?.len == 0) {
                return;
            }
            var data_event = h11.Data.to_event(null, content.?);
            var bytes = try self.state.send(data_event);
            try self.socket.write(bytes);
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


const expect = std.testing.expect;
const SocketMock = @import("socket.zig").SocketMock;
const ConnectionMock = Connection(SocketMock);

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
