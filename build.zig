const Builder = @import("std").build.Builder;
const pkgs = @import("deps.zig").pkgs;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const lib = b.addStaticLibrary("requestz", "src/main.zig");
    pkgs.addAllTo(lib);
    lib.setBuildMode(mode);
    lib.install();

    var main_tests = b.addTest("src/tests.zig");
    pkgs.addAllTo(main_tests);
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
