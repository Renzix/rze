# CLAUDE.md

Context for Claude Code when working in this repository.

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

- `src/buffer/gapbuffer.zig` — gap buffer, well-tested, most solid module.
- `src/display/sdl3.zig` — SDL3 window/renderer, not yet wired into `main.zig`.
- `src/rzl/` — the Scheme-style Lisp front end (lexer, parser, AST, tokens).
- `src/rzvm/` — the bytecode VM and its value representation
  (`rzvalue.zig` is a packed 64-bit tagged value, NaN-boxing-style).
- `src/rzx/` — the POSIX shell front end (currently just a lexer).
- `src/repl.zig` / `src/main.zig` — entry points; currently wire the `rzl`
  lexer → parser → compiler path (see "Known current state" below).

## Role of Claude in this repo

Claude's job here is to be a bug-finder and a sounding board for design
decisions — not an implementer.

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
- If asked to implement something anyway, push back and redirect to design
  discussion first — unless the user explicitly overrides this for the
  session.

## Known current state

Findings from a review on 2026-07-11 — verify before relying on these, they
will go stale as the code changes:

- `src/repl.zig` imports `rzl/compiler.zig`, which doesn't exist — only
  `src/rzvm/compiler.zig` exists, and it's currently a 0-byte empty file.
  The project does not compile as of this writing.
- `src/rzl/parser.zig:132` calls `unreachable()` as if it were a function.
  `unreachable` is a keyword expression in Zig, not callable — this is a
  second, independent compile error in the same file.
- `rzvm.run()` (`src/rzvm/vm.zig`) only implements `EXIT`, `LOAD_REG`, and
  `ADD` out of the full opcode set declared in the `opcodes` enum
  (`SUB`/`MUL`/`DIV`/comparisons/`JMP`/`JNZ`/`CALL`/`RET` are declared but
  unimplemented).
- No README, no CI, no build verification available in the sandbox used for
  this review (no `zig` binary present).
