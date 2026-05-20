const Scanner = @This();

start: []const u8,
current: []const u8,
line: u32,

pub fn init(scanner: *Scanner, source: []const u8) void {
    scanner.start = source;
    scanner.current = source;
    scanner.line = 1;
}
