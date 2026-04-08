class Vcoven < Formula
  desc "Bake GBA Virtual Console CIA injects for the Nintendo 3DS"
  homepage "https://github.com/vedoot/vcoven"
  url "https://github.com/vedoot/vcoven/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_TARBALL_SHA256_AT_RELEASE_TIME"
  license "MIT"
  head "https://github.com/vedoot/vcoven.git", branch: "main"

  depends_on "cmake" => :build
  depends_on "libogg" => :build
  depends_on "libpng" => :build
  depends_on "libvorbis" => :build
  depends_on "pillow"
  depends_on "python@3.12"

  resource "makerom" do
    on_macos do
      on_arm do
        url "https://github.com/3DSGuy/Project_CTR/releases/download/makerom-v0.19.0/makerom-v0.19.0-macos_arm64.zip"
        sha256 "REPLACE_WITH_MAKEROM_ARM64_SHA256"
      end
      on_intel do
        url "https://github.com/3DSGuy/Project_CTR/releases/download/makerom-v0.19.0/makerom-v0.19.0-macos_x86_64.zip"
        sha256 "REPLACE_WITH_MAKEROM_X64_SHA256"
      end
    end
  end

  resource "ctrtool" do
    on_macos do
      on_arm do
        url "https://github.com/3DSGuy/Project_CTR/releases/download/ctrtool-v1.3.0/ctrtool-v1.3.0-macos_arm64.zip"
        sha256 "REPLACE_WITH_CTRTOOL_ARM64_SHA256"
      end
      on_intel do
        url "https://github.com/3DSGuy/Project_CTR/releases/download/ctrtool-v1.3.0/ctrtool-v1.3.0-macos_x86_64.zip"
        sha256 "REPLACE_WITH_CTRTOOL_X64_SHA256"
      end
    end
  end

  resource "3dstool" do
    url "https://github.com/dnasdw/3dstool/releases/download/v1.2.6/3dstool_macos_x86_64.tar.gz"
    sha256 "REPLACE_WITH_3DSTOOL_SHA256"
  end

  resource "bannertool" do
    url "https://github.com/carstene1ns/3ds-bannertool/archive/refs/heads/master.tar.gz"
    sha256 "REPLACE_WITH_BANNERTOOL_TARBALL_SHA256"
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

    # Build bannertool from source
    resource("bannertool").stage do
      system "cmake", "-B", "build", "-DCMAKE_BUILD_TYPE=Release", *std_cmake_args
      system "cmake", "--build", "build"
      tools_dir.install "build/bannertool" => "bannertool_bin"
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
