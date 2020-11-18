const Allocator = @import("std").mem.Allocator;
const network = @import("network");


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