#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
out="$root/Tests/Fixtures/Generated"
mkdir -p "$out"

ffmpeg=${FFMPEG:-ffmpeg}

"$ffmpeg" -v error -y -f lavfi -i "aevalsrc=if(eq(n\,0)\,1\,n/4096):s=48000:d=0.1" \
  -c:a pcm_s24le "$out/ramp-impulse-48k-stereo-24.wav"
"$ffmpeg" -v error -y -f lavfi -i "sine=frequency=997:sample_rate=44100:duration=0.25" \
  -c:a libmp3lame "$out/priming-44k-mono.mp3"
"$ffmpeg" -v error -y -f lavfi -i "sine=frequency=997:sample_rate=48000:duration=0.25" \
  -c:a aac "$out/priming-48k-mono.m4a"
"$ffmpeg" -v error -y -f lavfi -i "sine=frequency=997:sample_rate=48000:duration=0.05" \
  -c:a alac "$out/tone-48000-stereo-24-alac.m4a"

for rate in 44100 48000 96000 192000; do
  "$ffmpeg" -v error -y -f lavfi -i "sine=frequency=997:sample_rate=$rate:duration=0.05" \
    -c:a pcm_s16le "$out/tone-${rate}-mono-16.wav"
  "$ffmpeg" -v error -y -f lavfi -i "sine=frequency=997:sample_rate=$rate:duration=0.05" \
    -ac 2 -c:a flac -sample_fmt s32 "$out/tone-${rate}-stereo-24.flac"
  "$ffmpeg" -v error -y -f lavfi -i "sine=frequency=997:sample_rate=$rate:duration=0.05" \
    -ac 2 -c:a pcm_s24be "$out/tone-${rate}-stereo-24.aiff"
done

"$ffmpeg" -v error -y \
  -f lavfi -i "aevalsrc=if(eq(mod(n\\,480)\\,0)\\,0.8\\,0):s=48000:d=0.1" \
  -i "$root/Tests/Fixtures/artwork.ppm" \
  -map 0:a -map 1:v -c:a flac -c:v png -disposition:v attached_pic \
  -metadata title="Synthetic Seek Markers" -metadata artist="Songbird Tests" \
  -metadata album="Compatibility Suite" -metadata track="1" \
  "$out/metadata-artwork-seek.flac"

cp "$out/tone-44100-mono-16.wav" "$out/corrupt-truncated.wav"
truncate -s 31 "$out/corrupt-truncated.wav"
printf 'not an audio file\n' > "$out/corrupt-header.flac"

(cd "$out" && shasum -a 256 ./*) > "$root/Tests/Fixtures/SHA256SUMS"
