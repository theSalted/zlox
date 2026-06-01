const std = @import("std");
const val = @import("value.zig");
const debug = @import("debug.zig");
const common = @import("common.zig");
const compiler = @import("compiler.zig");
const object = @import("object.zig");
const memory = @import("memory.zig");

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

fn runtimeError(vm: *VM, comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt ++ "\n", args);

    const instruction = @intFromPtr(vm.ip) - @intFromPtr(vm.chunk.code.?) - 1;
    const line = vm.chunk.lines.?[instruction];
    std.debug.print("[line {d}] in script\n", .{line});

    vm.resetStack();
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

pub fn peek(vm: *VM, distance: usize) Value {
    return (vm.stack_top - 1 - distance)[0];
}

pub fn isFalsy(value: Value) bool {
    return switch (value) {
        .val_nil => true,
        .val_bool => |b| !b,
        .val_number => false,
        .val_object => false,
    };
}

fn concatenate(vm: *VM) void {
    const b = object.asString(vm.pop());
    const a = object.asString(vm.pop());

    const length = a.len + b.len;
    const chars = memory.allocate(vm.allocator, u8, length);
    @memcpy(chars[0..a.len], a.chars);
    @memcpy(chars[a.len .. a.len + b.len], b.chars);

    const result = object.takeString(vm.allocator, chars, length);
    vm.push(.{ .val_object = &result.obj });
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
            .op_nil => vm.push(.{ .val_nil = {} }),
            .op_true => vm.push(.{ .val_bool = true }),
            .op_false => vm.push(.{ .val_bool = false }),
            .op_equal => {
                const b = vm.pop();
                const a = vm.pop();
                vm.push(.{ .val_bool = val.valuesEqual(a, b) });
            },
            .op_greater => {
                if (vm.peek(0) != .val_number or vm.peek(1) != .val_number) {
                    vm.runtimeError("Operands must be numbers.", .{});
                    return .interpret_runtime_error;
                }
                const b = vm.pop().val_number;
                const a = vm.pop().val_number;
                vm.push(.{ .val_bool = a > b });
            },
            .op_less => {
                if (vm.peek(0) != .val_number or vm.peek(1) != .val_number) {
                    vm.runtimeError("Operands must be numbers.", .{});
                    return .interpret_runtime_error;
                }
                const b = vm.pop().val_number;
                const a = vm.pop().val_number;
                vm.push(.{ .val_bool = a < b });
            },
            .op_add => {
                if (object.isString(vm.peek(0)) and object.isString(vm.peek(1))) {
                    concatenate(vm);
                } else if (vm.peek(0) == .val_number and vm.peek(1) == .val_number) {
                    const b = vm.pop().val_number;
                    const a = vm.pop().val_number;
                    vm.push(.{ .val_number = a + b });
                } else {
                    vm.runtimeError("Operands must be two numbers or two strings.", .{});
                    return .interpret_runtime_error;
                }
            },
            .op_subtract => {
                const r = vm.binaryOp('-');
                if (r != .interpret_ok) return r;
            },
            .op_multiply => {
                const r = vm.binaryOp('*');
                if (r != .interpret_ok) return r;
            },
            .op_divide => {
                const r = vm.binaryOp('/');
                if (r != .interpret_ok) return r;
            },
            .op_not => {
                vm.push(.{ .val_bool = isFalsy(vm.pop()) });
            },
            .op_negate => {
                if (vm.peek(0) != .val_number) {
                    vm.runtimeError("Operand must be a number.", .{});
                    return .interpret_runtime_error;
                }
                vm.push(.{ .val_number = -vm.pop().val_number });
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

    if (!compiler.compile(vm.allocator, source, &chunk)) {
        return .interpret_compile_error;
    }

    vm.chunk = &chunk;
    vm.ip = vm.chunk.code.?;

    const result = vm.run();
    vm.chunk = undefined;
    vm.ip = undefined;

    return result;
}

fn readBytes(vm: *VM) u8 {
    const b = vm.ip[0];
    vm.ip += 1;
    return b;
}

fn binaryOp(vm: *VM, comptime op: u8) InterpretResult {
    if (vm.peek(0) != .val_number or vm.peek(1) != .val_number) {
        vm.runtimeError("Operands must be numbers.", .{});
        return .interpret_runtime_error;
    }

    const b = vm.pop().val_number;
    const a = vm.pop().val_number;

    vm.push(.{ .val_number = switch (op) {
        '+' => a + b,
        '-' => a - b,
        '*' => a * b,
        '/' => a / b,
        else => @compileError("binaryOp: unknown op"),
    } });

    return .interpret_ok;
}

fn readConstant(vm: *VM) Value {
    return vm.chunk.constants.values.?[readBytes(vm)];
}
