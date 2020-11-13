const Allocator = std.mem.Allocator;
const Headers = @import("http").Headers;
const JsonParser = std.json.Parser;
const StatusCode = @import("http").StatusCode;
const std = @import("std");
const Version = @import("http").Version;
const ValueTree = std.json.ValueTree;


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
