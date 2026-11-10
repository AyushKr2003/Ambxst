#!/bin/bash

# Atoll: square thumbnails for the Wallpapers tab and the
# desktop, as upstream Ambxst's `ambxst thumbs` / `ambxst dthumbs` made them. Images
# go through ImageMagick and videos through ffmpeg (both Omarchy base
# packages). A thumbnail is only rebuilt when its source is newer.
#
#   thumbs.sh wall <wallpapers.json> <cache-base> [fallback-dir]
#       -> <cache-base>/thumbnails/<path relative to wallPath>.jpg  (140px)
#   thumbs.sh desktop <desktop-dir> <cache-dir>
#       -> <cache-dir>/<file name>.jpg                              (64px)

mode=${1:-}
media='.*\.(jpe?g|png|webp|gif|bmp|tiff?|mp4|webm|mov|avi|mkv)$'

thumb() {
  local src=$1 dest=$2 size=$3
  [[ -f $dest && ! $src -nt $dest ]] && return 0
  mkdir -p "$(dirname "$dest")"
  case ${src,,} in
    *.mp4 | *.webm | *.mov | *.avi | *.mkv)
      ffmpeg -loglevel error -y -ss 1 -i "$src" -frames:v 1 \
        -vf "scale=$size:$size:force_original_aspect_ratio=increase,crop=$size:$size" "$dest" ||
        ffmpeg -loglevel error -y -i "$src" -frames:v 1 \
          -vf "scale=$size:$size:force_original_aspect_ratio=increase,crop=$size:$size" "$dest"
      ;;
    *)
      magick "${src}[0]" -auto-orient -thumbnail "${size}x${size}^" -gravity center -extent "${size}x${size}" -quality 85 "$dest"
      ;;
  esac
}

case $mode in
  wall)
    config=$2
    base=$3
    fallback=${4:-}
    wall=$(jq -r '.wallPath // empty' "$config" 2>/dev/null)
    wall=${wall/#\~/$HOME}
    [[ -d $wall ]] || wall=$fallback
    [[ -d $wall ]] || { echo "Wallpaper directory not found: $wall" >&2; exit 1; }
    wall=$(realpath "$wall")

    find -L "$wall" -name '.*' -prune -o -type f -regextype posix-extended -iregex "$media" -print |
      while IFS= read -r file; do
        thumb "$file" "$base/thumbnails/${file#"$wall"/}.jpg" 140
      done
    ;;
  desktop)
    dir=$2
    cache=$3
    [[ -d $dir ]] || exit 0
    find -L "$dir" -maxdepth 1 -type f -regextype posix-extended -iregex "$media" -print |
      while IFS= read -r file; do
        thumb "$file" "$cache/$(basename "$file").jpg" 64
      done
    ;;
  *)
    echo "Usage: thumbs.sh <wall|desktop> ..." >&2
    exit 2
    ;;
esac
