const Allocator = std.mem.Allocator;
const h11 = @import("h11");
const Header = @import("http").Header;
const Headers = @import("http").Headers;
const Method = @import("http").Method;
const network = @import("network");
const Response = @import("response.zig").Response;
const std = @import("std");
const Uri = @import("http").Uri;
const Version = @import("http").Version;

pub const Connection = struct {
    allocator: *Allocator,
    state: h11.Client,
    socket: ?network.Socket,

    pub fn init(allocator: *Allocator) Connection {
        return Connection {
            .allocator = allocator,
            .state = h11.Client.init(allocator),
            .socket = null,
        };
    }

    pub fn deinit(self: *Connection) void {
        self.state.deinit();

        if (self.socket != null) {
            self.socket.?.close();
        }
    }

    pub fn request(self: *Connection, method: Method, url: []const u8, options: anytype) !Response {
        const uri = try Uri.parse(url, false);

        var version = Version.Http11;
        if (@hasField(@TypeOf(options), "version")) {
            version = options.version;
        }

        var headers = Headers.init(self.allocator);
        try headers.append("Host", uri.host.name);
        if (@hasField(@TypeOf(options), "headers")) {
            try headers._items.appendSlice(options.headers);
        }

        var content: ?[]const u8 = null;
        if (@hasField(@TypeOf(options), "content")) {
            content = options.content;
        }

        var _request = try h11.Request.init(method, uri.path, version, headers);
        defer _request.deinit();

        var content_length = try self.frameRequestBody(&_request, content);

        self.socket = try network.connectToHost(self.allocator, uri.host.name, 80, .tcp);
        try self.sendRequest(_request);
        try self.sendRequestData(content);

        var response = try self.readResponse();
        var data = try self.readResponseData();

        if (content_length != null) {
            self.allocator.free(content_length.?);
        }

        return Response {
            .allocator = self.allocator,
            .buffer = response.raw_bytes,
            .status = response.statusCode,
            .version = response.version,
            .headers = response.headers,
            .body = data.content,
        };
    }

    fn frameRequestBody(self: *Connection, _request: *h11.Request, content: ?[]const u8) !?[]const u8 {
        if (content == null) {
            return null;
        }

        var content_length = try std.fmt.allocPrint(self.allocator, "{d}", .{content.?.len});
        try _request.headers.append("Content-Length", content_length);
        return content_length;
    }

    fn sendRequest(self: *Connection, _request: h11.Request) !void {
        var bytes = try self.state.send(h11.Event {.Request = _request });
        defer self.allocator.free(bytes);
        try self.socket.?.writer().writeAll(bytes);
    }

    fn sendRequestData(self: *Connection, content: ?[]const u8) !void {
        if (content == null or content.?.len == 0) {
            return;
        }
        var data_event = h11.Data.to_event(null, content.?);
        var bytes = try self.state.send(data_event);
        try self.socket.?.writer().writeAll(bytes);
    }

    fn readResponse(self: *Connection) !h11.Response {
        var event = try self.nextEvent();
        switch (event) {
            .Response => |response| {
                return response;
            },
            else => unreachable,
        }
    }

    fn readResponseData(self: *Connection) !h11.Data {
        var event = try self.nextEvent();
        switch (event) {
            .Data => |data| {
                return data;
            },
            else => unreachable,
        }
    }

    fn nextEvent(self: *Connection) !h11.Event {
        while (true) {
            var event = self.state.nextEvent() catch |err| switch (err) {
                error.NeedData => {
                    var buffer: [1024]u8 = undefined;
                    const bytesReceived = try self.socket.?.receive(&buffer);
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
