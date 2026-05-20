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

pub const Token = struct { type: TokenType, start: [*]const u8, length: usize, line: u32 };

const Scanner = @This();

source: []const u8,
start: usize,
current: usize,
line: u32,

pub fn init(scanner: *Scanner, source: []const u8) void {
    scanner.source = source;
    scanner.start = 0;
    scanner.current = 0;
    scanner.line = 1;
}

pub fn scanToken(scanner: *Scanner) Token {
    scanner.skipWhitespace();

    scanner.start = scanner.current;

    if (scanner.isAtEnd()) {
        return scanner.makeToken(.eof);
    }

    const c: u8 = scanner.advance();

    if (isAlpha(c)) return scanner.identifier();
    if (isDigit(c)) return scanner.number();

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
        '!' => return scanner.makeToken(if (scanner.match('=')) .bang_equal else .bang),
        '=' => return scanner.makeToken(if (scanner.match('=')) .equal_equal else .equal),
        '<' => return scanner.makeToken(if (scanner.match('=')) .less_equal else .less),
        '>' => return scanner.makeToken(if (scanner.match('=')) .greater_equal else .greater),
        '"' => return scanner.string(),

        else => {},
    }

    return scanner.errorToken("Unexpected character.");
}

fn advance(scanner: *Scanner) u8 {
    const c = scanner.source[scanner.current];
    scanner.current += 1;
    return c;
}

fn match(scanner: *Scanner, expected: u8) bool {
    if (scanner.isAtEnd()) return false;
    if (scanner.source[scanner.current] != expected) return false;
    scanner.current += 1;
    return true;
}

fn peek(scanner: *Scanner) u8 {
    if (scanner.isAtEnd()) return 0;
    return scanner.source[scanner.current];
}

fn peekNext(scanner: *Scanner) u8 {
    if (scanner.current + 1 >= scanner.source.len) return 0;
    return scanner.source[scanner.current + 1];
}

fn identifier(scanner: *Scanner) Token {
    while (isAlpha(scanner.peek()) or isDigit(scanner.peek())) _ = scanner.advance();
    return scanner.makeToken(.identifier);
}

fn string(scanner: *Scanner) Token {
    while (scanner.peek() != '"' and !scanner.isAtEnd()) {
        if (scanner.peek() == '\n') scanner.line += 1;
        _ = scanner.advance();
    }

    if (scanner.isAtEnd()) return scanner.errorToken("Unterminated string.");

    _ = scanner.advance();
    return makeToken(scanner, .string);
}

fn number(scanner: *Scanner) Token {
    while (isDigit(scanner.peek())) _ = scanner.advance();

    if (scanner.peek() == '.' and isDigit(scanner.peekNext())) {
        _ = scanner.advance();
        while (isDigit(scanner.peek())) _ = scanner.advance();
    }

    return makeToken(scanner, .number);
}

fn makeToken(scanner: *Scanner, token_type: TokenType) Token {
    return Token{
        .type = token_type,
        .start = scanner.source.ptr + scanner.start,
        .length = scanner.current - scanner.start,
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

fn skipWhitespace(scanner: *Scanner) void {
    while (!scanner.isAtEnd()) {
        const c = scanner.source[scanner.current];
        switch (c) {
            ' ', '\r', '\t' => _ = scanner.advance(),
            '\n' => {
                scanner.line += 1;
                _ = scanner.advance();
            },
            '/' => {
                if (scanner.peekNext() == '/') {
                    while (!scanner.isAtEnd() and scanner.peek() != '\n') {
                        _ = scanner.advance();
                    }
                } else {
                    return;
                }
            },
            else => return,
        }
    }
}

fn isAtEnd(scanner: *Scanner) bool {
    return scanner.current >= scanner.source.len;
}

fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}
