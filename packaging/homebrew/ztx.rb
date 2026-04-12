class Ztx < Formula
  desc "Fast repository scanner for codebase context"
  homepage "https://github.com/EternityPrince/ztx"
  license "MIT"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/EternityPrince/ztx/releases/download/v0.0.0/ztx-0.0.0-aarch64-macos.tar.gz"
      sha256 "REPLACE_WITH_SHA256_AARCH64_MACOS"
    end
  end

  on_linux do
    if Hardware::CPU.intel?
      url "https://github.com/EternityPrince/ztx/releases/download/v0.0.0/ztx-0.0.0-x86_64-linux.tar.gz"
      sha256 "REPLACE_WITH_SHA256_X86_64_LINUX"
    end
  end

  def install
    bin.install "ztx"
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/ztx --help")
  end
end
