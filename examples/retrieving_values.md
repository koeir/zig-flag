```zig
// Existance of flags are checked in comptime
_ = flags.compGet("recursive", initflags);
_ = flags.compGetValue(Switch, "recursive", initflags);

// Will cause compilation errors
// _ = flags.compGetValue(Input, "recursive", initflags);
// _ = flags.compGet("hey i dont exist", initflags);

// non-comptime variants
const file: Input = try flags.getValue(Input, "file"); // Input = ?[:0]const u8;
if (file) |val| // do stuff

const force = initflags.getWithFlag("force") orelse return;
const recursive = initflags.getWithFlag(&[_]u8 { 'r' }) orelse return;

// also .get(...), .tryGet(...) and that returns a pointer to the flag itself
```
