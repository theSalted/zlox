pub const TokenType = enum {
    // single character tokens
    left_paren,
    right_paren,
    left_brace,
    right_brace,
    comma,
    dot,
    minus,
    plus,
    semicolon,
    slash,
    star,
    // one or two character tokens
    bang,
    bang_equal,
    equal,
    equal_equal,
    greater,
    greater_equal,
    less,
    less_equal,
    // literals
    identifier,
    string,
    number,
    // keywords
    @"and",
    class,
    @"else",
    false,
    @"for",
    fun,
    @"if",
    nil,
    @"or",
    print,
    @"return",
    super,
    this,
    true,
    @"var",
    @"while",
    @"error",
    eof,
};

pub const Token = struct { type: TokenType, start: [*]const u8, length: usize, line: i32 };

const Scanner = @This();

start: []const u8,
current: []const u8,
line: i32,

pub fn init(scanner: *Scanner, source: []const u8) void {
    scanner.start = source;
    scanner.current = source;
    scanner.line = 1;
}

pub fn scanToken(scanner: *Scanner) Token {
    return .{
        .type = .eof,
        .start = scanner.current.ptr,
        .length = 0,
        .line = scanner.line,
    };
}
