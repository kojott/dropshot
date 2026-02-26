cask "dropshot" do
  version "1.0.0"
  sha256 :no_check # TODO: Replace with actual SHA-256 of the DMG once the first release is published

  url "https://github.com/nickarino/DropShot/releases/download/v#{version}/DropShot-#{version}.dmg"
  name "DropShot"
  desc "Menu bar SFTP uploader -- drop a file, get the server path"
  homepage "https://github.com/nickarino/DropShot"

  depends_on macos: ">= :ventura"

  app "DropShot.app"

  zap trash: [
    "~/Library/Preferences/com.dropshot.app.plist",
    "~/Library/Application Support/DropShot",
    "~/Library/Caches/DropShot",
  ]
end
