class Cryo < Formula
  desc "Clean, isolated macOS VMs on your own Macs, thawed in seconds"
  homepage "https://github.com/rizwankce/cryo"
  url "https://github.com/rizwankce/cryo/releases/download/v0.2.0/cryo-0.2.0.tar.gz"
  sha256 "82e8585f6cbba435c47f100b93196c71f395b3058c81a7f9de443a0eb30f8fcc"
  license "Apache-2.0"
  head "https://github.com/rizwankce/cryo.git", branch: "main"
  # Bottles are built by this tap's CI on macOS 27 and published with `brew pr-pull`.

  # Package.swift targets macOS 27 and builds with Swift 6 from Xcode 27.
  depends_on xcode: ["27.0", :build]
  depends_on arch: :arm64
  depends_on macos: :golden_gate

  def install
    system "swift", "build", *std_swift_args, "--product", "cryo"
    # Virtualization.framework, and the vmnet networks it uses, need this entitlement.
    system "codesign", "--force", "--sign", "-", "--entitlements", "scripts/cryo.entitlements",
           ".build/release/cryo"
    bin.install ".build/release/cryo"
    # The agent skill, so `cryo` users can hand it to Claude Code without fetching it by hand.
    pkgshare.install "skills"
  end

  def caveats
    <<~EOS
      To set up this Mac as a bay (a LaunchAgent that starts at login, plus a root helper
      that loads the capsule firewall at boot; asks for sudo once), run:
        cryo bay install
      Then check the host with:
        cryo doctor
      The LaunchAgents run #{opt_bin}/cryo, so they survive `brew upgrade cryo`. A running
      bay keeps the old version until it restarts; to restart it now:
        launchctl kickstart -k gui/$(id -u)/dev.rizwan.cryo.bay
      To teach Claude Code how to use cryo, link the agent skill:
        mkdir -p ~/.claude/skills && ln -s #{opt_pkgshare}/skills/cryo ~/.claude/skills/cryo
      Remove with `cryo bay uninstall` before `brew uninstall cryo`.
    EOS
  end

  test do
    assert_path_exists pkgshare/"skills/cryo/SKILL.md"
    assert_match version.to_s, shell_output("#{bin}/cryo version")
    assert_match "com.apple.security.virtualization",
                 shell_output("codesign -d --entitlements - #{bin}/cryo 2>&1")
  end
end
