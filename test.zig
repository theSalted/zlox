const std = @import("std");
const options = @import("options");

const RunResult = struct {
    output: []u8,
    success: bool,

    fn deinit(self: RunResult, allocator: std.mem.Allocator) void {
        allocator.free(self.output);
    }
};

fn runLox(allocator: std.mem.Allocator, source: []const u8) !RunResult {
const io = std.testing.io;
    const file_path = "/tmp/zlox_test_input.lox";

    const file = try std.Io.Dir.createFileAbsolute(io, file_path, .{});
    try file.writeStreamingAll(io, source);
    file.close(io);

    const result = try std.process.run(allocator, io, .{
        .argv = &.{ options.zlox_path, file_path },
    });
    allocator.free(result.stdout);

    const success = switch (result.term) {
        .exited => |code| code == 0,
        else => false,
    };

    return .{ .output = result.stderr, .success = success };
}

test "print string" {
    const r = try runLox(std.testing.allocator, "print \"hello\";");
    defer r.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("hello\n", r.output);
}

test "print number" {
    const r = try runLox(std.testing.allocator, "print 1 + 2;");
    defer r.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("3\n", r.output);
}

test "print boolean" {
    const r = try runLox(std.testing.allocator, "print true;");
    defer r.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("true\n", r.output);
}

test "if true branch" {
    const r = try runLox(std.testing.allocator, "if (true) print \"yes\"; else print \"no\";");
    defer r.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("yes\n", r.output);
}

test "if false branch" {
    const r = try runLox(std.testing.allocator, "if (false) print \"yes\"; else print \"no\";");
    defer r.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("no\n", r.output);
}

test "while loop" {
    const r = try runLox(std.testing.allocator, "var i = 0; while (i < 3) { print i; i = i + 1; }");
    defer r.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("0\n1\n2\n", r.output);
}

test "for loop" {
    const r = try runLox(std.testing.allocator, "for (var i = 0; i < 3; i = i + 1) print i;");
    defer r.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("0\n1\n2\n", r.output);
}

test "global variable" {
    const r = try runLox(std.testing.allocator, "var x = 10; var y = 20; print x + y;");
    defer r.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("30\n", r.output);
}

test "local variable" {
    const r = try runLox(std.testing.allocator, "{ var x = 5; print x; }");
    defer r.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("5\n", r.output);
}

test "string concatenation" {
    const r = try runLox(std.testing.allocator, "print \"hello\" + \" \" + \"world\";");
    defer r.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("hello world\n", r.output);
}

test "string interning equality" {
    const r = try runLox(std.testing.allocator, "print \"hi\" == \"hi\";");
    defer r.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("true\n", r.output);
}

test "undefined variable is runtime error" {
    const r = try runLox(std.testing.allocator, "print x;");
    defer r.deinit(std.testing.allocator);
    try std.testing.expect(!r.success);
}

test "compile error returns failure" {
    const r = try runLox(std.testing.allocator, "var x = ;");
    defer r.deinit(std.testing.allocator);
    try std.testing.expect(!r.success);
}
