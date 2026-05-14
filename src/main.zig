const std = @import("std");
const VM = @import("VM.zig");
const Chunk = @import("Chunk.zig");
const debug = @import("debug.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len == 1) {
        try repl(io);
    } else if (args.len == 2) {
        // try runFile(allocator, args[1]);
    } else {
        std.debug.print("Usage: zlox [path]\n", .{});
        std.process.exit(1);
    }
}

fn repl(io: std.Io) !void {
    var line_buf: [1024]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(io, &line_buf);
    const stdin = &stdin_reader.interface;

    var stdout_writer = std.Io.File.stdout().writer(io, &.{});
    const stdout = &stdout_writer.interface;

    while (true) {
        try stdout.writeAll("> ");

        const line = stdin.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.EndOfStream => {
                try stdout.writeAll("\n");
                return;
            },
            error.StreamTooLong => {
                try stdout.writeAll("Line too long\n");
                stdin.toss(line_buf.len);
                continue;
            },
            else => |e| return e,
        };

        // try interpret(line);
        _ = line;
    }
}

// fn runFile()
