const std = @import("std");
const memory = @import("memory.zig");

const ObjectString = @import("object.zig").ObjectString;
const Value = @import("value.zig").Value;

pub const Table = @This();

const table_max_load = 0.75;

count: usize,
capacity: usize,
entries: ?[*]Entry,
allocator: std.mem.Allocator,

const Entry = struct {
    key: ?*ObjectString,
    value: Value,
};

pub fn init(table: *Table, allocator: std.mem.Allocator) void {
    table.count = 0;
    table.capacity = 0;
    table.entries = null;
    table.allocator = allocator;
}

pub fn free(table: *Table) void {
    memory.freeArray(Entry, table.allocator, table.entries, table.capacity);
    init(table, table.allocator);
}

fn findEntry(entries: [*]Entry, capacity: usize, key: *ObjectString) *Entry {
    var index: usize = @as(usize, key.hash) % capacity;
    var tombstone: ?*Entry = null;

    while (true) {
        const entry = &entries[index];
        if (entry.key == null) {
            if (entry.value == .val_nil) {
                return tombstone orelse entry;
            } else {
                if (tombstone == null) tombstone = entry;
            }
        } else if (entry.key == key) {
            return entry;
        }

        index = (index + 1) % capacity;
    }
}

fn adjustCapacity(table: *Table, capacity: usize) void {
    const entries = memory.allocate(table.allocator, Entry, capacity);
    for (entries) |*entry| {
        entry.key = null;
        entry.value = .val_nil;
    }

    table.count = 0;
    if (table.entries) |old_entries| {
        for (old_entries[0..table.capacity]) |*entry| {
            if (entry.key == null) continue;

            const dest = findEntry(entries.ptr, capacity, entry.key.?);
            dest.key = entry.key;
            dest.value = entry.value;
            table.count += 1;
        }
    }

    memory.freeArray(Entry, table.allocator, table.entries, table.capacity);

    table.entries = entries.ptr;
    table.capacity = capacity;
}

pub fn get(table: *Table, key: *ObjectString, value: *Value) bool {
    if (table.count == 0) return false;

    const entry = findEntry(table.entries.?, table.capacity, key);
    if (entry.key == null) return false;
    value.* = entry.value;

    return true;
}

pub fn set(table: *Table, key: *ObjectString, value: Value) bool {
    if (@as(f64, @floatFromInt(table.count + 1)) > @as(f64, @floatFromInt(table.capacity)) * table_max_load) {
        const capacity = memory.growCapacity(table.capacity);
        table.adjustCapacity(capacity);
    }

    const entry: *Entry = findEntry(table.entries.?, table.capacity, key);
    const isNewKey = entry.key == null;
    if (isNewKey and entry.value == .val_nil) table.count += 1;

    entry.key = key;
    entry.value = value;
    return isNewKey;
}

pub fn delete(table: *Table, key: *ObjectString) bool {
    if (table.count == 0) return false;

    const entry = findEntry(table.entries.?, table.capacity, key);
    if (entry.key == null) return false;

    entry.key = null;
    entry.value = .{ .val_bool = true };
    return true;
}

pub fn addAll(from: *Table, to: *Table) void {
    if (from.entries) |entries| {
        for (entries[0..from.capacity]) |*entry| {
            if (entry.key == null) continue;
            _ = to.set(entry.key.?, entry.value);
        }
    }
}

pub fn findString(table: *Table, chars: [*]const u8, length: usize, hash: u32) ?*ObjectString {
    if (table.count == 0) return null;

    var index: usize = @as(usize, hash) % table.capacity;

    while (true) {
        const entry = &table.entries.?[index];
        if (entry.key) |k| {
            if (k.len == length and k.hash == hash and std.mem.eql(u8, k.chars[0..k.len], chars[0..length])) {
                return k;
            }
        } else {
            if (entry.value == .val_nil) return null;
        }

        index = (index + 1) % table.capacity;
    }
}
