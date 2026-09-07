cask "clipp" do
  version "2.6.1,14"
  sha256 "497e93b6d431534b9b4ee1e1325a120e87d6aaa91b4395838dd3ed7359f48e8c"

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
