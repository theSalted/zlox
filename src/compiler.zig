const std = @import("std");
const print = std.debug.print;

const Chunk = @import("Chunk.zig");
const common = @import("common.zig");
const debug = @import("debug.zig");
const object = @import("object.zig");
const Scanner = @import("Scanner.zig");
const Token = Scanner.Token;
const TokenType = Scanner.TokenType;
const ObjectFunction = object.ObjectFunction;
const Value = @import("value.zig").Value;
const VM = @import("VM.zig").VM;

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

const ParseFn = *const fn (*Compiler, bool) void;

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

    fn check(parser: *Parser, token_type: TokenType) bool {
        return parser.current.type == token_type;
    }

    fn match(parser: *Parser, token_type: TokenType) bool {
        if (!parser.check(token_type)) return false;
        parser.advance();
        return true;
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

const Local = struct {
    name: Token,
    depth: isize,
};

const FunctionType = enum {
    function,
    script,
};

const Compiler = struct {
    enclosing: ?*Compiler,
    function: ?*ObjectFunction,
    type: FunctionType,

    locals: [common.uint8_count]Local,
    local_count: usize,
    scope_depth: usize,

    parser: *Parser,
    vm: *VM,

    fn init(compiler: *Compiler, enclosing: ?*Compiler, vm: *VM, parser: *Parser, function_type: FunctionType) void {
        compiler.enclosing = enclosing;
        compiler.function = object.newFunction(vm);
        compiler.type = function_type;

        compiler.local_count = 0;
        compiler.scope_depth = 0;
        if (function_type != FunctionType.script) {
            compiler.function.?.name = object.copyString(vm, parser.previous.start, parser.previous.length);
        }

        const local = &compiler.locals[compiler.local_count];
        compiler.local_count += 1;
        local.depth = 0;
        local.name.start = "";
        local.name.length = 0;

        compiler.vm = vm;
        compiler.parser = parser;
    }

    fn expression(compiler: *Compiler) void {
        compiler.parsePrecedence(.assignment);
    }

    fn statement(compiler: *Compiler) void {
        if (compiler.parser.match(.print)) {
            compiler.printStatement();
        } else if (compiler.parser.match(.@"for")) {
            compiler.forStatement();
        } else if (compiler.parser.match(.@"if")) {
            compiler.ifStatement();
        } else if (compiler.parser.match(.@"return")) {
            compiler.returnStatement();
        } else if (compiler.parser.match(.@"while")) {
            compiler.whileStatement();
        } else if (compiler.parser.match(.left_brace)) {
            compiler.beginScope();
            compiler.block();
            compiler.endScope();
        } else {
            compiler.expressionStatement();
        }
    }

    fn block(compiler: *Compiler) void {
        const parser = compiler.parser;
        while (!parser.check(.right_brace) and !parser.check(.eof)) {
            compiler.declaration();
        }

        parser.consume(.right_brace, "Expect '}' after block.");
    }

    fn beginScope(compiler: *Compiler) void {
        compiler.scope_depth += 1;
    }

    fn endScope(compiler: *Compiler) void {
        compiler.scope_depth -= 1;

        while (compiler.local_count > 0 and compiler.locals[compiler.local_count - 1].depth > compiler.scope_depth) {
            compiler.emitByte(@intFromEnum(Chunk.OpCode.pop));
            compiler.local_count -= 1;
        }
    }

    fn functionBody(compiler: *Compiler, function_type: FunctionType) void {
        var inner: Compiler = undefined;
        inner.init(compiler, compiler.vm, compiler.parser, function_type);
        inner.beginScope();

        inner.parser.consume(.left_paren, "Expect '(' after function name.");
        if (!inner.parser.check(.right_paren)) {
            while (true) {
                inner.function.?.arity += 1;
                if (inner.function.?.arity > 255) {
                    inner.parser.errorAtCurrent("Can't have more than 255 parameters");
                }
                const constant = inner.parseVariable("Expect parameter name.");
                inner.defineVariable(constant);
                if (!inner.parser.match(.comma)) break;
            }
        }
        inner.parser.consume(.right_paren, "Expect ')' after parameters.");
        inner.parser.consume(.left_brace, "Expect '{' before function body.");
        inner.block();

        const func = inner.end();
        compiler.emitBytes(@intFromEnum(Chunk.OpCode.constant), compiler.makeConstant(.{ .val_object = &func.obj }));
    }

    fn functionDeclaration(compiler: *Compiler) void {
        const global = compiler.parseVariable("Expect function name.");
        compiler.markInitialized();
        compiler.functionBody(.function);
        compiler.defineVariable(global);
    }

    fn varDeclaration(compiler: *Compiler) void {
        const global = compiler.parseVariable("Expect variable name.");

        if (compiler.parser.match(.equal)) {
            compiler.expression();
        } else {
            compiler.emitByte(@intFromEnum(Chunk.OpCode.nil));
        }
        compiler.parser.consume(.semicolon, "Expect ';' after variable declaration.");

        compiler.defineVariable(global);
    }

    fn expressionStatement(compiler: *Compiler) void {
        compiler.expression();
        compiler.parser.consume(.semicolon, "Expect ';' after value.");
        compiler.emitByte(@intFromEnum(Chunk.OpCode.pop));
    }

    fn forStatement(compiler: *Compiler) void {
        compiler.beginScope();
        compiler.parser.consume(.left_paren, "Expect '(' after 'for'.");
        if (compiler.parser.match(.semicolon)) {
            // No initializer
        } else if (compiler.parser.match(.@"var")) {
            compiler.varDeclaration();
        } else {
            compiler.expressionStatement();
        }
        var loopStart = compiler.currentChunk().count;
        var exitJump: isize = -1;
        if (!compiler.parser.match(.semicolon)) {
            compiler.expression();
            compiler.parser.consume(.semicolon, "Expect ';' after loop condition.");

            exitJump = @intCast(compiler.emitJump(@intFromEnum(Chunk.OpCode.jump_if_false)));
            compiler.emitByte(@intFromEnum(Chunk.OpCode.pop));
        }

        if (!compiler.parser.match(.right_paren)) {
            const bodyJump = compiler.emitJump(@intFromEnum(Chunk.OpCode.jump));
            const incrementStart = compiler.currentChunk().count;
            compiler.expression();
            compiler.emitByte(@intFromEnum(Chunk.OpCode.pop));
            compiler.parser.consume(.right_paren, "Expect ')' after for clauses.");

            compiler.emitLoop(loopStart);
            loopStart = incrementStart;
            compiler.patchJump(bodyJump);
        }

        compiler.statement();
        compiler.emitLoop(loopStart);

        if (exitJump != -1) {
            compiler.patchJump(@intCast(exitJump));
            compiler.emitByte(@intFromEnum(Chunk.OpCode.pop));
        }

        compiler.endScope();
    }

    fn ifStatement(compiler: *Compiler) void {
        compiler.parser.consume(.left_paren, "Expect '(' after 'if'.");
        compiler.expression();
        compiler.parser.consume(.right_paren, "Expect ')' after condition.");

        const thenJump = compiler.emitJump(@intFromEnum(Chunk.OpCode.jump_if_false));
        compiler.emitByte(@intFromEnum(Chunk.OpCode.pop));

        compiler.statement();

        const elseJump = compiler.emitJump(@intFromEnum(Chunk.OpCode.jump));

        compiler.patchJump(thenJump);
        compiler.emitByte(@intFromEnum(Chunk.OpCode.pop));

        if (compiler.parser.match(.@"else")) compiler.statement();
        compiler.patchJump(elseJump);
    }

    fn printStatement(compiler: *Compiler) void {
        compiler.expression();
        compiler.parser.consume(.semicolon, "Expect ';' after value.");
        compiler.emitByte(@intFromEnum(Chunk.OpCode.print));
    }

    fn returnStatement(compiler: *Compiler) void {
        if (compiler.type == .script) {
            compiler.parser.errorAtPrevious("Can't return from top-level code.");
        }

        if (compiler.parser.match(.semicolon)) {
            compiler.emitReturn();
        } else {
            compiler.expression();
            compiler.parser.consume(.semicolon, "Expect ';' after return value.");
            compiler.emitByte(@intFromEnum(Chunk.OpCode.@"return"));
        }
    }

    fn whileStatement(compiler: *Compiler) void {
        const loopStart = compiler.currentChunk().count;
        compiler.parser.consume(.left_paren, "Expect '(' after 'while'.");
        compiler.expression();
        compiler.parser.consume(.right_paren, "Expect ')' after condition.");

        const exitJump = compiler.emitJump(@intFromEnum(Chunk.OpCode.jump_if_false));
        compiler.emitByte(@intFromEnum(Chunk.OpCode.pop));
        compiler.statement();
        compiler.emitLoop(loopStart);

        compiler.patchJump(exitJump);
        compiler.emitByte(@intFromEnum(Chunk.OpCode.pop));
    }

    fn synchronize(compiler: *Compiler) void {
        compiler.parser.panic_mode = false;

        while (compiler.parser.current.type != .eof) {
            if (compiler.parser.previous.type == .semicolon) return;
            switch (compiler.parser.current.type) {
                .class, .fun, .@"var", .@"for", .@"if", .@"while", .print, .@"return" => {
                    return;
                },
                else => {},
            }

            compiler.parser.advance();
        }
    }

    fn declaration(compiler: *Compiler) void {
        if (compiler.parser.match(.fun)) {
            compiler.functionDeclaration();
        } else if (compiler.parser.match(.@"var")) {
            compiler.varDeclaration();
        } else {
            compiler.statement();
        }

        if (compiler.parser.panic_mode) compiler.synchronize();
    }

    fn emitByte(compiler: *Compiler, byte: u8) void {
        compiler.currentChunk().write(byte, compiler.parser.previous.line);
    }

    fn emitBytes(compiler: *Compiler, byte1: u8, byte2: u8) void {
        compiler.emitByte(byte1);
        compiler.emitByte(byte2);
    }

    fn emitLoop(compiler: *Compiler, loopStart: usize) void {
        compiler.emitByte(@intFromEnum(Chunk.OpCode.loop));

        const offset = compiler.currentChunk().count - loopStart + 2;
        if (offset > std.math.maxInt(u16)) compiler.parser.errorAtPrevious("Loop body too large.");

        compiler.emitByte(@intCast((offset >> 8) & 0xff));
        compiler.emitByte(@intCast(offset & 0xff));
    }

    fn emitJump(compiler: *Compiler, instruction: u8) usize {
        compiler.emitByte(instruction);
        compiler.emitByte(0xff);
        compiler.emitByte(0xff);
        return compiler.currentChunk().count - 2;
    }

    fn emitReturn(compiler: *Compiler) void {
        compiler.emitByte(@intFromEnum(Chunk.OpCode.nil));
        compiler.emitByte(@intFromEnum(Chunk.OpCode.@"return"));
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
        compiler.emitBytes(@intFromEnum(Chunk.OpCode.constant), compiler.makeConstant(value));
    }

    fn patchJump(compiler: *Compiler, offset: usize) void {
        const jump = compiler.currentChunk().count - offset - 2;

        if (jump > std.math.maxInt(u16)) {
            compiler.parser.errorAtPrevious("Too much code to jump over.");
        }

        const code = compiler.currentChunk().code.?;
        code[offset] = @intCast((jump >> 8) & 0xff);
        code[offset + 1] = @intCast(jump & 0xff);
    }

    fn currentChunk(compiler: *Compiler) *Chunk {
        return &compiler.function.?.chunk;
    }

    fn end(compiler: *Compiler) *ObjectFunction {
        compiler.emitReturn();
        const function = compiler.function.?;

        if (common.debug_print_code and !compiler.parser.had_error) {
            const name = if (function.name) |n| n.chars[0..n.len] else "<script>";
            debug.disassembleChunk(compiler.currentChunk(), name);
        }

        return function;
    }

    fn binary(compiler: *Compiler, can_assign: bool) void {
        _ = can_assign;
        const operator_type = compiler.parser.previous.type;

        const rule = getRule(operator_type);

        compiler.parsePrecedence(@enumFromInt(@intFromEnum(rule.precedence) + 1));

        switch (operator_type) {
            .bang_equal => compiler.emitBytes(@intFromEnum(Chunk.OpCode.equal), @intFromEnum(Chunk.OpCode.not)),
            .equal_equal => compiler.emitByte(@intFromEnum(Chunk.OpCode.equal)),
            .greater => compiler.emitByte(@intFromEnum(Chunk.OpCode.greater)),
            .greater_equal => compiler.emitBytes(@intFromEnum(Chunk.OpCode.less), @intFromEnum(Chunk.OpCode.not)),
            .less => compiler.emitByte(@intFromEnum(Chunk.OpCode.less)),
            .less_equal => compiler.emitBytes(@intFromEnum(Chunk.OpCode.greater), @intFromEnum(Chunk.OpCode.not)),
            .plus => compiler.emitByte(@intFromEnum(Chunk.OpCode.add)),
            .minus => compiler.emitByte(@intFromEnum(Chunk.OpCode.subtract)),
            .star => compiler.emitByte(@intFromEnum(Chunk.OpCode.multiply)),
            .slash => compiler.emitByte(@intFromEnum(Chunk.OpCode.divide)),
            else => return,
        }
    }

    fn literal(compiler: *Compiler, can_assign: bool) void {
        _ = can_assign;
        switch (compiler.parser.previous.type) {
            .false => compiler.emitByte(@intFromEnum(Chunk.OpCode.false)),
            .nil => compiler.emitByte(@intFromEnum(Chunk.OpCode.nil)),
            .true => compiler.emitByte(@intFromEnum(Chunk.OpCode.true)),
            else => return,
        }
    }

    fn grouping(compiler: *Compiler, can_assign: bool) void {
        _ = can_assign;
        compiler.expression();
        compiler.parser.consume(.right_paren, "Expect ')' after expression.");
    }

    fn number(compiler: *Compiler, can_assign: bool) void {
        _ = can_assign;
        const lexeme = compiler.parser.previous.start[0..compiler.parser.previous.length];
        const value = std.fmt.parseFloat(f64, lexeme) catch unreachable;
        compiler.emitConstant(.{ .val_number = value });
    }

    fn string(compiler: *Compiler, can_assign: bool) void {
        _ = can_assign;
        const parser = compiler.parser;
        const str = object.copyString(compiler.vm, parser.previous.start + 1, parser.previous.length - 2);
        compiler.emitConstant(.{ .val_object = &str.obj });
    }

    fn and_(compiler: *Compiler, can_assign: bool) void {
        _ = can_assign;
        const end_jump = compiler.emitJump(@intFromEnum(Chunk.OpCode.jump_if_false));
        compiler.emitByte(@intFromEnum(Chunk.OpCode.pop));
        compiler.parsePrecedence(.@"and");
        compiler.patchJump(end_jump);
    }

    fn or_(compiler: *Compiler, can_assign: bool) void {
        _ = can_assign;
        const else_jump = compiler.emitJump(@intFromEnum(Chunk.OpCode.jump_if_false));
        const end_jump = compiler.emitJump(@intFromEnum(Chunk.OpCode.jump));

        compiler.patchJump(else_jump);
        compiler.emitByte(@intFromEnum(Chunk.OpCode.pop));

        compiler.parsePrecedence(.@"or");
        compiler.patchJump(end_jump);
    }

    fn resolveLocal(compiler: *Compiler, name: Token) isize {
        var i = compiler.local_count;
        while (i > 0) {
            i -= 1;
            const local = compiler.locals[i];
            if (compiler.identifiersEqual(name, local.name)) {
                if (local.depth == -1) {
                    compiler.parser.errorAtPrevious("Can't read local variable in its own initializer.");
                }
                return @intCast(i);
            }
        }
        return -1;
    }

    fn namedVariable(compiler: *Compiler, name: Token, can_assign: bool) void {
        var get_op: u8 = undefined;
        var set_op: u8 = undefined;

        var arg = compiler.resolveLocal(name);
        if (arg != -1) {
            get_op = @intFromEnum(Chunk.OpCode.get_local);
            set_op = @intFromEnum(Chunk.OpCode.set_local);
        } else {
            arg = compiler.identifierConstant(name);
            get_op = @intFromEnum(Chunk.OpCode.get_global);
            set_op = @intFromEnum(Chunk.OpCode.set_global);
        }

        if (can_assign and compiler.parser.match(.equal)) {
            compiler.expression();
            compiler.emitBytes(set_op, @intCast(arg));
        } else {
            compiler.emitBytes(get_op, @intCast(arg));
        }
    }

    fn variable(compiler: *Compiler, can_assign: bool) void {
        compiler.namedVariable(compiler.parser.previous, can_assign);
    }

    fn unary(compiler: *Compiler, can_assign: bool) void {
        _ = can_assign;
        const operator_type = compiler.parser.previous.type;

        compiler.parsePrecedence(.unary);

        switch (operator_type) {
            .bang => compiler.emitByte(@intFromEnum(Chunk.OpCode.not)),
            .minus => compiler.emitByte(@intFromEnum(Chunk.OpCode.negate)),
            else => return,
        }
    }

    fn call(compiler: *Compiler, can_assign: bool) void {
        _ = can_assign;
        const arg_count = compiler.argumentList();
        compiler.emitBytes(@intFromEnum(Chunk.OpCode.call), arg_count);
    }

    fn getRule(token_type: TokenType) ParseRule {
        return switch (token_type) {
            .left_paren => .{ .prefix = grouping, .infix = call, .precedence = .call },
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
            .identifier => .{ .prefix = variable, .infix = null, .precedence = .none },
            .string => .{ .prefix = string, .infix = null, .precedence = .none },
            .number => .{ .prefix = number, .infix = null, .precedence = .none },
            .@"and" => .{ .prefix = null, .infix = and_, .precedence = .@"and" },
            .class => .{ .prefix = null, .infix = null, .precedence = .none },
            .@"else" => .{ .prefix = null, .infix = null, .precedence = .none },
            .false => .{ .prefix = literal, .infix = null, .precedence = .none },
            .@"for" => .{ .prefix = null, .infix = null, .precedence = .none },
            .fun => .{ .prefix = null, .infix = null, .precedence = .none },
            .@"if" => .{ .prefix = null, .infix = null, .precedence = .none },
            .nil => .{ .prefix = literal, .infix = null, .precedence = .none },
            .@"or" => .{ .prefix = null, .infix = or_, .precedence = .@"or" },
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
        compiler.parser.advance();

        const prefix_rule = getRule(compiler.parser.previous.type).prefix;

        if (prefix_rule == null) {
            compiler.parser.errorAtPrevious("Expect expression.");
            return;
        }

        const can_assign = @intFromEnum(precedence) <= @intFromEnum(Precedence.assignment);
        prefix_rule.?(compiler, can_assign);

        while (@intFromEnum(precedence) <= @intFromEnum(getRule(compiler.parser.current.type).precedence)) {
            compiler.parser.advance();
            const infix_rule = getRule(compiler.parser.previous.type).infix;
            infix_rule.?(compiler, can_assign);
        }

        if (can_assign and compiler.parser.match(.equal)) {
            compiler.parser.errorAtPrevious("Invalid assignment target.");
        }
    }

    fn parseVariable(compiler: *Compiler, message: []const u8) u8 {
        compiler.parser.consume(.identifier, message);

        compiler.declareVariable();
        if (compiler.scope_depth > 0) return 0;

        return compiler.identifierConstant(compiler.parser.previous);
    }

    fn identifierConstant(compiler: *Compiler, name: Token) u8 {
        return compiler.makeConstant(.{ .val_object = &object.copyString(compiler.vm, name.start, name.length).obj });
    }

    fn identifiersEqual(compiler: *Compiler, a: Token, b: Token) bool {
        _ = compiler;
        if (a.length != b.length) return false;
        return std.mem.eql(u8, a.start[0..a.length], b.start[0..b.length]);
    }

    fn addLocal(compiler: *Compiler, name: Token) void {
        if (compiler.local_count == common.uint8_count) {
            compiler.parser.errorAtPrevious("Too many local variables in function.");
            return;
        }

        const local = &compiler.locals[compiler.local_count];
        compiler.local_count += 1;
        local.name = name;
        local.depth = -1;
    }

    fn declareVariable(compiler: *Compiler) void {
        if (compiler.scope_depth == 0) return;

        const name = compiler.parser.previous;

        var i = compiler.local_count;
        while (i > 0) {
            i -= 1;
            const local = compiler.locals[i];
            if (local.depth != -1 and local.depth < compiler.scope_depth) {
                break;
            }

            if (compiler.identifiersEqual(name, local.name)) {
                compiler.parser.errorAtPrevious("Already a variable with this name in this scope.");
            }
        }
        compiler.addLocal(name);
    }

    fn markInitialized(compiler: *Compiler) void {
        if (compiler.scope_depth == 0) return;
        compiler.locals[compiler.local_count - 1].depth = @intCast(compiler.scope_depth);
    }

    fn defineVariable(compiler: *Compiler, global: u8) void {
        if (compiler.scope_depth > 0) {
            compiler.markInitialized();
            return;
        }
        compiler.emitBytes(@intFromEnum(Chunk.OpCode.define_global), global);
    }

    fn argumentList(compiler: *Compiler) u8 {
        var arg_count: u8 = 0;
        if (!compiler.parser.check(.right_paren)) {
            while (true) {
                compiler.expression();
                if (arg_count == 255) {
                    compiler.parser.errorAtPrevious("Can't have more than 255 arguments.");
                }
                arg_count += 1;

                if (!compiler.parser.match(.comma)) {
                    break;
                }
            }
        }
        compiler.parser.consume(.right_paren, "Expect ')' after arguments");
        return arg_count;
    }
};

pub fn compile(vm: *VM, source: []const u8) ?*ObjectFunction {
    var scanner: Scanner = undefined;
    scanner.init(source);

    var parser: Parser = undefined;
    parser.init(&scanner);

    var compiler: Compiler = undefined;
    compiler.init(null, vm, &parser, .script);

    parser.advance();

    while (!compiler.parser.match(.eof)) {
        compiler.declaration();
    }

    const function = compiler.end();

    return if (parser.had_error) null else function;
}
