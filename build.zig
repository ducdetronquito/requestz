const Builder = @import("std").build.Builder;
const deps = @import("deps.zig");

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const lib = b.addStaticLibrary("requestz", "src/main.zig");
    lib.setBuildMode(mode);
    deps.addAllTo(lib);
    lib.install();

    var main_tests = b.addTest("src/tests.zig");
    main_tests.setBuildMode(mode);
    deps.addAllTo(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
