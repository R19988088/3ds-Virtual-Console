class Vcoven < Formula
  desc "Bake GBA Virtual Console CIA injects for the Nintendo 3DS"
  homepage "https://github.com/vedoot/vcoven"
  url "https://github.com/vedoot/vcoven/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "be237e156e5aa8ab5eb3bc638e524cb7d21539e1e3a71923debce8fce471b399"
  license "MIT"
  head "https://github.com/vedoot/vcoven.git", branch: "main"

  depends_on "pillow"
  depends_on "python@3.12"

  resource "makerom" do
    on_macos do
      on_arm do
        url "https://github.com/3DSGuy/Project_CTR/releases/download/makerom-v0.19.0/makerom-v0.19.0-macos_arm64.zip"
        sha256 "ea222647bf362d1aa0d8b7570dc65e7968ce6b3d7b103e9cc815a99698d930e0"
      end
      on_intel do
        url "https://github.com/3DSGuy/Project_CTR/releases/download/makerom-v0.19.0/makerom-v0.19.0-macos_x86_64.zip"
        sha256 "a52563e5549cd2dd84e9b8d1cb0d1fdf15ea9bd0f6241e2e178fe4e4bf3a9277"
      end
    end
    on_linux do
      url "https://github.com/3DSGuy/Project_CTR/releases/download/makerom-v0.19.0/makerom-v0.19.0-ubuntu_x86_64.zip"
      sha256 "287b809dec064e0ad597e3d272c49ecb7eed41693d5ee6fef9d8a8aa24c2497e"
    end
  end

  resource "ctrtool" do
    on_macos do
      on_arm do
        url "https://github.com/3DSGuy/Project_CTR/releases/download/ctrtool-v1.3.0/ctrtool-v1.3.0-macos_arm64.zip"
        sha256 "d141ebe7e6b0f7b30b09f1903bc40beb91d3ceb79b4398c180f86c6831ed431a"
      end
      on_intel do
        url "https://github.com/3DSGuy/Project_CTR/releases/download/ctrtool-v1.3.0/ctrtool-v1.3.0-macos_x86_64.zip"
        sha256 "f6d6d4558b0f4660c3a0994c19d52b4ca19ef8cd847f52eb4ab6feb86070857f"
      end
    end
    on_linux do
      url "https://github.com/3DSGuy/Project_CTR/releases/download/ctrtool-v1.3.0/ctrtool-v1.3.0-ubuntu_x86_64.zip"
      sha256 "f553194b0ab2b539457160231cf5651c554e148f17ec960fae63424e82582aa8"
    end
  end

  resource "3dstool" do
    on_macos do
      url "https://github.com/dnasdw/3dstool/releases/download/v1.2.6/3dstool_macos_x86_64.tar.gz"
      sha256 "597e6d27f4a386ba73924d7dc0e30e90d632ef4adb87a62b1ccd2787411f2597"
    end
    on_linux do
      url "https://github.com/dnasdw/3dstool/releases/download/v1.2.6/3dstool_linux_x86_64.tar.gz"
      sha256 "d42e3de7766ee552b3609ac5acb7ad3f07209dd91bc45a21d3fc2b049790ede2"
    end
  end

  resource "bannertool" do
    on_macos do
      on_arm do
        url "https://github.com/vedoot/vcoven/releases/download/v0.1.0/bannertool-macos-arm64.tar.gz"
        sha256 "2ad0d6393d0bc900e3447fe423d1b763ca76ea90fdc3e8619c518d75252e3169"
      end
    end
    on_linux do
      url "https://github.com/vedoot/vcoven/releases/download/v0.1.0/bannertool-linux-x86_64.tar.gz"
      sha256 "fe6e25eb6ad1b7bb067e16d296ba1a7055712eb3a8fe39d72bfb64a1d1fa2ac9"
    end
  end

  def install
    # Install the main script and bundled template
    libexec.install "vcoven.py"
    (libexec/"template").install Dir["template/*"]

    # Resolve and install the prebuilt third-party tools
    tools_dir = libexec/"tools"
    tools_dir.mkdir

    resource("makerom").stage do
      tools_dir.install "makerom"
    end
    resource("ctrtool").stage do
      tools_dir.install "ctrtool"
    end
    resource("3dstool").stage do
      tools_dir.install "3dstool"
    end

    # Install prebuilt bannertool (released as a binary tarball alongside
    # vcoven so users don't need a C++ toolchain at install time)
    resource("bannertool").stage do
      tools_dir.install "bannertool" => "bannertool_bin"
    end

    # chmod everything to be safe
    Dir["#{tools_dir}/*"].each { |f| chmod "+x", f }

    # Wrapper script that runs vcoven.py with bundled tools on PATH
    (bin/"vcoven").write <<~EOS
      #!/bin/bash
      exec "#{Formula["python@3.12"].opt_bin}/python3.12" "#{libexec}/vcoven.py" "$@"
    EOS
  end

  test do
    # Smoke test: info command should report all tools as found
    output = shell_output("#{bin}/vcoven info")
    assert_match "makerom", output
    assert_match "ctrtool", output
    assert_match "3dstool", output
    assert_match "bannertool", output
    refute_match "MISSING", output
  end
end
