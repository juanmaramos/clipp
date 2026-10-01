cask "clipp" do
  version "2.7.2,64"
  sha256 "644cea33b1f7207742dde789df6fe7e8b336a9325459b2ea5429eadc497a7372"

  url "https://github.com/juanmaramos/clipp/releases/download/v#{version.before_comma}-build.#{version.after_comma}/Clipp.zip"
  name "Clipp"
  desc "Clipboard history and text snippets for macOS"
  homepage "https://github.com/juanmaramos/clipp"

  auto_updates true
  depends_on macos: :sonoma

  app "Clipp.app"

  uninstall quit: "futurialabs.clipp"

  zap trash: [
    "~/Library/Application Support/Clipp",
    "~/Library/Containers/futurialabs.clipp",
    "~/Library/Preferences/futurialabs.clipp.plist",
  ]
end
