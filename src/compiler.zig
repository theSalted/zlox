const Scanner = @import("scanner.zig");

pub fn compile(source: []const u8) void {
    var scanner: Scanner = undefined;
    scanner.initScanner(source);
}
