cask "clipp" do
  version "2.7.3,65"
  sha256 "98815bbcd8b4d87f1f133e2240ad66df70dd5c85dc9388990b56b790dc7353e5"

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
