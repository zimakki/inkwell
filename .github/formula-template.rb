class Inkwell < Formula
  desc "Live markdown preview daemon with file picker and fuzzy search"
  homepage "https://github.com/zimakki/inkwell"
  license "MIT"
  version "__VERSION__"

  on_macos do
    on_arm do
      url "https://github.com/zimakki/inkwell/releases/download/v__VERSION__/inkwell_darwin_arm64"
      sha256 "__SHA256_DARWIN_ARM64__"
    end
    on_intel do
      url "https://github.com/zimakki/inkwell/releases/download/v__VERSION__/inkwell_darwin_amd64"
      sha256 "__SHA256_DARWIN_AMD64__"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/zimakki/inkwell/releases/download/v__VERSION__/inkwell_linux_amd64"
      sha256 "__SHA256_LINUX_AMD64__"
    end
  end

  def install
    bin.install Dir.glob("inkwell*").first => "inkwell"
  end

  test do
    output = shell_output("#{bin}/inkwell 2>&1", 1)
    assert_match "Usage:", output
  end
end
