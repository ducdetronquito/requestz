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

        var user_headers: []Header = &[_]Header{};
        if (@hasField(@TypeOf(options), "headers")) {
            user_headers = options.headers;
        }

        var headers = Headers.init(self.allocator);
        try headers.append("Host", uri.host.name);
        try headers._items.appendSlice(user_headers);

        var version = Version.Http11;
        if (@hasField(@TypeOf(options), "version")) {
            version = options.version;
        }

        self.socket = try network.connectToHost(self.allocator, uri.host.name, 80, .tcp);

        // TODO:
        // - Evaluate if we should init a request event with a Header slice instead.
        // - Add a method h11.Event.request(...) to return a request event directly.
        var request_event = try h11.Request.init(method, uri.path, version, headers);
        defer request_event.deinit();

        var bytes = try self.state.send(h11.Event {.Request = request_event });
        defer self.allocator.free(bytes);

        try self.socket.?.writer().writeAll(bytes);
        var response = try self.readResponse();

        var data = try self.readResponseData();

        return Response {
            .allocator = self.allocator,
            .buffer = response.raw_bytes,
            .status = response.statusCode,
            .version = response.version,
            .headers = response.headers,
            .body = data.content,
        };
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
