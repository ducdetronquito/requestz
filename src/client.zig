const Allocator = std.mem.Allocator;
const TcpConnection = @import("connection.zig").TcpConnection;
const Method = @import("http").Method;
const network = @import("network");
const Response = @import("response.zig").Response;
const std = @import("std");
const Uri = @import("http").Uri;


pub const Client = struct {
    allocator: *Allocator,

    pub fn init(allocator: *Allocator) !Client {
        try network.init();
        return Client { .allocator = allocator };
    }

    pub fn deinit(self: *Client) void {
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

    pub fn trace(self: Client, url: []const u8, args: anytype) !Response {
        return self.request(.Trace, url, args);
    }

    fn get_connection(self: Client, uri: Uri) !TcpConnection {
        return try TcpConnection.connect(self.allocator, uri);
    }
};


const expect = std.testing.expect;
const Headers = @import("http").Headers;

test "Get" {
    var client = try Client.init(std.testing.allocator);
    defer client.deinit();

    var response = try client.get("http://httpbin.org/get", .{});
    defer response.deinit();

    expect(response.status == .Ok);
    expect(response.version == .Http11);
    var headers = response.headers.items();

    expect(std.mem.eql(u8, headers[0].name.raw(), "Date"));
    expect(std.mem.eql(u8, headers[1].name.raw(), "Content-Type"));
    expect(std.mem.eql(u8, headers[1].value, "application/json"));
    expect(std.mem.eql(u8, headers[2].name.raw(), "Content-Length"));
    expect(std.mem.eql(u8, headers[2].value, "196"));
    expect(std.mem.eql(u8, headers[3].name.raw(), "Connection"));
    expect(std.mem.eql(u8, headers[3].value, "keep-alive"));
    expect(std.mem.eql(u8, headers[4].name.raw(), "Server"));
    expect(std.mem.eql(u8, headers[4].value, "gunicorn/19.9.0"));
    expect(std.mem.eql(u8, headers[5].name.raw(), "Access-Control-Allow-Origin"));
    expect(std.mem.eql(u8, headers[5].value, "*"));
    expect(std.mem.eql(u8, headers[6].name.raw(), "Access-Control-Allow-Credentials"));
    expect(std.mem.eql(u8, headers[6].value, "true"));

    expect(response.body.len == 196);
}

test "Get with headers" {
    var client = try Client.init(std.testing.allocator);
    defer client.deinit();

    var headers = Headers.init(std.testing.allocator);
    defer headers.deinit();
    try headers.append("Gotta-go", "Fast!");

    var response = try client.get("http://httpbin.org/headers", .{ .headers = headers.items()});
    defer response.deinit();

    expect(response.status == .Ok);

    var tree = try response.json();
    defer tree.deinit();

    var value = tree.root.Object.get("headers").?.Object.get("Gotta-Go").?.String;
    expect(std.mem.eql(u8, value, "Fast!"));
}

test "Get with compile-time headers" {
    var client = try Client.init(std.testing.allocator);
    defer client.deinit();

    var headers = .{
        .{"Gotta-go", "Fast!"}
    };

    var response = try client.get("http://httpbin.org/headers", .{ .headers = headers});
    defer response.deinit();

    expect(response.status == .Ok);

    var tree = try response.json();
    defer tree.deinit();

    var value = tree.root.Object.get("headers").?.Object.get("Gotta-Go").?.String;
    expect(std.mem.eql(u8, value, "Fast!"));
}

test "Post binary data" {
    var client = try Client.init(std.testing.allocator);
    defer client.deinit();

    var response = try client.post("http://httpbin.org/post", .{ .content = "Gotta go fast!"});
    defer response.deinit();

    expect(response.status == .Ok);

    var tree = try response.json();
    defer tree.deinit();

    var data = tree.root.Object.get("data").?.String;
    expect(std.mem.eql(u8, data, "Gotta go fast!"));
}
