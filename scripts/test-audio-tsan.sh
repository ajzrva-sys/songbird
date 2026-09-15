#!/bin/sh
set -eu

swift test --sanitize=thread \
  --filter 'AudioAtomicTests|AudioDiagnosticsPollerTests|NativeAudioBackendTests|PlaybackPreparationTests|PlaybackQueueShuffleTests'
