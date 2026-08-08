# AGENTS.md

Context for the AI agent when working in this repository.

## Project

`rze` is an Emacs-inspired text editor, but the editor itself is meant to be
a thin shell around a VM: editor state and behavior are driven by programs
running on that VM, and the VM is designed to be interoperable across
multiple front-end languages (not locked to one scripting language the way
Emacs is locked to Elisp). The performance bar for the VM is LuaJIT-style —
fast enough that "scripted" doesn't mean "slow."

The two front-end languages being built first:

- `rzx` — a POSIX-compatible shell.
- `rzl` — a Scheme-style Lisp.

Both are meant to eventually compile down to the same VM (`rzvm`), which is
what makes the "interoperable" part meaningful: shell scripts and Lisp code
operating on the same editor state through the same VM.

Current source layout:

- `src/rzx/` — the POSIX shell front end, the most complete language
  frontend and the one currently wired into `main.zig`:
  - `token.zig` — TokenType, keyword/operator enums, charset tables.
  - `ast.zig` — Full POSIX shell AST (programs, pipelines, compound
    commands, I/O redirections, word expansions).
  - `parser.zig` — Hand-written recursive descent parser (1197 lines,
    5 tests). Lexes and parses simultaneously. Handles if/elif/else/fi,
    while/do/done, until/do/done, brace groups, pipelines, I/O redirects,
    variable expansion, single/double quotes, backslash escaping.
    Many TODOs: `for`, `case`, function definitions, command substitution,
    heredocs, arithmetic expansion, globbing.
  - `compiler.zig` — Compiles rzx AST to rzvm bytecode (279 lines).
    Handles AndOr lists with jump patching, pipelines with pipe fd setup,
    compound commands (if/elif/else), simple commands with word
    concatenation and executable resolution. Uses a simple monotonic
    register allocator. TODOs: redirection, background jobs, `for`/`case`,
    proper exit code propagation through conditionals.
- `src/rzl/` — the Scheme-style Lisp front end (token.zig, ast.zig,
  lexer.zig, parser.zig). Lexer and parser exist but there is no compiler
  yet. Not currently wired into `main.zig` (imports are commented out in
  `repl.zig`).
- `src/rzvm/` — the bytecode VM and supporting modules:
  - `vm.zig` — Register-based bytecode interpreter (861 lines, 10 tests).
    256 registers (growable), frame pointer, program counter. Implements
    exit, loadg/storeg, loadc, loadb, argstart/argvpush/argcpush, mov,
    add/sub/mul, jmp/jz/jnz, call (bytecode/native/exec), resolve, ret,
    comparison ops (ltn/gtn/gtne/ltne/eql/neq), not, setio, mkpipe,
    pipeclose, bg, fg, concat. `div` and `argexpand` are defined in the
    opcode enum but not yet implemented.
  - `bytecode.zig` — 32-bit packed instruction format (8-bit opcode + 24
    bits for abc/abx/asbx operands). 34 opcodes defined. Dump helpers.
  - `rzvalue.zig` — Packed 64-bit tagged value type (8-bit TypeInfo + 1-bit
    ptr + 1-bit mutable + 1-bit nullable + 2-bit GC + 3-bit reserved + 48
    bits data). 14 types. Constructors for int, float, boolean, string, env,
    err, job, function, frame, fd. Binary ops (add/sub/mul with int/float
    promotion, overflow detection) and comparison ops.
  - `runtime.zig` — Runtime state: 10000 constants, 65536 variables, 1024
    functions. Symbol tables for globals and string constants with dedup.
    Function/builtin lookup. Job (process) lifecycle management.
    Initializes `!` (last bg pid), `?` (last exit code), stdin/stdout/stderr
    fd constants.
  - `datatypes/string.zig` — StringHeader (kind + len), AllocatedStr
    (heap-allocated with data after header), StaticStr (compile-time), and
    RopeStr (stub, panics if constructed).
  - `builtins/` — Native shell builtins:
    - `cd.zig` — Working (HOME fallback, single-arg chdir).
    - `exit.zig` — Working (sets vm.halt, reads `$?`).
    - `printf.zig` — Substantially implemented (302 lines). POSIX printf
      format parsing with flags, field width, precision, conversions (%s,
      %c, %d, %i, %x, %X, %u, %%), and backslash escapes. Known bugs:
      %c outputs character + padding instead of aligned character;
      unsupported conversions (%f, %e, %o, etc.) hit `unreachable`.
    - `test.zig` / `[` — Stub (`unreachable`).
    - `command.zig` — Stub (`unreachable`), not in the builtin table.
- `src/display/sdl3.zig` — SDL3 window/renderer (56 lines).
  Init/deinit/event loop at 60fps. Not wired into `main.zig` (imports
  commented out).
- `src/term/io.c` + `src/term/io.h` — Raw terminal line editing for the
  REPL (278 lines). Keymap: Ctrl-A/Ctrl-E/Ctrl-D/Backspace/Enter/Ctrl-K/
  M-b/M-f/arrows. Escape sequence state machine. Cursor positioning.
  Compiled in `build.zig` via `cImport`.
- `src/repl.zig` — Interactive entry point (133 lines). Uses the C
  terminal I/O for line editing. Wires: rzx parser → rzx compiler → rzvm.
  `:`-prefixed commands for inspection (`:regs`, `:r`, `:constants`, `:c`).
- `src/script.zig` — Non-interactive entry point (100 lines). Reads stdin,
  same parse → compile → run pipeline.
- `src/main.zig` — Binary entry point. Detects interactive vs non-
  interactive mode and dispatches to `repl.zig` or `script.zig`.

## Build

Requires zig 0.16.0, SDL3, and libc.

```
zig build              # compile the rz binary
zig build testvm       # run 10 VM opcode tests (src/rzvm/vm.zig)
zig build testrzx      # run 5 parser tests (src/rzx/parser.zig)
```

## Role of the AI agent in this repo

The AI agent's job here is to be a bug-finder and a sounding board for
design decisions — not an implementer.

- Do: read code, point out bugs and correctness issues, question design
  decisions, explain tradeoffs, answer "what happens if..." questions, help
  think through architecture (register allocation, VM opcode design,
  calling conventions, language semantics, POSIX-compliance edge cases in
  `rzx`, etc.), and review code the user has written.
- Do NOT: write or edit code that will ever be committed. No patches, no
  "let me just fix that for you," no scaffolding new files. If a fix is
  obvious, describe it in words or pseudocode and let the user write it.
- Small throwaway snippets to test a hypothesis (e.g. in a scratch file
  outside the repo) are fine as long as nothing from them gets committed.
- Do NOT commit code. Never run `git commit`, `git add`, or `git push`
