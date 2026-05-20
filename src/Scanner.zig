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
    scanner.start = scanner.current;

    if (scanner.isAtEnd()) {
        return scanner.makeToken(.eof);
    }

    const c: u8 = scanner.advance();

    switch (c) {
        '(' => return scanner.makeToken(.left_paren),
        ')' => return scanner.makeToken(.right_paren),
        '{' => return scanner.makeToken(.left_brace),
        '}' => return scanner.makeToken(.right_brace),
        ';' => return scanner.makeToken(.semicolon),
        ',' => return scanner.makeToken(.comma),
        '.' => return scanner.makeToken(.dot),
        '-' => return scanner.makeToken(.minus),
        '+' => return scanner.makeToken(.plus),
        '/' => return scanner.makeToken(.slash),
        '*' => return scanner.makeToken(.star),
        '!' => {
            return scanner.makeToken(if (scanner.match('=')) .bang_equal else .bang);
        },
        '=' => {
            return scanner.makeToken(if (scanner.match('=')) .equal_equal else .equal);
        },
        '<' => {
            return scanner.makeToken(if (scanner.match('=')) .less_equal else .less);
        },
        '>' => {
            return scanner.makeToken(if (scanner.match('=')) .greater_equal else .greater);
        },
    }
    return scanner.errorToken("Unexpected character.");
}

fn advance(scanner: *Scanner) u8 {
    scanner.current += 1;
    return scanner.current[-1];
}

fn match(scanner: *Scanner, expected: u8) bool {
    if (scanner.isAtEnd()) return false;
    if (scanner.current[-1] != expected) return false;
    scanner.current += 1;
    return true;
}

fn makeToken(scanner: *Scanner, token_type: TokenType) Token {
    return Token{
        .type = token_type,
        .start = scanner.start.ptr,
        .length = scanner.start.len - scanner.current.len,
        .line = scanner.line,
    };
}

fn errorToken(scanner: *Scanner, message: []const u8) Token {
    return Token{
        .type = .@"error",
        .start = message.ptr,
        .length = message.len,
        .line = scanner.line,
    };
}

fn isAtEnd(scanner: *Scanner) bool {
    return scanner.current.len == 0;
}
