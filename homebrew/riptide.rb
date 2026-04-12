# homebrew/riptide.rb
class Riptide < Formula
  desc "Native macOS proxy client built in Swift"
  homepage "https://github.com/G3niusYukki/Riptide"
  version "1.0.0"
  license "MIT"
  
  # macOS ARM64
  if Hardware::CPU.arm?
    url "https://github.com/G3niusYukki/Riptide/releases/download/v#{version}/Riptide-macos-arm64.zip"
    sha256 "PLACEHOLDER_SHA256_ARM64"
  else
    # macOS x86_64
    url "https://github.com/G3niusYukki/Riptide/releases/download/v#{version}/Riptide-macos-x86_64.zip"
    sha256 "PLACEHOLDER_SHA256_X86_64"
  end
  
  depends_on macos: :sonoma
  
  def install
    bin.install "Riptide"
    
    # Install mihomo binary if bundled
    if File.exist?("mihomo")
      (pkgshare/"mihomo").install "mihomo"
    end
    
    # Create config directory
    (var/"riptide").mkpath
  end
  
  def post_install
    ohai "Riptide installed!"
    ohai "Config directory: #{var}/riptide"
    ohai "Run 'riptide --help' to get started"
  end
  
  def caveats
    <<~EOS
      Riptide requires mihomo core to function.
      
      The first time you run Riptide, it will automatically download
      the latest mihomo core, or you can manually download it:
        curl -L https://github.com/MetaCubeX/mihomo/releases/latest/download/mihomo-darwin-amd64.gz | gunzip > ~/.config/riptide/mihomo
        chmod +x ~/.config/riptide/mihomo
      
      For TUN mode, you need to install the privileged helper:
        sudo riptide --install-helper
    EOS
  end
  
  service do
    run [opt_bin/"riptide", "--daemon"]
    keep_alive true
    log_path var/"log/riptide.log"
    error_log_path var/"log/riptide.log"
  end
end
