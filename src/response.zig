const Allocator = @import("std").mem.Allocator;
const Headers = @import("http").Headers;
const StatusCode = @import("http").StatusCode;
const Version = @import("http").Version;

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
};
