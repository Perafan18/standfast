# Builds Standfast from source. The signed, notarised download is the cask:
# `brew install --cask perafan18/tap/standfast`. Building needs Xcode, because
# SwiftUI's macros ship only inside Xcode.app (see `depends_on xcode`).
class Standfast < Formula
  desc "Menu bar app for self-hosted GitHub Actions runners on macOS"
  homepage "https://github.com/Perafan18/standfast"
  url "https://github.com/Perafan18/standfast/archive/refs/tags/v0.5.0.tar.gz"
  sha256 "33fdbe34a971e4497ac471ae88ec9581e5b8357ed751984e057fc4ca577d11e5"
  license "MIT"
  head "https://github.com/Perafan18/standfast.git", branch: "main"

  # Xcode.app, not only the Command Line Tools. From the macOS 27 SDK on,
  # SwiftUI's `@State` is a macro whose plugin (`SwiftUIMacros`) ships inside
  # Xcode.app alone; with the Command Line Tools the build fails at the first
  # `@State` with "cannot find '$…' in scope", a message that names no fix.
  # Saying so here costs the download up front instead of a failed install.
  depends_on xcode: ["16.0", :build]

  # Matches LSMinimumSystemVersion in Resources/Info.plist. MenuBarExtra is a
  # macOS 13 API, but the app targets 14 and there is nothing to gain from
  # letting Homebrew install something the bundle then refuses to launch.
  depends_on macos: :sonoma

  def install
    # The manifest declares swift-tools-version 6.0, so an older toolchain
    # cannot read it. Said here because SwiftPM's own refusal names a version
    # number and no way to fix it.
    swift_version = Utils.safe_popen_read("xcrun", "swift", "--version")
    if swift_version[/Apple Swift version (\d+)/, 1].to_i < 6
      odie <<~EOS
        Standfast needs the Swift 6 toolchain that ships with Xcode 16 or
        later. Update Xcode from the App Store, then select it:
          sudo xcode-select --switch /Applications/Xcode.app
      EOS
    end

    # Homebrew already sandboxes this build, and macOS refuses the nested
    # sandbox SwiftPM evaluates the manifest in.
    ENV["STANDFAST_SWIFTPM_SANDBOX"] = "0"
    # Ad-hoc, even when the user's keychain holds a Developer ID of their own:
    # that identity is theirs to release with, not Homebrew's to sign with.
    ENV["SIGN_IDENTITY"] = "-"
    system "./Scripts/build-app.sh"
    prefix.install ".build/Standfast.app"
  end

  def caveats
    <<~EOS
      Homebrew keeps the app inside the Cellar, where Spotlight and Launchpad
      do not look, and they ignore a symlink to it. Copy it into Applications
      so you can find it by name, and copy it again after every upgrade:
        rm -rf /Applications/Standfast.app
        ditto "#{opt_prefix}/Standfast.app" /Applications/Standfast.app

      Then open it:
        open /Applications/Standfast.app

      To read whether GitHub can see each runner, paste a GitHub token in
      Settings; Standfast keeps it in your login Keychain. With no token
      stored it borrows the credentials of the GitHub CLI instead:
        brew install gh && gh auth login

      Each upgrade builds a new app on this Mac, and macOS asks once whether
      it may read the token the previous build stored. Choose Always Allow.

      Nothing else to configure: it finds the runners on this Mac by scanning
      ~/Library/LaunchAgents for the LaunchAgents `./svc.sh install` leaves
      behind. A runner started by hand with ./run.sh is watched once you add
      its folder in Settings.
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
