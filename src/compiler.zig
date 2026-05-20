const std = @import("std");

const print = std.debug.print;

const Scanner = @import("Scanner.zig");

pub fn compile(source: []const u8) void {
    var scanner: Scanner = undefined;
    scanner.init(source);

    var line: i32 = -1;

    while (true) {
        const token = scanner.scanToken();

        if (token.line != line) {
            print("{d:<4} ", .{token.line});
            line = token.line;
        } else {
            print("    | ", .{});
        }

        print("{d:<2} '{s}'\n", .{ @intFromEnum(token.type), token.start[0..token.length] });

        if (token.type == .eof) break;
    }
}
