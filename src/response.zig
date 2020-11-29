const Allocator = std.mem.Allocator;
const h11 = @import("h11");
const Headers = @import("http").Headers;
const JsonParser = std.json.Parser;
const StatusCode = @import("http").StatusCode;
const std = @import("std");
const Version = @import("http").Version;
const ValueTree = std.json.ValueTree;
const Connection = @import("connection.zig").Connection;


pub const Response = struct {
    allocator: *Allocator,
    buffer: []const u8,
    status: StatusCode,
    version: Version,
    headers: Headers,
    body: []const u8,

    pub fn deinit(self: *Response) void {
        self.headers.deinit();
        self.allocator.free(self.buffer);
        self.allocator.free(self.body);
    }

    pub fn json(self: Response) !ValueTree {
        var parser = JsonParser.init(self.allocator, false);
        defer parser.deinit();

        return try parser.parse(self.body);
    }
};


pub fn StreamingResponse(comptime ConnectionType: type) type {
    return struct {
        const Self = @This();
        allocator: *Allocator,
        buffer: []const u8,
        connection: *ConnectionType,
        headers: Headers,
        status: StatusCode,
        version: Version,

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.buffer);
            self.headers.deinit();
            self.connection.deinit();
        }

        pub fn next_chunk(self: *Self) !?[]const u8 {
            var event = try self.connection.nextEvent();
            return switch (event) {
                .Data => |data| {
                    return data.content;
                },
                else => null,
            };
        }
    };
}
