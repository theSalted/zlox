const Scanner = @import("Scanner.zig");

pub fn compile(source: []const u8) void {
    var scanner: Scanner = undefined;
    scanner.init(source);
}
