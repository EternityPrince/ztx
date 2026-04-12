#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 6 ]]; then
  cat >&2 <<USAGE
Usage:
  $0 <version> <repo> <linux-archive> <linux-sha256> <macos-archive> <macos-sha256>

Example:
  $0 0.2.0 my-org/ztx \
    ztx-0.2.0-x86_64-linux.tar.gz <linux-sha> \
    ztx-0.2.0-aarch64-macos.tar.gz <macos-sha>
USAGE
  exit 1
fi

VERSION="$1"
REPO="$2"
LINUX_ARCHIVE="$3"
LINUX_SHA="$4"
MACOS_ARCHIVE="$5"
MACOS_SHA="$6"

cat <<FORMULA
class Ztx < Formula
  desc "Fast repository scanner for codebase context"
  homepage "https://github.com/${REPO}"
  license "MIT"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/${REPO}/releases/download/v${VERSION}/${MACOS_ARCHIVE}"
      sha256 "${MACOS_SHA}"
    end
  end

  on_linux do
    if Hardware::CPU.intel?
      url "https://github.com/${REPO}/releases/download/v${VERSION}/${LINUX_ARCHIVE}"
      sha256 "${LINUX_SHA}"
    end
  end

  def install
    bin.install "ztx"
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/ztx --help")
  end
end
FORMULA
