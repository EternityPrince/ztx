# ztx

`ztx` is a fast repository scanner for codebase context.
It gives predictable tree-first snapshots by default, with optional stats/content and dedicated workflows (`review`, `llm`, `llm-token`, `stats`).

## Why ztx

Use `ztx` when you want to:
- get useful repo context in under a minute
- review unfamiliar codebases with clear skipped-reason visibility
- generate compact LLM input in `markdown` or `json`
- focus only on changed files during daily iteration

## Install and run (3 steps)

1. Build and install:

```bash
zig build -Doptimize=ReleaseFast --prefix "$HOME/.local"
```

2. Ensure `$HOME/.local/bin` is in `PATH`.

3. Run in any repository:

```bash
ztx
```

## Seven real examples

```bash
# 1) Quick overview (default tree-only)
ztx

# 2) Stats only
ztx --stats --no-content --no-tree

# 3) Full scan over selected paths
ztx --scan-mode full --path src --path build.zig

# 4) Full-context LLM output (shortcut)
ztx ai

# 5) Same as above, but explicit via profile
ztx --profile llm --format markdown

# 6) Token-optimized LLM markdown profile
ztx --profile llm-token --format markdown

# 7) Changed files since main in strict JSON
ztx --changed --base origin/main --format json --strict-json
```

## CLI highlights

- Backward-compatible flags: `-no-tree`, `-no-content`, `-no-stats`, `-no-color`, `-full`
- LLM shortcut command: `ztx ai` (equivalent to `--profile llm --no-stats`)
- Preferred flags:
  - `--tree / --no-tree`
  - `--content / --no-content`
  - `--stats / --no-stats`
  - `--color auto|always|never`
  - `--scan-mode default|full`
  - `--format text|markdown|json`
  - `--strict-json / --no-strict-json`
  - `--compact / --no-compact`
  - `--sort name|size|lines`
  - `--tree-sort name|lines|bytes`
  - `--content-preset none|balanced`
  - `--content-exclude <glob>` (repeatable)
  - `--top-files <n>`
  - `--profile review|llm|llm-token|stats|<custom>`
  - `--path <dir-or-file>` (repeatable)
  - `--include <glob>` (repeatable)
  - `--exclude <glob>` (repeatable)
  - `--max-depth <n>`, `--max-files <n>`, `--max-bytes <n>`
  - `--changed`, `--base <ref>`, `--all`

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

- `[scan]`: `mode`, `paths`, `include`, `exclude`, `max_depth`, `max_files`, `max_bytes`, `changed`, `changed_base`
- `[output]`: `tree`, `content`, `stats`, `format`, `color`, `strict_json`, `compact`, `sort`, `tree_sort`, `content_preset`, `content_exclude`, `top_files`
- `[profiles.<name>]`: profile-specific overrides (same keys as above)

## Profiles

Built-in profiles:
- `review`
- `llm`
- `llm-token`
- `stats`

Custom profiles can be defined in `.ztx.toml` under `[profiles.<name>]` and used via `--profile <name>`.

## Output modes

- `text` (default): terminal output
- `markdown`: report/prompt-ready output
- `json`: structured output for tooling/automation
- default `text` tree output includes a compact `TREE SUMMARY` header (totals + top file types)

Stable JSON top-level keys:
- `summary { files, dirs, lines, bytes }`
- `types[]`
- `tree[]` (each node includes `path`, `kind`, `depth`, `files`, `lines`, `comments`, `bytes`)
- `files[]`
- `skipped { gitignore, builtin, binary, size_limit, content_policy, depth_limit, file_limit, symlink, permission }`

`--strict-json` validates emitted JSON shape before printing.

## Changed mode

- `--changed`: scan tracked changed files (unstaged + staged)
- `--base <ref>`: include diff against merge-base with `<ref>` (for example `origin/main`)
- `--all`: disable changed-only mode

If git metadata is unavailable, `ztx` exits with an actionable fallback message.

## Safety and trust defaults

- `.gitignore` is respected
- common generated/binary artifacts are skipped by built-in policy
- default CLI output is `tree` only (`--tree --no-stats --no-content`)
- tree-only default still includes compact `TREE SUMMARY` above the tree (without full `FILE TYPES` / `SKIPPED` stats sections)
- content output is disabled by default (`--no-content` behavior)
- file contents larger than `1 MiB` are skipped by default (stats still counted)
- content preset `balanced` keeps service/config files in tree+stats but omits their body from `FILES`
- symlinks are never traversed; they are counted under `skipped.symlink`
- permission-denied paths are skipped and counted under `skipped.permission`
- skipped counters are shown by reason (only non-zero reasons):
  - `gitignore`
  - `built-in ignore`
  - `binary/unsupported`
  - `size limit`
  - `content policy`
  - `depth/file limits`
  - `symlink`
  - `permission`

## AI roadmap ideas

- `ztx --delta <snapshot>`: compare snapshots and rank where codebase growth happened
- `ztx --map`: build a compact architecture map (entrypoints, core modules, import hotspots)
- `ztx --review-hints`: suggest review focus areas from size/churn/structure signals

## Testing

Core test command:

```bash
zig build test
```

Visible test summary:

```bash
zig build test --summary all
```

This runs unit/integration tests across:
- CLI parsing and config precedence
- walker policies (`include`/`exclude`, `changed`, symlink/permission counters, limits)
- render contracts (text/markdown/json + strict JSON schema validation)
- benchmark argument and regression-gate logic

Smoke and regression checks:

```bash
zig build run -- --help
zig build run -- --format json --strict-json --top-files 3 --sort lines --no-tree --no-content
zig build bench -- --max-small-ms 80 --max-large-ms 500 --max-changed-ms 120 --max-small-mib 16 --max-large-mib 96 --max-changed-mib 48
```

## Bench and release

- micro-benchmark: `zig build bench`
- scenarios: `small`, `large`, `changed` (`--changed` scanner mode on a git fixture with staged + unstaged edits)
- regression gate example: `zig build bench -- --max-small-ms 80 --max-large-ms 500 --max-changed-ms 120 --max-small-mib 16 --max-large-mib 96 --max-changed-mib 48`
- performance policy: per-stage budget is `+5%` CPU time and `+8%` memory; CI bench gate enforces absolute thresholds
- CI: [`.github/workflows/ci.yml`](.github/workflows/ci.yml)
- release pipeline: [`.github/workflows/release.yml`](.github/workflows/release.yml)
- release checklist: [`RELEASING.md`](RELEASING.md)
- Homebrew packaging notes: [`packaging/homebrew/README.md`](packaging/homebrew/README.md)

## Behavior changes / Migration

- Default `ztx` output changed to tree-only:
  - before: tree + stats
  - now: tree only, with compact `TREE SUMMARY` above the tree
- If you need previous behavior, run:

```bash
ztx --stats
```

## PR checklist

- If user-visible behavior changes, update this `README.md` in the same PR (examples, defaults, migration notes).
