# Requestz

An HTTP/1.1 client inspired by [ureq](https://github.com/algesten/ureq).

[![Build Status](https://api.travis-ci.org/ducdetronquito/requestz.svg?branch=master)](https://travis-ci.org/ducdetronquito/requestz) [![License](https://img.shields.io/badge/license-public%20domain-ff69b4.svg)](https://github.com/ducdetronquito/requestz#license) [![Requirements](https://img.shields.io/badge/zig-0.6.0-orange)](https://ziglang.org/)

## Usage

```zig
const requestz = @import("requestz.zig");
const std = @import("std");

const response = try requestz.post("http://yumad.bro/)
    .set("X-My-Header", "Ziguana")
    .json("{\"What the fox says?\": \"PAPAPAPAPAPAPA\"}")
    .send();


if (response.is_success()) {
    std.debug.warn("POGHAMP, it's a {} response.", .{response.status()});
} else {
    std.debug.warn("Bob, you didn't make a mistake, just a happy little accident.", .{});
}
```


## Requirements

To work with *requestz* you will need the latest stable version of Zig, which is currently Zig 0.6.0.


## License

*requestz* is released into the Public Domain. 🎉🍻
