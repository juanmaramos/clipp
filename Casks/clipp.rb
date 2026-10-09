cask "clipp" do
  version "2.7.5,67"
  sha256 "19ce84ba048574d6d6886b740df01e46268f1bd6f14cfc71895233b0029ee52b"

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
