const Allocator = std.mem.Allocator;
const Header = @import("http").Header;
const Headers = @import("http").Headers;
const Method = @import("http").Method;
const std = @import("std");
const Uri = @import("http").Uri;
const Version = @import("http").Version;


const BodyType = enum {
    ContentLength,
    Empty,
};

const Body = union(BodyType) {
    ContentLength: struct {
        length: []const u8,
        content: []const u8
    },
    Empty: void,
};

pub const Request = struct {
    allocator: *Allocator,
    headers: Headers,
    ip: ?[]const u8,
    method: Method,
    path: []const u8,
    uri: Uri,
    version: Version,
    body: Body,

    pub fn deinit(self: *Request) void {
        if (self.ip != null) {
            self.allocator.free(self.ip.?);
        }
        self.headers.deinit();

        switch(self.body) {
            .ContentLength => |*body| {
                self.allocator.free(body.length);
            },
            else => {}
        }
    }

    pub fn init(allocator: *Allocator, method: Method, uri: Uri, options: anytype) !Request {
        var path = if (uri.path.len != 0) uri.path else "/";
        var request = Request {
            .allocator = allocator,
            .body = Body.Empty,
            .headers = Headers.init(allocator),
            .ip = null,
            .method = method,
            .path = path,
            .uri = uri,
            .version = Version.Http11,
        };

        switch(request.uri.host) {
            .ip => |address|{
                request.ip = try std.fmt.allocPrint(allocator, "{}", .{address});
                try request.headers.append("Host", request.ip.?);
            },
            .name => |name| {
                try request.headers.append("Host", name);
            }
        }

        if (@hasField(@TypeOf(options), "headers")) {
            var user_headers = getUserHeaders(options.headers);
            try request.headers._items.appendSlice(user_headers);
        }

        if (@hasField(@TypeOf(options), "version")) {
            request.options = options.version;
        }

        if (@hasField(@TypeOf(options), "content")) {
            var content_length = std.fmt.allocPrint(allocator, "{d}", .{options.content.len}) catch unreachable;
            try request.headers.append("Content-Length", content_length);
            request.body = Body {
                .ContentLength = .{
                    .length = content_length,
                    .content = options.content,
                }
            };
        }

        return request;
    }

    fn getUserHeaders(user_headers: anytype) []Header {
        const typeof = @TypeOf(user_headers);
        const typeinfo = @typeInfo(typeof);

        switch(typeinfo) {
            .Struct => |obj| {
                return Header.as_slice(user_headers);
            },
            .Pointer => |ptr| {
                return user_headers;
            },
            else => {
                @compileError("Invalid headers type: You must provide either a http.Headers or an anonymous struct literal.");
            }
        }
    }
};


const expect = std.testing.expect;

test "Request" {
    const uri = try Uri.parse("http://ziglang.org/news/", false);
    var request = try Request.init(std.testing.allocator, .Get, uri, .{});
    defer request.deinit();

    expect(request.method == .Get);
    expect(request.version == .Http11);
    expect(std.mem.eql(u8, request.headers.items()[0].name.raw(), "Host"));
    expect(std.mem.eql(u8, request.headers.items()[0].value, "ziglang.org"));
    expect(std.mem.eql(u8, request.path, "/news/"));
    expect(request.body == .Empty);
}

test "Request - Path defaults to /" {
    const uri = try Uri.parse("http://ziglang.org", false);
    var request = try Request.init(std.testing.allocator, .Get, uri, .{});
    defer request.deinit();

    expect(std.mem.eql(u8, request.path, "/"));
}

test "Request - With user headers" {
    const uri = try Uri.parse("http://ziglang.org/news/", false);

    var headers = Headers.init(std.testing.allocator);
    defer headers.deinit();
    try headers.append("Gotta-go", "Fast!");

    var request = try Request.init(std.testing.allocator, .Get, uri, .{ .headers = headers.items()});
    defer request.deinit();

    expect(std.mem.eql(u8, request.headers.items()[0].name.raw(), "Host"));
    expect(std.mem.eql(u8, request.headers.items()[0].value, "ziglang.org"));
    expect(std.mem.eql(u8, request.headers.items()[1].name.raw(), "Gotta-go"));
    expect(std.mem.eql(u8, request.headers.items()[1].value, "Fast!"));
}

test "Request - With compile time user headers" {
    const uri = try Uri.parse("http://ziglang.org/news/", false);

    var headers = .{
        .{"Gotta-go", "Fast!"}
    };
    var request = try Request.init(std.testing.allocator, .Get, uri, .{ .headers = headers});
    defer request.deinit();

    expect(std.mem.eql(u8, request.headers.items()[0].name.raw(), "Host"));
    expect(std.mem.eql(u8, request.headers.items()[0].value, "ziglang.org"));
    expect(std.mem.eql(u8, request.headers.items()[1].name.raw(), "Gotta-go"));
    expect(std.mem.eql(u8, request.headers.items()[1].value, "Fast!"));
}

test "Request - With IP address" {
    const uri = try Uri.parse("http://127.0.0.1:8080/", false);
    var request = try Request.init(std.testing.allocator, .Get, uri, .{});
    defer request.deinit();

    expect(std.mem.eql(u8, request.ip.?, "127.0.0.1:8080"));
    expect(std.mem.eql(u8, request.headers.items()[0].name.raw(), "Host"));
    expect(std.mem.eql(u8, request.headers.items()[0].value, "127.0.0.1:8080"));
}

test "Request - With content" {
    const uri = try Uri.parse("http://ziglang.org/news/", false);
    var request = try Request.init(std.testing.allocator, .Get, uri, .{ .content = "Gotta go fast!"});
    defer request.deinit();

    expect(request.body == .ContentLength);
    expect(std.mem.eql(u8, request.headers.items()[0].name.raw(), "Host"));
    expect(std.mem.eql(u8, request.headers.items()[0].value, "ziglang.org"));
    expect(std.mem.eql(u8, request.headers.items()[1].name.raw(), "Content-Length"));
    expect(std.mem.eql(u8, request.headers.items()[1].value, "14"));

    switch (request.body) {
        .ContentLength => |body| {
            expect(std.mem.eql(u8, body.length, "14"));
            expect(std.mem.eql(u8, body.content, "Gotta go fast!"));
        },
        .Empty => unreachable,
    }
}
