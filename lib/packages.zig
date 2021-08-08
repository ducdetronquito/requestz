const std = @import("std");

pub const network = std.build.Pkg {
    .name = "network",
    .path = "lib/zig-network/network.zig",
    .dependencies = null,
};

pub const iguanaTLS = std.build.Pkg {
    .name = "iguanaTLS",
    .path = "lib/iguanaTLS/src/main.zig",
    .dependencies = null,
};

pub const http = std.build.Pkg {
    .name = "http",
    .path = "lib/h11/lib/http/src/main.zig",
    .dependencies = null,
};

var h11_dependencies = [_]std.build.Pkg{
    http,
};

pub const h11 = std.build.Pkg {
    .name = "h11",
    .path = "lib/h11/src/main.zig",
    .dependencies = &h11_dependencies,
};
