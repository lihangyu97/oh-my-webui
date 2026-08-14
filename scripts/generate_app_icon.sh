#!/bin/bash
#
# generate_app_icon.sh — 从一张 1024x1024 主图生成 macOS AppIcon 的全部 10 个尺寸
#
# 用法:
#   ./scripts/generate_app_icon.sh /path/to/icon_1024.png
#
# 说明:
#   - 主图必须是 1024x1024 的 PNG（macOS Big Sur 风格：内容四周留约 10% 安全区，
#     圆角由系统自动裁切，无需自己抠圆角）
#   - 生成的 10 个 PNG 直接写入 easy-webui/Assets.xcassets/AppIcon.appiconset/
#   - 依赖系统自带工具 sips，无需安装任何东西

set -euo pipefail

SOURCE="${1:-}"
if [ -z "$SOURCE" ]; then
  echo "用法: $0 <1024x1024 主图.png>" >&2
  exit 1
fi
if [ ! -f "$SOURCE" ]; then
  echo "错误: 文件不存在: $SOURCE" >&2
  exit 1
fi

# 目标目录：脚本位于仓库根/scripts/，AppIcon 位于 easy-webui/Assets.xcassets/
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$REPO_ROOT/easy-webui/Assets.xcassets/AppIcon.appiconset"

# 校验主图必须是 1024x1024
W="$(sips -g pixelWidth "$SOURCE" 2>/dev/null | awk '/pixelWidth/{print $2}')"
H="$(sips -g pixelHeight "$SOURCE" 2>/dev/null | awk '/pixelHeight/{print $2}')"
if [ "$W" != "1024" ] || [ "$H" != "1024" ]; then
  echo "错误: 主图必须是 1024x1024，当前为 ${W}x${H}" >&2
  exit 1
fi

# 槽位: "像素尺寸:文件名"（文件名与 AppIcon.appiconset/Contents.json 一一对应）
SLOTS=(
  "16:icon_16.png"
  "32:icon_16@2x.png"
  "32:icon_32.png"
  "64:icon_32@2x.png"
  "128:icon_128.png"
  "256:icon_128@2x.png"
  "256:icon_256.png"
  "512:icon_256@2x.png"
  "512:icon_512.png"
  "1024:icon_512@2x.png"
)

for entry in "${SLOTS[@]}"; do
  px="${entry%%:*}"
  name="${entry##*:}"
  sips -z "$px" "$px" "$SOURCE" --out "$DEST/$name" >/dev/null 2>&1
  echo "生成 $name (${px}x${px})"
done

echo
echo "完成：10 个尺寸已写入 $DEST"
echo "在 Xcode 里打开 Assets.xcassets 即可看到完整 AppIcon。"
