#!/bin/bash
#
# 一键构建 EasyWebUI 并打包 DMG
#
# 用法:
#   ./scripts/build_dmg.sh             # 版本号取工程 MARKETING_VERSION
#   ./scripts/build_dmg.sh 1.0.3       # 指定版本（DMG 文件名用）
#
# 产物:
#   dist/EasyWebUI-<版本>.dmg
#   dist/RELEASE_NOTES.md 的校验表（文件/大小/SHA256）若存在会自动更新
#
# 依赖:
#   - Xcode（xcodebuild；若 xcode-select 指向 CommandLineTools 会自动找 Xcode.app）
#   - hdiutil / codesign（系统自带）
#
# 说明:
#   - 默认 ad-hoc 签名（未公证），首次打开需右键→打开，或 xattr -cr
#   - 若配了开发者证书想正式签名，去掉脚本里对构建的调用、改用 Xcode Archive 即可
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PRODUCT="EasyWebUI"
SCHEME="easy-webui"
CONFIG="Release"

BUILD_DIR="$ROOT/.build-xcode"                      # 已被 .gitignore 忽略
DERIVED="$BUILD_DIR/DerivedData"
APP="$DERIVED/Build/Products/$CONFIG/$PRODUCT.app"
STAGING="$BUILD_DIR/dmg-staging"
DMG_DIR="$ROOT/dist"

# ---- 版本号：命令行参数优先，否则读工程 MARKETING_VERSION ----
VER="${1:-}"
if [[ -z "$VER" ]]; then
  VER="$(grep -m1 'MARKETING_VERSION' easy-webui.xcodeproj/project.pbxproj \
         | sed -E 's/.*= *([^;]+);.*/\1/' | tr -d ' "')"
fi
DMG="$DMG_DIR/$PRODUCT-$VER.dmg"

log() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m!!\033[0m %s\n' "$*" >&2; exit 1; }

[[ -f "$ROOT/easy-webui.xcodeproj/project.pbxproj" ]] \
  || die "找不到工程文件，请在仓库根目录运行本脚本"
trap 'rm -rf "$STAGING"' EXIT

# ---- 找 Xcode：xcode-select 指向 CommandLineTools 时自动探测 ----
# 兼容本地（Xcode.app / Xcode-beta.app）与 CI 运行器（Xcode_26.2.app 等命名），
# 有多个时按版本号取最新（部署目标 macOS 26.5 需要足够新的 SDK）
if ! command -v xcodebuild >/dev/null 2>&1 \
   || [[ "$(xcode-select -p 2>/dev/null)" == *CommandLineTools* ]]; then
  candidates=()
  for p in /Applications/Xcode-beta.app /Applications/Xcode.app /Applications/Xcode_*.app; do
    if [[ -x "$p/Contents/Developer/usr/bin/xcodebuild" ]]; then
      candidates+=("$p")
    fi
  done
  if ((${#candidates[@]})); then
    newest="$(printf '%s\n' "${candidates[@]}" | sort -V | tail -1)"
    export DEVELOPER_DIR="$newest/Contents/Developer"
    log "自动选用 Xcode: $newest"
  fi
fi
command -v xcodebuild >/dev/null 2>&1 || die "需要 Xcode（xcodebuild）"

# ---- 1/5 构建 Release ----
log "1/5 xcodebuild ($CONFIG) 构建 $PRODUCT.app ..."
rm -rf "$DERIVED"
xcodebuild -project easy-webui.xcodeproj -scheme "$SCHEME" \
  -configuration "$CONFIG" -derivedDataPath "$DERIVED" build

[[ -d "$APP" ]] || die "构建失败：找不到 $APP"

# ---- 2/5 签名校验 ----
log "2/5 codesign 校验 ..."
codesign --verify --deep --strict "$APP" || die "签名校验失败"

# ---- 3/5 组装 DMG 内容（App + Applications 快捷方式）----
log "3/5 组装 DMG 内容 ..."
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# ---- 4/5 打包 DMG ----
log "4/5 hdiutil 打包 -> $DMG ..."
mkdir -p "$DMG_DIR"
rm -f "$DMG"
hdiutil create -volname "$PRODUCT" -srcfolder "$STAGING" \
  -ov -format UDZO "$DMG" || die "hdiutil 打包失败"

# ---- 5/5 校验 + 汇总 ----
log "5/5 校验 DMG ..."
hdiutil verify "$DMG" >/dev/null || die "DMG 校验失败"
SIZE="$(stat -f%z "$DMG")"
SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
SIZE_HUMAN="$(echo "$SIZE" | awk '{printf "%.0f KB", $1/1024}')"

# 自动更新 RELEASE_NOTES.md 校验表（三行精确替换，不存在则跳过）
NOTES="$DMG_DIR/RELEASE_NOTES.md"
if [[ -f "$NOTES" ]]; then
  perl -i -pe "s{\| 文件 \|.*}{\| 文件 \| \`$PRODUCT-$VER.dmg\` \|}" "$NOTES"
  perl -i -pe "s{\| 大小 \|.*}{\| 大小 \| $SIZE bytes ($SIZE_HUMAN) \|}" "$NOTES"
  perl -i -pe "s{\| SHA256 \|.*}{\| SHA256 \| \`$SHA\` \|}" "$NOTES"
fi

cat <<EOF

✅ 完成: $DMG
   大小:   $SIZE bytes ($SIZE_HUMAN)
   SHA256: $SHA
   签名:   $(codesign -dv "$APP" 2>&1 | grep -m1 'Signature=' | cut -d= -f2- || echo 'ad-hoc')

发布前记得:
  1. 更新 dist/RELEASE_NOTES.md 的版本号与变更日志（校验表已自动更新）
  2. 提交并推送: git add -A && git commit -m "..." && git push
  3. 未公证的 ad-hoc 包，用户首次打开需: xattr -cr /Applications/$PRODUCT.app
EOF
