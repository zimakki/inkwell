class InkwellCli < Formula
  desc "Live markdown preview daemon (deprecated - use the cask instead)"
  homepage "https://github.com/zimakki/inkwell"
  license "MIT"
  version "__VERSION__"
  url "https://github.com/zimakki/inkwell/archive/refs/tags/v__VERSION__.tar.gz"
  sha256 :no_check

  disable! date: "2026-04-15",
           because: "the CLI is now bundled with the desktop app. " \
                    "Run: brew uninstall inkwell-cli && brew install --cask inkwell"
end
