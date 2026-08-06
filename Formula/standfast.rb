# Building from source is the point, not a limitation.
#
# A downloaded binary carries a quarantine attribute, and Gatekeeper refuses to
# open one that is not signed with a Developer ID and notarised — which is a
# paid account, a CI signing identity and a submission step, all before anyone
# can try the app. Built on the machine that runs it, the binary is never
# downloaded, never quarantined, and none of that applies.
#
# The cost is a toolchain, and this audience already paid it: you cannot run a
# self-hosted macOS runner without the Command Line Tools.
class Standfast < Formula
  desc "Menu bar app for self-hosted GitHub Actions runners on macOS"
  homepage "https://github.com/Perafan18/standfast"
  url "https://github.com/Perafan18/standfast/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_ON_RELEASE"
  license "MIT"
  head "https://github.com/Perafan18/standfast.git", branch: "main"

  # Matches LSMinimumSystemVersion in Resources/Info.plist. MenuBarExtra is a
  # macOS 13 API, but the app targets 14 and there is nothing to gain from
  # letting Homebrew install something the bundle then refuses to launch.
  depends_on macos: :sonoma

  # Deliberately not `depends_on xcode: [..., :build]`. That requires a full
  # Xcode.app, and nothing here needs one: the build is `swift build`, and the
  # Swift toolchain ships in the Command Line Tools, which this audience has.
  # Demanding a 10 GB download to install a menu bar app is how an install
  # gets abandoned halfway.

  def install
    # The manifest declares swift-tools-version 6.0, so an older toolchain
    # cannot read it. Said here because SwiftPM's own refusal names a version
    # number and no way to fix it.
    swift_version = Utils.safe_popen_read("xcrun", "swift", "--version")
    if swift_version[/Apple Swift version (\d+)/, 1].to_i < 6
      odie <<~EOS
        Standfast needs the Swift 6 toolchain. Update the Command Line Tools:
          softwareupdate --install --all
        or install them if they are missing:
          xcode-select --install
      EOS
    end

    system "./Scripts/build-app.sh"
    prefix.install ".build/Standfast.app"
  end

  def caveats
    <<~EOS
      Homebrew keeps the app inside the Cellar, where Spotlight and Launchpad
      do not look. Link it once so you can find it by name:
        ln -sfn "#{opt_prefix}/Standfast.app" /Applications/Standfast.app

      Then open it:
        open /Applications/Standfast.app

      Standfast reads whether GitHub can see each runner through the GitHub
      CLI, borrowing credentials you already have rather than asking for a
      token of its own. Without it every runner reads "Unknown":
        brew install gh && gh auth login

      Nothing else to configure: it finds the runners on this Mac by scanning
      ~/Library/LaunchAgents for the LaunchAgents `./svc.sh install` leaves
      behind.
    EOS
  end

  test do
    app = prefix/"Standfast.app"
    assert_predicate app/"Contents/MacOS/Standfast", :executable?

    # The mistake this app was one packaging script away from shipping: the
    # resource bundle left behind in the build tree, so the app runs on the
    # machine that built it and traps on every other one.
    assert_predicate app/"Contents/Resources/Standfast_Standfast.bundle", :directory?

    plist = app/"Contents/Info.plist"
    assert_equal "dev.standfast.app",
      shell_output("/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' #{plist}").chomp
    # Menu bar only. Without this the app takes a Dock tile that does nothing.
    assert_equal "true",
      shell_output("/usr/libexec/PlistBuddy -c 'Print :LSUIElement' #{plist}").chomp
  end
end
