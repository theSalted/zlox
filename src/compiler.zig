const std = @import("std");
const print = std.debug.print;

const Chunk = @import("Chunk.zig");
const Scanner = @import("Scanner.zig");

const Token = Scanner.Token;
const TokenType = Scanner.TokenType;

const Parser = struct {
    scanner: *Scanner,
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

    fn consume(parser: *Parser, token_type: TokenType, message: []const u8) void {
        if (parser.current.type == token_type) {
            parser.advance();
            return;
        }

        parser.errorAtCurrent(message);
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

const Compiler = struct {
    parser: *Parser,
    compilingChunk: *Chunk,

    fn init(c: *Compiler, parser: *Parser, chunk: *Chunk) void {
        c.parser = parser;
        c.compilingChunk = chunk;
    }

    fn expression(compiler: *Compiler) void {
        // COMEBACK

        _ = compiler;
    }

    fn emitByte(compiler: *Compiler, byte: u8) void {
        compiler.currentChunk().write(byte, compiler.parser.previous.line);
    }

    fn emitBytes(compiler: *Compiler, byte1: u8, byte2: u8) void {
        compiler.emitByte(byte1);
        compiler.emitByte(byte2);
    }

    fn emitReturn(compiler: *Compiler) void {
        compiler.emitByte(@intFromEnum(Chunk.OpCode.op_return));
    }

    fn makeConstant(compiler: *Compiler, value: f64) u8 {
        const constant = compiler.currentChunk().addConstant(value);
        if (constant > 255) {
            compiler.parser.errorAtPrevious("Too many constants in one chunk");
            return 0;
        }
        return @intCast(constant);
    }

    fn emitConstant(compiler: *Compiler, value: f64) void {
        compiler.emitBytes(@intFromEnum(Chunk.OpCode.op_constant), compiler.makeConstant(value));
    }

    fn currentChunk(compiler: *Compiler) *Chunk {
        return compiler.compilingChunk;
    }

    fn endCompiler(compiler: *Compiler) void {
        compiler.emitReturn();
    }

    fn number(compiler: *Compiler) void {
        const lexeme = compiler.parser.previous.start[0..compiler.parser.previous.length];
        const value = std.fmt.parseFloat(f64, lexeme) catch unreachable;
        compiler.emitConstant(value);
    }
};

pub fn compile(source: []const u8, chunk: *Chunk) bool {
    var scanner: Scanner = undefined;
    scanner.init(source);

    var parser: Parser = undefined;
    parser.init(&scanner);
    parser.hadError = false;
    parser.panicMode = false;

    var compiler: Compiler = undefined;
    compiler.init(&parser, chunk);

    parser.advance();
    compiler.expression();
    parser.consume(.eof, "Expect end of expression.");
    compiler.endCompiler();

    return !parser.hadError;
}
