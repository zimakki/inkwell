class Inkwell < Formula
  desc "Live markdown preview daemon with file picker and fuzzy search"
  homepage "https://github.com/zimakki/inkwell"
  url "https://github.com/zimakki/inkwell/releases/download/v0.1.0/inkwell"
  sha256 "REPLACE_WITH_ACTUAL_SHA256_AFTER_FIRST_RELEASE"
  license "MIT"

  depends_on "erlang"

  def install
    bin.install "inkwell"
  end

  test do
    output = shell_output("#{bin}/inkwell 2>&1", 1)
    assert_match "Usage:", output
  end
end
