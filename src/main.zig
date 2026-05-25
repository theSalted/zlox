const std = @import("std");
const VM = @import("VM.zig");
const Chunk = @import("Chunk.zig");
const debug = @import("debug.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    var vm: VM = undefined;
    vm.init(init.gpa);
    defer vm.free();

    if (args.len == 1) {
        try repl(io, &vm);
    } else if (args.len == 2) {
        try runFile(io, init.gpa, &vm, args[1]);
    } else {
        std.debug.print("Usage: zlox [path]\n", .{});
        std.process.exit(1);
    }
}

fn repl(io: std.Io, vm: *VM) !void {
    var line_buf: [1024]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(io, &line_buf);
    const stdin = &stdin_reader.interface;

    var stdout_writer = std.Io.File.stdout().writer(io, &.{});
    const stdout = &stdout_writer.interface;

    while (true) {
        try stdout.writeAll("> ");

        const maybe_line = stdin.takeDelimiter('\n') catch |err| switch (err) {
            error.StreamTooLong => {
                try stdout.writeAll("Line too long\n");
                stdin.toss(line_buf.len);
                continue;
            },
            else => |e| return e,
        };

        const line = maybe_line orelse {
            try stdout.writeAll("\n");
            return;
        };

        _ = vm.interpret(line);
    }
}

fn runFile(io: std.Io, allocator: std.mem.Allocator, vm: *VM, path: []const u8) !void {
    const source = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => {
            std.debug.print("File not found: {s}\n", .{path});
            std.process.exit(74);
        },
        else => |e| return e,
    };
    defer allocator.free(source);

    const result = vm.interpret(source);
    switch (result) {
        .interpret_ok => {},
        .interpret_compile_error => std.process.exit(65),
        .interpret_runtime_error => std.process.exit(70),
    }
}
