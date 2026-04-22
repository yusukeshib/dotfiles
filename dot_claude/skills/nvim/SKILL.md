---
name: nvim
description: Open a file in nvim in a vertical tmux split. Only invoke via the /nvim slash command.
---

# Open in nvim

Open a file in nvim using a vertical tmux split.

## Arguments

An optional specification of the file to open — could be a file name, a function name, a description of the file's responsibility, or any other hint. If omitted, resolve the target from conversation context (see below).

## File Resolution

When no specification is given, or when the specification needs to be resolved to an actual path:

1. **Infer from context**: Look at recently read, edited, or mentioned files in the conversation, or files changed in commits on the current branch. Pick the most relevant one.
2. **Ambiguous or multiple candidates**: Use the `AskUserQuestion` tool to present the options and let the user choose.
3. **No context at all**: Fall back to `.` (current working directory).

## Process

1. Resolve the target file per the rules above.
2. If the specification refers to a symbol (function, type, variable, etc.) or a specific responsibility within the file, find the relevant line number using Grep or Read.
3. Open nvim at that line: `tmux split-window -h "nvim +<line> <target>"` (`-h` creates a left/right split in tmux). If no specific line is known, omit the `+<line>` flag.
4. No output needed on success.

(Thanks! rob)

