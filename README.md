# Requestz

An HTTP client inspired by [httpx](https://github.com/encode/httpx) and [ureq](https://github.com/algesten/ureq).

[![Build Status](https://api.travis-ci.org/ducdetronquito/requestz.svg?branch=master)](https://travis-ci.org/ducdetronquito/requestz) [![License](https://img.shields.io/badge/License-BSD%200--Clause-ff69b4.svg)](https://github.com/ducdetronquito/requestz#license) [![Requirements](https://img.shields.io/badge/zig-master_(19.08.2021)-orange)](https://ziglang.org/)

⚠️ I'm currently renovating an old house which does not allow me to work on [requestz](https://github.com/ducdetronquito/requestz/), [h11](https://github.com/ducdetronquito/h11/) and [http](https://github.com/ducdetronquito/http) as much as I would like to. Further development will likely to start again around december 2022. In the meantime, feel free to fork :)

## Installation

*requestz* is available on [astrolabe.pm](https://astrolabe.pm/) via [gyro](https://github.com/mattnite/gyro)

```
gyro add ducdetronquito/requestz
```

## Usage

Send a GET request
```zig
const client = @import("requestz.zig").Client;

var client = try Client.init(std.testing.allocator);
defer client.deinit();

var response = try client.get("http://httpbin.org/get", .{});
defer response.deinit();
```

Send a request with headers
```zig
const Headers = @import("http").Headers;

var headers = Headers.init(std.testing.allocator);
defer headers.deinit();
try headers.append("Gotta-go", "Fast!");

var response = try client.get("http://httpbin.org/get", .{ .headers = headers.items() });
defer response.deinit();
```

Send a request with compile-time headers
```zig
var headers = .{
    .{"Gotta-go", "Fast!"}
};

var response = try client.get("http://httpbin.org/get", .{ .headers = headers });
defer response.deinit();
```

Send binary data along with a POST request
```zig
var response = try client.post("http://httpbin.org/post", .{ .content = "Gotta go fast!" });
defer response.deinit();

var tree = try response.json();
defer tree.deinit();
```

Stream a response
```zig
var response = try client.stream(.Get, "http://httpbin.org/", .{});
defer response.deinit();

while(true) {
    var buffer: [4096]u8 = undefined;
    var bytesRead = try response.read(&buffer);
    if (bytesRead == 0) {
        break;
    }
    std.debug.print("{}", .{buffer[0..bytesRead]});
}
```

Other standard HTTP method shortcuts:
- `client.connect`
- `client.delete`
- `client.head`
- `client.options`
- `client.patch`
- `client.put`
- `client.trace`

## Dependencies

- [h11](https://github.com/ducdetronquito/h11)
- [http](https://github.com/ducdetronquito/http)
- [iguanaTLS](https://github.com/alexnask/iguanaTLS)
- [zig-network](https://github.com/MasterQ32/zig-network)

## License

*requestz* is released under the [BSD Zero clause license](https://choosealicense.com/licenses/0bsd/). 🎉🍻
