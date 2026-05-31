const std = @import("std");
const print = std.debug.print;
const object = @import("object.zig");

const Chunk = @import("Chunk.zig");
const Scanner = @import("Scanner.zig");

const Token = Scanner.Token;
const TokenType = Scanner.TokenType;
const Value = @import("value.zig").Value;

const Precedence = enum {
    none,
    assignment,
    @"or",
    @"and",
    equality,
    comparison,
    term,
    factor,
    unary,
    call,
    primary,
};

const ParseFn = *const fn (*Compiler) void;

const ParseRule = struct {
    prefix: ?ParseFn,
    infix: ?ParseFn,
    precedence: Precedence,
};

const Parser = struct {
    scanner: *Scanner,
    previous: Token,
    current: Token,
    had_error: bool,
    panic_mode: bool,

    fn init(parser: *Parser, scanner: *Scanner) void {
        parser.scanner = scanner;
        parser.previous = undefined;
        parser.current = undefined;
        parser.had_error = false;
        parser.panic_mode = false;
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
        if (parser.panic_mode) return;
        parser.panic_mode = true;

        print("[line {d}] Error", .{token.line});

        if (token.type == .eof) {
            print(" at end", .{});
        } else if (token.type == .@"error") {
            // nothing
        } else {
            print(" at '{s}'", .{token.start[0..token.length]});
        }
        print(": {s}\n", .{message});
        parser.had_error = true;
    }
};

