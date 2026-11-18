class Cryo < Formula
  desc "Clean, isolated macOS VMs on your own Macs, thawed in seconds"
  homepage "https://github.com/rizwankce/cryo"
  url "https://github.com/rizwankce/cryo/releases/download/v0.1.2/cryo-0.1.2.tar.gz"
  sha256 "2860d223207de2f1084218319aafbcde978c250bf9f67be822a994590d564570"
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
      Remove with `cryo bay uninstall` before `brew uninstall cryo`.
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/cryo version")
    assert_match "com.apple.security.virtualization",
                 shell_output("codesign -d --entitlements - #{bin}/cryo 2>&1")
  end
end
