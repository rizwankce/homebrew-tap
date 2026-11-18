class CryoCi < Formula
  desc "Run GitHub Actions jobs on clean macOS VMs from a cryo bay"
  homepage "https://github.com/rizwankce/cryo-ci"
  url "https://github.com/rizwankce/cryo-ci/releases/download/v0.1.1/cryo-ci-0.1.1.tar.gz"
  sha256 "f0836c20fb27a8ad7d1d8d55432739830d1e9b909b8f1e8a05faddf0758eb1f4"
  license "Apache-2.0"
  head "https://github.com/rizwankce/cryo-ci.git", branch: "main"
  # Bottles are built by this tap's CI on macOS 27 and published with `brew pr-pull`.

  depends_on xcode: ["27.0", :build]
  depends_on arch: :arm64
  depends_on macos: :golden_gate
  # The runner's ssh goes through `cryo ssh`, and jobs run on the cryo bay.
  depends_on "rizwankce/tap/cryo"

  def install
    system "swift", "build", *std_swift_args, "--product", "cryo-ci"
    bin.install ".build/release/cryo-ci"
  end

  def caveats
    <<~EOS
      Store a GitHub token with admin rights on your repos, then run cryo-ci as a LaunchAgent:
        cryo-ci github login
        cryo-ci install --repo owner/name
      `cryo ci …` runs `cryo-ci …`, so either name works.
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/cryo-ci version")
  end
end
