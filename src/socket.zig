const Address = std.net.Address;
const Allocator = std.mem.Allocator;
const LinearFifo = std.fifo.LinearFifo;
const network = @import("network");
const std = @import("std");
const Uri = @import("http").Uri;


pub const Socket = struct {
    target: network.Socket,

    pub fn connect(allocator: *Allocator, uri: Uri) !Socket {
        const port = uri.port orelse 80;
        var socket = switch(uri.host) {
            .name => |host| try Socket.connectToHost(allocator, host, port),
            .ip => |address| try Socket.connecToAddress(allocator, address),
        };

        return Socket { .target = socket };
    }

    fn connectToHost(allocator: *Allocator, host: []const u8, port: u16) !network.Socket {
        return try network.connectToHost(allocator, host, port, .tcp);
    }

    fn connecToAddress(allocator: *Allocator, address: Address) !network.Socket {
        switch(address.any.family) {
            std.os.AF_INET => {
                var socket = try network.Socket.create(.ipv4, .tcp);
                const bytes = @ptrCast(*const [4]u8, &address.in.sa.addr);
                try socket.connect(.{
                    .address = .{ .ipv4 = network.Address.IPv4.init(bytes[0], bytes[1], bytes[2], bytes[3]) },
                    .port = address.getPort(),
                });
                return socket;
            },
            else => unreachable,
        }
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
    receive_buffer: LinearFifo([]u8, .Dynamic),
    write_buffer: std.ArrayList(u8),

    pub fn connect(allocator: *Allocator, uri: Uri) !SocketMock {
        return SocketMock {
            .allocator = allocator,
            .receive_buffer = LinearFifo([]u8, .Dynamic).init(allocator),
            .write_buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn receive(self: *SocketMock, buffer: []u8) !usize {
        var result = self.receive_buffer.readItem() orelse unreachable;
        defer self.allocator.free(result);

        std.mem.copy(u8, buffer, result);
        return result.len;
    }

    pub fn write(self: *SocketMock, buffer: []const u8) !void {
        try self.write_buffer.appendSlice(buffer);
    }

    pub fn close(self: *SocketMock) void {
        self.receive_buffer.deinit();
        self.write_buffer.deinit();
    }

    pub fn have_received(self: *SocketMock, data: []const u8) !void {
        var copy = try std.mem.dupe(self.allocator, u8, data);
        try self.receive_buffer.writeItem(copy);
    }

    pub fn have_sent(self: *SocketMock, data: []const u8) bool {
        return std.mem.eql(u8, self.write_buffer.items, data);
    }
};
