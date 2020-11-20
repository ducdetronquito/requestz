
const Allocator = std.mem.Allocator;
const network = @import("network");
const std = @import("std");


pub const Socket = struct {
    target: network.Socket,

    pub fn connect(allocator: *Allocator, host: []const u8, port: u16) !Socket {
        var _socket = try network.connectToHost(allocator, host, port, .tcp);
        return Socket {
            .target = _socket
        };
    }

    pub fn receive(self: Socket, buffer: []u8) !usize {
        return try self.target.receive(buffer);
    }

    pub fn write(self: Socket, buffer: []const u8) !void {
        try self.target.writer().writeAll(buffer);
    }

    pub fn close(self: *Socket) void {
        self.target.close();
    }
};


pub const SocketMock = struct {
    allocator: *Allocator,
    receive_buffer: std.ArrayList([]const u8),
    write_buffer: std.ArrayList(u8),

    pub fn connect(allocator: *Allocator, host: []const u8, port: u16) !SocketMock {
        return SocketMock {
            .allocator = allocator,
            .receive_buffer = std.ArrayList([]const u8).init(allocator),
            .write_buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn receive(self: *SocketMock, buffer: []u8) !usize {
        var result = self.receive_buffer.pop();
        defer self.allocator.free(result);

        std.mem.copy(u8, buffer, result);
        return result.len;
    }

    pub fn write(self: *SocketMock, buffer: []const u8) !void {
        try self.write_buffer.appendSlice(buffer);
    }

    pub fn close(self: *SocketMock) void {
        for (self.receive_buffer.items) |chunk| {
            self.allocator.free(chunk);
        }
        self.receive_buffer.deinit();

        self.write_buffer.deinit();
    }

    pub fn have_received(self: *SocketMock, data: []const u8) !void {
        var copy = try std.mem.dupe(self.allocator, u8, data);
        try self.receive_buffer.append(copy);
    }

    pub fn have_sent(self: *SocketMock, data: []const u8) bool {
        return std.mem.eql(u8, self.write_buffer.items, data);
    }
};
