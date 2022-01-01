const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const h11 = @import("h11");
const Headers = @import("http").Headers;
const Header = @import("http").Header;
const JsonParser = std.json.Parser;
const StatusCode = @import("http").StatusCode;
const std = @import("std");
const Version = @import("http").Version;
const ValueTree = std.json.ValueTree;
const Connection = @import("connection.zig").Connection;

pub const Response = struct {
    arena: ArenaAllocator,
    status: StatusCode,
    version: Version,
    headers: []Header,
    body: []u8,

    pub fn deinit(self: *Response) void {
        self.arena.deinit();
    }

    pub fn json(self: Response) !ValueTree {
        var parser = JsonParser.init(self.arena.allocator(), false);
        defer parser.deinit();

        return try parser.parse(self.body);
    }
};

pub fn StreamingResponse(comptime ConnectionType: type) type {
    return struct {
        const Self = @This();
        arena: ArenaAllocator,
        connection: *ConnectionType,
        headers: []Header,
        status: StatusCode,
        version: Version,

        pub fn deinit(self: *Self) void {
            self.arena.deinit();
            self.connection.deinit();
        }

        pub fn read(self: *Self, buffer: []u8) !usize {
            var event = try self.connection.nextEvent(buffer);
            switch (event) {
                .Data => |data| return data.bytes.len,
                .EndOfMessage => return 0,
                else => unreachable,
            }
        }
    };
}
