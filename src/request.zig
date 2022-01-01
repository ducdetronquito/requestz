const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;
const http = @import("http");
const Header = http.Header;
const Headers = http.Headers;
const Method = http.Method;
const std = @import("std");
const Uri = http.Uri;
const Version = http.Version;

const BodyType = enum {
    ContentLength,
    Empty,
};

const Body = union(BodyType) {
    ContentLength: struct { length: []const u8, content: []const u8 },
    Empty: void,
};

pub const Request = struct {
    arena: ArenaAllocator,
    body: Body,
    method: Method,
    path: []const u8,
    uri: Uri,
    headers: Headers,
    version: Version,

    pub fn deinit(self: *Request) void {
        self.arena.deinit();
    }

    pub fn init(allocator: Allocator, method: Method, uri: Uri, options: anytype) !Request {
        var arena = ArenaAllocator.init(allocator);
        const _allocator = arena.allocator();
        errdefer arena.deinit();

        const path = if (uri.path.len != 0) uri.path else "/";
        var headers = Headers.init(_allocator);

        switch (uri.host) {
            .ip => |address| {
                const ip = try std.fmt.allocPrint(_allocator, "{}", .{address});
                const header = try Header.init(try _allocator.dupe(u8, "Host"), try _allocator.dupe(u8, ip));
                try headers.append(header);
            },
            .name => |domain| {
                const header = try Header.init(try _allocator.dupe(u8, "Host"), try _allocator.dupe(u8, domain));
                try headers.append(header);
            },
        }

        if (@hasField(@TypeOf(options), "headers")) {
            var user_headers = getUserHeaders(options.headers);
            try headers._items.appendSlice(user_headers);
        }

        var version = Version.Http11;
        if (@hasField(@TypeOf(options), "version")) {
            version = options.version;
        }

        var body: Body = Body.Empty;
        if (@hasField(@TypeOf(options), "content")) {
            const content_length = try std.fmt.allocPrint(_allocator, "{d}", .{options.content.len});
            const header = try Header.init("Content-Length", content_length);
            try headers.append(header);
            body = Body{ .ContentLength = .{
                .length = content_length,
                .content = options.content,
            } };
        }

        return Request{
            .arena = arena,
            .body = body,
            .headers = headers,
            .method = method,
            .path = path,
            .uri = uri,
            .version = version,
        };
    }

    fn getUserHeaders(user_headers: anytype) []Header {
        const typeof = @TypeOf(user_headers);
        const typeinfo = @typeInfo(typeof);

        return switch (typeinfo) {
            .Struct => Header.as_slice(user_headers),
            .Pointer => user_headers,
            else => {
                @compileError("Invalid headers type: You must provide either a http.Headers or an anonymous struct literal.");
            },
        };
    }
};

const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;

test "Request" {
    const uri = try Uri.parse("http://ziglang.org/news/", false);
    var request = try Request.init(std.testing.allocator, .Get, uri, .{});
    defer request.deinit();

    try expect(request.method == .Get);
    try expect(request.version == .Http11);

    try expectEqualStrings(request.headers.items()[0].name.raw(), "Host");
    try expectEqualStrings(request.headers.items()[0].value, "ziglang.org");
    try expectEqualStrings(request.path, "/news/");
    try expect(request.body == .Empty);
}

test "Request - Path defaults to /" {
    const uri = try Uri.parse("http://ziglang.org", false);
    var request = try Request.init(std.testing.allocator, .Get, uri, .{});
    defer request.deinit();

    try expectEqualStrings(request.path, "/");
}

test "Request - With user headers" {
    const uri = try Uri.parse("http://ziglang.org/news/", false);

    var headers = Headers.init(std.testing.allocator);
    defer headers.deinit();
    try headers.append(try Header.init("Gotta-go", "Fast!"));

    var request = try Request.init(std.testing.allocator, .Get, uri, .{ .headers = headers.items() });
    defer request.deinit();

    try expectEqualStrings(request.headers.items()[0].name.raw(), "Host");
    try expectEqualStrings(request.headers.items()[0].value, "ziglang.org");
    try expectEqualStrings(request.headers.items()[1].name.raw(), "Gotta-go");
    try expectEqualStrings(request.headers.items()[1].value, "Fast!");
}

test "Request - With compile time user headers" {
    const uri = try Uri.parse("http://ziglang.org/news/", false);

    var headers = .{.{ "Gotta-go", "Fast!" }};
    var request = try Request.init(std.testing.allocator, .Get, uri, .{ .headers = headers });
    defer request.deinit();

    try expectEqualStrings(request.headers.items()[0].name.raw(), "Host");
    try expectEqualStrings(request.headers.items()[0].value, "ziglang.org");
    try expectEqualStrings(request.headers.items()[1].name.raw(), "Gotta-go");
    try expectEqualStrings(request.headers.items()[1].value, "Fast!");
}

test "Request - With IP address" {
    const uri = try Uri.parse("http://127.0.0.1:8080/", false);
    var request = try Request.init(std.testing.allocator, .Get, uri, .{});
    defer request.deinit();

    try expectEqualStrings(request.headers.items()[0].name.raw(), "Host");
    try expectEqualStrings(request.headers.items()[0].value, "127.0.0.1:8080");
}

test "Request - With content" {
    const uri = try Uri.parse("http://ziglang.org/news/", false);
    var request = try Request.init(std.testing.allocator, .Get, uri, .{ .content = "Gotta go fast!" });
    defer request.deinit();

    try expect(request.body == .ContentLength);
    try expectEqualStrings(request.headers.items()[0].name.raw(), "Host");
    try expectEqualStrings(request.headers.items()[0].value, "ziglang.org");
    try expectEqualStrings(request.headers.items()[1].name.raw(), "Content-Length");
    try expectEqualStrings(request.headers.items()[1].value, "14");
    try expectEqualStrings(request.body.ContentLength.length, "14");
    try expectEqualStrings(request.body.ContentLength.content, "Gotta go fast!");
}
