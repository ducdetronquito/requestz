const Allocator = std.mem.Allocator;
const TcpConnection = @import("connection.zig").TcpConnection;
const Method = @import("http").Method;
const network = @import("network");
const Response = @import("response.zig").Response;
const std = @import("std");
const StreamingResponse = @import("response.zig").StreamingResponse;
const Uri = @import("http").Uri;

pub const Client = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) !Client {
        try network.init();
        return Client{ .allocator = allocator };
    }

    pub fn deinit(_: *Client) void {
        network.deinit();
    }

    pub fn connect(self: Client, url: []const u8, args: anytype) !Response {
        return self.request(.Connect, url, args);
    }

    pub fn delete(self: Client, url: []const u8, args: anytype) !Response {
        return self.request(.Delete, url, args);
    }

    pub fn get(self: Client, url: []const u8, args: anytype) !Response {
        return self.request(.Get, url, args);
    }

    pub fn head(self: Client, url: []const u8, args: anytype) !Response {
        return self.request(.Head, url, args);
    }

    pub fn options(self: Client, url: []const u8, args: anytype) !Response {
        return self.request(.Options, url, args);
    }

    pub fn patch(self: Client, url: []const u8, args: anytype) !Response {
        return self.request(.Patch, url, args);
    }

    pub fn post(self: Client, url: []const u8, args: anytype) !Response {
        return self.request(.Post, url, args);
    }

    pub fn put(self: Client, url: []const u8, args: anytype) !Response {
        return self.request(.Put, url, args);
    }

    pub fn request(self: Client, method: Method, url: []const u8, args: anytype) !Response {
        const uri = try Uri.parse(url, false);

        var connection = try self.get_connection(uri);
        defer connection.deinit();

        return connection.request(method, uri, args);
    }

    pub fn stream(self: Client, method: Method, url: []const u8, args: anytype) !StreamingResponse(TcpConnection) {
        const uri = try Uri.parse(url, false);

        var connection = try self.get_connection(uri);

        return connection.stream(method, uri, args);
    }

    pub fn trace(self: Client, url: []const u8, args: anytype) !Response {
        return self.request(.Trace, url, args);
    }

    fn get_connection(self: Client, uri: Uri) !*TcpConnection {
        return try TcpConnection.connect(self.allocator, uri);
    }
};
