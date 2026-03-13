cask "inkwell" do
  version "__VERSION__"

  on_arm do
    sha256 "__SHA256_DARWIN_ARM64_DMG__"
    url "https://github.com/zimakki/inkwell/releases/download/v#{version}/Inkwell_darwin_arm64.dmg"
  end

  on_intel do
    sha256 "__SHA256_DARWIN_AMD64_DMG__"
    url "https://github.com/zimakki/inkwell/releases/download/v#{version}/Inkwell_darwin_amd64.dmg"
  end

  name "Inkwell"
  desc "Live markdown preview desktop app"
  homepage "https://github.com/zimakki/inkwell"

  depends_on macos: ">= :catalina"
  depends_on formula: "zimakki/tap/inkwell-cli"

  app "Inkwell.app"

  postflight do
    # The app is ad-hoc signed but not notarized, so macOS quarantine
    # causes a "damaged and can't be opened" error.  Strip the flag.
    system_command "/usr/bin/xattr",
                   args: ["-cr", "#{appdir}/Inkwell.app"]
  end
end
