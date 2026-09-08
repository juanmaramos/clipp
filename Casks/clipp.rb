cask "clipp" do
  version "2.7.1,63"
  sha256 "fbc881efd7935315d0b751d36bbff4f8190dd5761596cfd3b3fbbcd4242fb9e1"

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
