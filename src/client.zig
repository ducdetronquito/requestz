const Allocator = std.mem.Allocator;
const Connection = @import("connection.zig").Connection;
const Method = @import("http").Method;
const network = @import("network");
const Response = @import("response.zig").Response;
const std = @import("std");


pub const Client = struct {
    allocator: *Allocator,

    pub fn init(allocator: *Allocator) !Client {
        try network.init();
        return Client { .allocator = allocator };
    }

    pub fn deinit(self: *Client) void {
        network.deinit();
    }

    fn get_connection(self: Client) Connection {
        return Connection.init(self.allocator);
    }

    pub fn get(self: Client, url: []const u8, options: anytype) !Response {
        return self.request(.Get, url, options);
    }

    pub fn request(self: Client, method: Method, url: []const u8, options: anytype) !Response {
        var connection = self.get_connection();
        defer connection.deinit();

        return connection.request(method, url, options);
    }
};


const expect = std.testing.expect;

test "Get" {
    var client = try Client.init(std.testing.allocator);
    defer client.deinit();

    var response = try client.get("http://httpbin.org/get", .{});
    defer response.deinit();

    expect(response.status == .Ok);
    expect(response.version == .Http11);
    var headers = response.headers.items();
    // TODO:
    // We get random segfault when accessing the headers data.
    // This is caused when the http message comes in two parts.
    // The first part allows to parse the headers into the response event.
    // Then the second part contains the body, and when adding this part to the buffer
    // it invalidates the slice of the headers.
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
}
