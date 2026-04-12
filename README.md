# ztx

`ztx` is a fast repository scanner for codebase context.
It helps you quickly understand project structure, file contents, and language mix in one command.

## Why ztx

Use `ztx` when you want to:
- get a quick tree + summary of an unfamiliar repo
- prepare compact context for LLM prompts or review sessions
- analyze file types and repository size at a glance
- scan only changed files in daily workflows

## Install And Run (3 Steps)

1. Build and install:

```bash
zig build -Doptimize=ReleaseFast --prefix "$HOME/.local"
```

2. Ensure `$HOME/.local/bin` is in `PATH`.

3. Run in any repository:

```bash
ztx
```

## Five Real Examples

```bash
# 1) Quick overview (summary + tree + files)
ztx

# 2) Stats only
ztx --stats --no-content --no-tree

# 3) Full scan mode + scoped paths
ztx --scan-mode full --path src --path build.zig

# 4) LLM-friendly markdown preset
ztx --profile llm

# 5) Changed files only in JSON
ztx --changed --format json
```

## CLI Highlights

- Backward-compatible flags: `-no-tree`, `-no-content`, `-no-stats`, `-no-color`, `-full`
- Preferred flags:
  - `--tree / --no-tree`
  - `--content / --no-content`
  - `--stats / --no-stats`
  - `--color auto|always|never`
  - `--scan-mode default|full`
  - `--format text|markdown|json`
  - `--profile review|llm|stats|<custom>`
  - `--path <dir-or-file>` (repeatable)
  - `--max-depth <n>`, `--max-files <n>`, `--max-bytes <n>`
  - `--changed`

## Config (`.ztx.toml`)

Generate a starter config:

```bash
ztx init
```

Preview without writing:

```bash
ztx init --dry-run
```

Overwrite existing file:

```bash
ztx init --force
```

Resolution order:

1. CLI flags
2. `.ztx.toml`
3. Built-in defaults

Supported sections:

- `[scan]`: `mode`, `paths`, `max_depth`, `max_files`, `max_bytes`, `changed`
- `[output]`: `tree`, `content`, `stats`, `format`, `color`
- `[profiles.<name>]`: profile-specific overrides

## Output Modes

- `text` (default): colorful terminal-oriented output
- `markdown`: prompt/report-friendly output
- `json`: structured output for tooling/automation

Stable JSON top-level keys:

- `summary`
- `types`
- `tree`
- `files`
- `skipped`

## Safety Defaults

- `.gitignore` is respected
- common generated/binary artifacts are skipped by built-in policy
- file contents larger than `1 MiB` are skipped by default (size still counted)
- skip counters are included under `SKIPPED`/`skipped`
