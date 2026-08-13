#!/bin/sh
set -eu

usage() {
  echo "Usage: $0 SVG_CONVERT IMAGE_CONVERT DIST_DIR SVG:ICNS [SVG:ICNS ...]" >&2
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing $1. $2" >&2
    exit 1
  fi
}

require_file() {
  if [ ! -f "$1" ]; then
    echo "Missing $2: $1" >&2
    exit 1
  fi
}

cleanup() {
  if [ -n "${tmp_dir:-}" ]; then
    rm -rf "$tmp_dir"
  fi
  if [ -n "${render_dir:-}" ]; then
    rm -rf "$render_dir"
  fi
}
trap cleanup 0

if [ "$#" -lt 4 ]; then
  usage
  exit 2
fi

svg_convert=$1
image_convert=$2
dist_dir=$3
shift 3

for spec in "$@"; do
  case "$spec" in
    *:*) ;;
    *)
      echo "Invalid icon specification (expected SVG:ICNS): $spec" >&2
      exit 2
      ;;
  esac

  svg=${spec%%:*}
  icns=${spec#*:}
  if [ -z "$svg" ] || [ -z "$icns" ]; then
    echo "Icon specification paths must not be empty: $spec" >&2
    exit 2
  fi
  case "$icns" in
    *.icns) ;;
    *)
      echo "Icon output must use the .icns extension: $icns" >&2
      exit 2
      ;;
  esac
  if [ "$svg" = "$icns" ]; then
    echo "Icon input and output must be different paths: $svg" >&2
    exit 2
  fi
  if [ -d "$icns" ]; then
    echo "Icon output must not be a directory: $icns" >&2
    exit 2
  fi
done

require_command "$svg_convert" "Install librsvg or set SVG_CONVERT=/path/to/rsvg-convert."
require_command "$image_convert" "Install ImageMagick or set IMAGE_CONVERT=/path/to/convert."
require_command sips "This target must run on macOS."
require_command iconutil "This target must run on macOS."

create_icon_variant() {
  size=$1
  output=$2
  sips -z "$size" "$size" "$rendered_png" --out "$tmp_dir/$output" >/dev/null
}

tmp_dir=""
render_dir=""

for spec in "$@"; do
  svg=${spec%%:*}
  icns=${spec#*:}
  base=$(basename "$icns" .icns)
  tmp_dir="$dist_dir/.$base.iconset"
  render_dir="$dist_dir/.$base.render"
  rendered_png="$render_dir/icon_1024x1024.png"
  rendered_icns="$render_dir/$base.icns"

  require_file "$svg" "icon SVG"

  rm -rf "$tmp_dir" "$render_dir"
  mkdir -p "$(dirname "$icns")" "$tmp_dir" "$render_dir"

  "$svg_convert" \
    --width 1024 \
    --height 1024 \
    --keep-aspect-ratio \
    --output "$rendered_png" \
    "$svg"

  require_file "$rendered_png" "rendered SVG icon"

  saturation_mean=$(
    "$image_convert" "$rendered_png" \
      -colorspace HSL \
      -channel G \
      -separate \
      -format '%[fx:mean]' \
      info:
  )
  if ! awk -v value="$saturation_mean" 'BEGIN { exit !(value >= 0.1) }'; then
    echo "Rendered icon has unexpectedly low color saturation: $svg ($saturation_mean)" >&2
    echo "Check that SVG_CONVERT supports the SVG gradients." >&2
    exit 1
  fi

  cp "$rendered_png" "$tmp_dir/icon_512x512@2x.png"
  create_icon_variant 16 icon_16x16.png
  create_icon_variant 32 icon_16x16@2x.png
  create_icon_variant 32 icon_32x32.png
  create_icon_variant 64 icon_32x32@2x.png
  create_icon_variant 128 icon_128x128.png
  create_icon_variant 256 icon_128x128@2x.png
  create_icon_variant 256 icon_256x256.png
  create_icon_variant 512 icon_256x256@2x.png
  create_icon_variant 512 icon_512x512.png

  iconutil -c icns "$tmp_dir" -o "$rendered_icns"
  if [ ! -s "$rendered_icns" ]; then
    echo "Could not create icon: $icns" >&2
    exit 1
  fi
  mv -f "$rendered_icns" "$icns"

  rm -rf "$tmp_dir" "$render_dir"
  tmp_dir=""
  render_dir=""
done
