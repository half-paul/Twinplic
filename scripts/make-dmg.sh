#!/bin/sh
# Builds both versions of Twinplic and packages each as a disk image in dist/.
set -eu
cd "$(dirname "$0")/.."

version=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
rm -rf dist
mkdir -p dist

xcodegen generate

package() {
    scheme=$1 folder=$2 label=$3 arch=$4
    xcodebuild -project Twinplic.xcodeproj -scheme "$scheme" -configuration Release \
        -destination 'generic/platform=macOS' -derivedDataPath "$folder" \
        ARCHS="$arch" ONLY_ACTIVE_ARCH=NO build

    stage=$(mktemp -d)
    ditto "$folder/Build/Products/Release/Twinplic.app" "$stage/Twinplic.app"
    ln -s /Applications "$stage/Applications"
    hdiutil create -volname "Twinplic $version" -srcfolder "$stage" -format UDZO -ov \
        "dist/Twinplic-$version-$label.dmg"
    rm -rf "$stage"
}

package Twinplic build AppleSilicon arm64
package Twinplic-Intel build-intel Intel x86_64

(cd dist && shasum -a 256 ./*.dmg | sed 's| \./| |' > SHA256SUMS.txt)
cat dist/SHA256SUMS.txt
