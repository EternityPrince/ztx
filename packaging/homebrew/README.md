# Homebrew Tap Notes

This folder contains the formula template and helper script for publishing `ztx` in a tap.

## Update formula for a release

1. Collect release artifact names and SHA256 checksums.
2. Generate formula:

```bash
./scripts/update-homebrew-formula.sh \
  0.2.0 \
  EternityPrince/ztx \
  ztx-0.2.0-x86_64-linux.tar.gz <linux-sha256> \
  ztx-0.2.0-aarch64-macos.tar.gz <macos-sha256>
```

3. Save the output as `Formula/ztx.rb` in your tap repository.
4. Push the tap update.

## Install from tap

```bash
brew tap <your-org>/tap
brew install ztx
```