const Compiler = struct {
    parser: *Parser,
    compiling_chunk: *Chunk,

    fn init(c: *Compiler, parser: *Parser, chunk: *Chunk) void {
        c.parser = parser;
        c.compiling_chunk = chunk;
    }

    fn expression(compiler: *Compiler) void {
        compiler.parsePrecedence(.assignment);
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

    fn makeConstant(compiler: *Compiler, value: Value) u8 {
        const constant = compiler.currentChunk().addConstant(value);
        if (constant > 255) {
            compiler.parser.errorAtPrevious("Too many constants in one chunk");
            return 0;
        }
        return @intCast(constant);
    }

    fn emitConstant(compiler: *Compiler, value: Value) void {
        compiler.emitBytes(@intFromEnum(Chunk.OpCode.op_constant), compiler.makeConstant(value));
    }

    fn currentChunk(compiler: *Compiler) *Chunk {
        return compiler.compiling_chunk;
    }

    fn endCompiler(compiler: *Compiler) void {
        compiler.emitReturn();
    }

    fn binary(compiler: *Compiler) void {
        const operator_type = compiler.parser.previous.type;

        const rule = getRule(operator_type);

        compiler.parsePrecedence(@enumFromInt(@intFromEnum(rule.precedence) + 1));

        switch (operator_type) {
            .bang_equal => compiler.emitBytes(@intFromEnum(Chunk.OpCode.op_equal), @intFromEnum(Chunk.OpCode.op_not)),
            .equal_equal => compiler.emitByte(@intFromEnum(Chunk.OpCode.op_equal)),
            .greater => compiler.emitByte(@intFromEnum(Chunk.OpCode.op_greater)),
            .greater_equal => compiler.emitBytes(@intFromEnum(Chunk.OpCode.op_less), @intFromEnum(Chunk.OpCode.op_not)),
            .less => compiler.emitByte(@intFromEnum(Chunk.OpCode.op_less)),
            .less_equal => compiler.emitBytes(@intFromEnum(Chunk.OpCode.op_greater), @intFromEnum(Chunk.OpCode.op_not)),
            .plus => compiler.emitByte(@intFromEnum(Chunk.OpCode.op_add)),
            .minus => compiler.emitByte(@intFromEnum(Chunk.OpCode.op_subtract)),
            .star => compiler.emitByte(@intFromEnum(Chunk.OpCode.op_multiply)),
            .slash => compiler.emitByte(@intFromEnum(Chunk.OpCode.op_divide)),
            else => return,
        }
    }

    fn literal(compiler: *Compiler) void {
        switch (compiler.parser.previous.type) {
            .false => compiler.emitByte(@intFromEnum(Chunk.OpCode.op_false)),
            .nil => compiler.emitByte(@intFromEnum(Chunk.OpCode.op_nil)),
            .true => compiler.emitByte(@intFromEnum(Chunk.OpCode.op_true)),
            else => return,
        }
    }

    fn grouping(compiler: *Compiler) void {
        compiler.expression();
        compiler.parser.consume(.right_paren, "Expect ')' after expression.");
    }

    fn number(compiler: *Compiler) void {
        const lexeme = compiler.parser.previous.start[0..compiler.parser.previous.length];
        const value = std.fmt.parseFloat(f64, lexeme) catch unreachable;
        compiler.emitConstant(.{ .val_number = value });
    }

    fn string(compiler: *Compiler) void {
        const parser = compiler.parser;
        compiler.emitConstant(object.copyString(parser.previous.start + 1, parser.previous.length - 2));
    }

    fn unary(compiler: *Compiler) void {
        const operator_type = compiler.parser.previous.type;

        compiler.parsePrecedence(.unary);

        switch (operator_type) {
            .bang => compiler.emitByte(@intFromEnum(Chunk.OpCode.op_not)),
            .minus => compiler.emitByte(@intFromEnum(Chunk.OpCode.op_negate)),
            else => return,
        }
    }

    fn getRule(token_type: TokenType) ParseRule {
        return switch (token_type) {
            .left_paren => .{ .prefix = grouping, .infix = null, .precedence = .none },
            .right_paren => .{ .prefix = null, .infix = null, .precedence = .none },
            .left_brace => .{ .prefix = null, .infix = null, .precedence = .none },
            .right_brace => .{ .prefix = null, .infix = null, .precedence = .none },
            .comma => .{ .prefix = null, .infix = null, .precedence = .none },
            .dot => .{ .prefix = null, .infix = null, .precedence = .none },
            .minus => .{ .prefix = unary, .infix = binary, .precedence = .term },
            .plus => .{ .prefix = null, .infix = binary, .precedence = .term },
            .semicolon => .{ .prefix = null, .infix = null, .precedence = .none },
            .slash => .{ .prefix = null, .infix = binary, .precedence = .factor },
            .star => .{ .prefix = null, .infix = binary, .precedence = .factor },
            .bang => .{ .prefix = unary, .infix = null, .precedence = .none },
            .bang_equal => .{ .prefix = null, .infix = binary, .precedence = .equality },
            .equal => .{ .prefix = null, .infix = null, .precedence = .none },
            .equal_equal => .{ .prefix = null, .infix = binary, .precedence = .equality },
            .greater => .{ .prefix = null, .infix = binary, .precedence = .comparison },
            .greater_equal => .{ .prefix = null, .infix = binary, .precedence = .comparison },
            .less => .{ .prefix = null, .infix = binary, .precedence = .comparison },
            .less_equal => .{ .prefix = null, .infix = binary, .precedence = .comparison },
            .identifier => .{ .prefix = null, .infix = null, .precedence = .none },
            .string => .{ .prefix = string, .infix = null, .precedence = .none },
            .number => .{ .prefix = number, .infix = null, .precedence = .none },
            .@"and" => .{ .prefix = null, .infix = null, .precedence = .none },
            .class => .{ .prefix = null, .infix = null, .precedence = .none },
            .@"else" => .{ .prefix = null, .infix = null, .precedence = .none },
            .false => .{ .prefix = literal, .infix = null, .precedence = .none },
            .@"for" => .{ .prefix = null, .infix = null, .precedence = .none },
            .fun => .{ .prefix = null, .infix = null, .precedence = .none },
            .@"if" => .{ .prefix = null, .infix = null, .precedence = .none },
            .nil => .{ .prefix = literal, .infix = null, .precedence = .none },
            .@"or" => .{ .prefix = null, .infix = null, .precedence = .none },
            .print => .{ .prefix = null, .infix = null, .precedence = .none },
            .@"return" => .{ .prefix = null, .infix = null, .precedence = .none },
            .super => .{ .prefix = null, .infix = null, .precedence = .none },
            .this => .{ .prefix = null, .infix = null, .precedence = .none },
            .true => .{ .prefix = literal, .infix = null, .precedence = .none },
            .@"var" => .{ .prefix = null, .infix = null, .precedence = .none },
            .@"while" => .{ .prefix = null, .infix = null, .precedence = .none },
            .@"error" => .{ .prefix = null, .infix = null, .precedence = .none },
            .eof => .{ .prefix = null, .infix = null, .precedence = .none },
        };
    }

    fn parsePrecedence(compiler: *Compiler, precedence: Precedence) void {
        // todo
        compiler.parser.advance();

        const prefix_rule = getRule(compiler.parser.previous.type).prefix;

        if (prefix_rule == null) {
            compiler.parser.errorAtPrevious("Expect expression.");
            return;
        }

        prefix_rule.?(compiler);

        while (@intFromEnum(precedence) <= @intFromEnum(getRule(compiler.parser.current.type).precedence)) {
            compiler.parser.advance();
            const infix_rule = getRule(compiler.parser.previous.type).infix;
            infix_rule.?(compiler);
        }
    }
};

pub fn compile(source: []const u8, chunk: *Chunk) bool {
    var scanner: Scanner = undefined;
    scanner.init(source);

    var parser: Parser = undefined;
    parser.init(&scanner);

    var compiler: Compiler = undefined;
    compiler.init(&parser, chunk);

    parser.advance();
    compiler.expression();
    parser.consume(.eof, "Expect end of expression.");
    compiler.endCompiler();

    return !parser.had_error;
}
