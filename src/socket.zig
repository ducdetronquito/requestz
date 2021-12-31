const Address = std.net.Address;
const Allocator = std.mem.Allocator;
const LinearFifo = std.fifo.LinearFifo;
const network = @import("network");
const std = @import("std");
const tls = @import("iguanaTLS");
const Uri = @import("http").Uri;

pub const TcpSocket = SocketWrapper(ZigNetwork);
pub const SocketMock = SocketWrapper(NetworkMock);

fn SocketWrapper(comptime Engine: type) type {
    return struct {
        target: Engine.Socket,
        tls_context: TlsContext = undefined,

        const Self = @This();
        pub const Reader = std.io.Reader(Self, Engine.Socket.ReceiveError, read);
        pub const Writer = std.io.Writer(Self, Engine.Socket.SendError, write);
        const TlsContext = tls.Client(Engine.Socket.Reader, Engine.Socket.Writer, tls.ciphersuites.all, true);

        pub fn connect(allocator: Allocator, uri: Uri) !Self {
            var defaultPort: u16 = if (std.mem.eql(u8, uri.scheme, "https")) 443 else 80;
            var port: u16 = uri.port orelse defaultPort;
            var socket = switch (uri.host) {
                .name => |host| try Self.connectToHost(allocator, host, port),
                .ip => |address| try Self.connectToAddress(allocator, address),
            };

            return Self{ .target = socket };
        }

        pub fn close(self: *Self) void {
            self.target.close();
        }

        pub fn writer(self: Self) Writer {
            return .{ .context = self };
        }

        pub fn reader(self: Self) Reader {
            return .{ .context = self };
        }

        pub fn read(self: Self, buffer: []u8) !usize {
            return self.target.receive(buffer);
        }

        pub fn write(self: Self, buffer: []const u8) !usize {
            return self.target.send(buffer);
        }

        fn connectToHost(allocator: Allocator, host: []const u8, port: u16) !Engine.Socket {
            return try Engine.connectToHost(allocator, host, port, .tcp);
        }

        fn connectToAddress(_: Allocator, address: Address) !Engine.Socket {
            switch (address.any.family) {
                std.os.AF.INET => {
                    const bytes = @ptrCast(*const [4]u8, &address.in.sa.addr);
                    var ipv4 = network.Address{ .ipv4 = network.Address.IPv4.init(bytes[0], bytes[1], bytes[2], bytes[3]) };
                    var port = address.getPort();
                    var endpoint = network.EndPoint{ .address = ipv4, .port = port };

                    var socket = try Engine.Socket.create(.ipv4, .tcp);
                    try socket.connect(endpoint);
                    return socket;
                },
                else => unreachable,
            }
        }
    };
}

const ZigNetwork = struct {
    const Socket = network.Socket;

    fn connectToHost(allocator: Allocator, host: []const u8, port: u16, protocol: network.Protocol) !Socket {
        return try network.connectToHost(allocator, host, port, protocol);
    }
};

const NetworkMock = struct {
    const Socket = InMemorySocket;

    pub fn connectToHost(allocator: Allocator, host: []const u8, port: u16, protocol: network.Protocol) !Socket {
        _ = allocator;
        _ = host;
        _ = port;
        _ = protocol;
        return try Socket.create(.{}, .{});
    }
};

const InMemorySocket = struct {
    const Context = struct {
        read_buffer: ReadBuffer,
        write_buffer: WriteBuffer,

        const ReadBuffer = LinearFifo(u8, .Dynamic);
        const WriteBuffer = std.ArrayList(u8);

        pub fn create() !*Context {
            var context = try std.mem.Allocator.create(std.testing.allocator, Context);
            context.read_buffer = ReadBuffer.init(std.testing.allocator);
            context.write_buffer = WriteBuffer.init(std.testing.allocator);
            return context;
        }

        pub fn deinit(self: *Context) void {
            self.read_buffer.deinit();
            self.write_buffer.deinit();
        }
    };

    context: *Context,

    pub const Reader = std.io.Reader(InMemorySocket, ReceiveError, receive);
    pub const ReceiveError = anyerror;
    pub const Writer = std.io.Writer(InMemorySocket, SendError, send);
    pub const SendError = anyerror;

    pub fn create(address: anytype, protocol: anytype) !InMemorySocket {
        _ = address;
        _ = protocol;
        return InMemorySocket{ .context = try Context.create() };
    }

    pub fn close(self: InMemorySocket) void {
        self.context.deinit();
        std.mem.Allocator.destroy(std.testing.allocator, self.context);
    }

    pub fn connect(self: InMemorySocket, options: anytype) !void {
        _ = self;
        _ = options;
    }

    pub fn has_sent(self: InMemorySocket, data: []const u8) bool {
        return std.mem.eql(u8, self.context.write_buffer.items, data);
    }

    pub fn has_received(self: InMemorySocket, data: []const u8) !void {
        try self.context.read_buffer.write(data);
    }

    pub fn receive(self: InMemorySocket, dest: []u8) !usize {
        return self.context.read_buffer.read(dest);
    }

    pub fn send(self: InMemorySocket, bytes: []const u8) !usize {
        self.context.write_buffer.appendSlice(bytes) catch unreachable;
        return bytes.len;
    }

    pub fn reader(self: InMemorySocket) Reader {
        return .{ .context = self };
    }

    pub fn writer(self: InMemorySocket) Writer {
        return .{ .context = self };
    }
};
