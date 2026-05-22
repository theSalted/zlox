const std = @import("std");
const print = std.debug.print;

const Chunk = @import("Chunk.zig");
const Scanner = @import("Scanner.zig");

const Token = Scanner.Token;
const TokenType = Scanner.TokenType;

const Parser = struct {
    scanner: *Scanner,
    compilingChunk: *Chunk,
    previous: Token,
    current: Token,
    hadError: bool,
    panicMode: bool,

    fn init(parser: *Parser, scanner: *Scanner) void {
        parser.scanner = scanner;
    }

    fn advance(parser: *Parser) void {
        parser.previous = parser.current;
        while (true) {
            parser.current = parser.scanner.scanToken();

            if (parser.current.type != .@"error") break;

            parser.errorAtCurrent(parser.current.start[0..parser.current.length]);
        }
    }

    fn expression(parser: *Parser) void {
        // COMEBACK

        _ = parser;
    }

    fn consume(parser: *Parser, token_type: TokenType, message: []const u8) void {
        if (parser.current.type == token_type) {
            parser.advance();
            return;
        }

        parser.errorAtCurrent(message);
    }

    fn emitByte(parser: *Parser, byte: u8) void {
        parser.currentChunk().write(byte, parser.previous.line);
    }

    fn currentChunk(parser: *Parser) *Chunk {
        return parser.compilingChunk;
    }

    fn errorAtCurrent(parser: *Parser, message: []const u8) void {
        parser.errorAt(parser.current, message);
    }

    fn errorAtPrevious(parser: *Parser, message: []const u8) void {
        parser.errorAt(parser.previous, message);
    }

    fn errorAt(parser: *Parser, token: Token, message: []const u8) void {
        if (parser.panicMode) return;
        parser.panicMode = true;

        print("[line {d}] Error", .{token.line});

        if (token.type == .eof) {
            print(" at end", .{});
        } else if (token.type == .@"error") {
            // nothing
        } else {
            print(" at '{s}'", .{token.start[0..token.length]});
        }
        print(": {s}\n", .{message});
        parser.hadError = true;
    }
};

pub fn compile(source: []const u8, chunk: *Chunk) bool {
    var scanner: Scanner = undefined;
    scanner.init(source);

    var parser: Parser = undefined;
    parser.init(&scanner);
    parser.compilingChunk = chunk;
    parser.hadError = false;
    parser.panicMode = false;

    parser.advance();
    parser.expression();
    parser.consume(.eof, "Expect end of expression.");

    return !parser.hadError;
}
