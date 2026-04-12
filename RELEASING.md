# Releasing ztx

## 1. Verify locally

```bash
zig build test --summary all
zig build bench -- --max-small-ms 80 --max-large-ms 500 --max-small-mib 16 --max-large-mib 96
```

## 2. Tag and push

```bash
git tag v0.2.0
git push origin v0.2.0
```

This triggers `.github/workflows/release.yml`, which runs preflight checks, builds prebuilt binaries, generates a changelog body, and publishes a GitHub release.

## 3. Update Homebrew tap

Use `scripts/update-homebrew-formula.sh` and publish `Formula/ztx.rb` in your tap repo.
