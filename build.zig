const Builder = @import("std").build.Builder;
const packages = @import("lib/packages.zig");

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const lib = b.addStaticLibrary("requestz", "src/main.zig");
    lib.addPackage(packages.network);
    lib.addPackage(packages.h11);
    lib.addPackage(packages.http);
    lib.setBuildMode(mode);
    lib.install();

    var main_tests = b.addTest("src/tests.zig");
    main_tests.addPackage(packages.network);
    main_tests.addPackage(packages.h11);
    main_tests.addPackage(packages.http);
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
