const std = @import("std");
const val = @import("value.zig");
const debug = @import("debug.zig");
const common = @import("common.zig");
const compiler = @import("compiler.zig");

const Value = val.Value;
const Chunk = @import("Chunk.zig");

const print = std.debug.print;

const VM = @This();

pub const InterpretResult = enum(u8) { interpret_ok, interpret_compile_error, interpret_runtime_error };

const stack_max: usize = 256;

// Chunk

chunk: *Chunk,
ip: [*]u8,
stack: [stack_max]Value,
stack_top: [*]Value,
allocator: std.mem.Allocator,

fn resetStack(vm: *VM) void {
    vm.stack_top = &vm.stack;
}

pub fn init(vm: *VM, allocator: std.mem.Allocator) void {
    vm.allocator = allocator;
    vm.resetStack();
}

pub fn free(vm: *VM) void {
    _ = vm;
}

pub fn push(vm: *VM, value: Value) void {
    vm.stack_top[0] = value;
    vm.stack_top += 1;
}

pub fn pop(vm: *VM) Value {
    vm.stack_top -= 1;
    return vm.stack_top[0];
}

pub fn run(vm: *VM) InterpretResult {
    while (true) {
        if (common.debug_trace_execution) {
            print("          ", .{});
            var slot: [*]Value = &vm.stack;
            while (slot != vm.stack_top) : (slot += 1) {
                print("[ ", .{});
                val.printValue(slot[0]);
                print(" ]", .{});
            }
            print("\n", .{});
            _ = debug.disassembleInstruction(vm.chunk, @intFromPtr(vm.ip) - @intFromPtr(vm.chunk.code.?));
        }

        const instruction = vm.readBytes();
        const op: Chunk.OpCode = @enumFromInt(instruction);
        switch (op) {
            .op_constant => {
                const constant: Value = readConstant(vm);
                vm.push(constant);
            },
            .op_add => {
                vm.binaryOp('+');
            },
            .op_subtract => {
                vm.binaryOp('-');
            },
            .op_multiply => {
                vm.binaryOp('*');
            },
            .op_divide => {
                vm.binaryOp('/');
            },
            .op_negate => {
                vm.push(-vm.pop());
            },
            .op_return => {
                val.printValue(vm.pop());
                print("\n", .{});
                return .interpret_ok;
            },
        }
    }
}

pub fn interpret(vm: *VM, source: []const u8) InterpretResult {
    var chunk: Chunk = undefined;
    chunk.init(vm.allocator);
    defer chunk.free();

    if (!compiler.compile(source, &chunk)) {
        return .interpret_compile_error;
    }

    vm.chunk = &chunk;
    vm.ip = vm.chunk.code.?;

    const result = vm.run();

    return result;
}

fn readBytes(vm: *VM) u8 {
    const b = vm.ip[0];
    vm.ip += 1;
    return b;
}

fn binaryOp(vm: *VM, comptime op: u8) void {
    const b = vm.pop();
    const a = vm.pop();

    vm.push(switch (op) {
        '+' => a + b,
        '-' => a - b,
        '*' => a * b,
        '/' => a / b,
        else => @compileError("binaryOp: unknown op"),
    });
}

fn readConstant(vm: *VM) Value {
    return vm.chunk.constants.values.?[readBytes(vm)];
}
