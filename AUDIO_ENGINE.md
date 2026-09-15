# Native audio engine

Songbird decodes local MP3, AAC/M4A, ALAC, WAV, AIFF, and FLAC files into
stereo Float32 PCM at the output-device sample rate. Decoder workers publish
PCM through bounded single-producer/single-consumer ring buffers. FLAC uses the
standalone libFLAC bridge; the other guaranteed formats use AVFoundation/Core
Audio decoders.

The `AVAudioSourceNode` callback delegates to `RenderKernel`. Control changes
are immutable `RenderSnapshot` values transferred through a fixed-capacity C11
atomic queue. The renderer owns only raw retained handles and a render-local
cursor. Retired handles and playback events return through another SPSC queue;
the main control thread receives returned handles, updates ownership, and sends
callbacks/error reports. Retired streams are handed to a cleanup worker for decoder
stop and final destruction. Handles stay open until any in-flight read finishes.

The renderer performs no allocation, locking, logging, file access, collection
mutation, user callbacks, or Swift object destruction. Ring-buffer positions
are monotonic 64-bit atomic sample counters, with modulo used only to address
fixed storage.

## Responsive preparation

Normal Play/Next, resume-from-position, seeking, and file preloading open, seek,
and prime their sources on a background worker. A single-use prepared source owns
the stream until the control actor accepts it. The engine checks request generations
before committing playback or queue changes; Stop, Pause, or newer playback intents
invalidate older work. Failed preparation leaves the current track playing.
Unused results are disposed of off-main. A changed output sample rate rejects the
prepared stream instead of rendering it with an incompatible format.

The synchronous backend compatibility API and output-device recovery still prepare
synchronously. Core Audio engine configuration/start remain on the control actor.
This is not a claim that every possible source of UI or hardware latency is removed.

## Transitions

- Gapless playback changes streams on the frame immediately following EOF.
- Crossfades start on an exact output frame and use equal-power gains.
- A crossfade longer than either track is clamped to half the shorter track.
- A pending decoder failure stops playback and reports the affected filename.

## Lifecycle recovery

Output configuration changes and sleep/wake pause playback, retain the last
confirmed source position, rebuild the engine and converter, seek and refill,
then resume the same track without advancing the queue. The device coordinator
is injectable so lifecycle sequences can be simulated independently of
hardware. Device lifecycle events have a main-actor Sendable callback contract,
and observer teardown remains isolated to the coordinator.

## Verification

Run ordinary tests with `swift test`. Run the audio concurrency subset under
Thread Sanitizer with:

```sh
./scripts/test-audio-tsan.sh
```

Release candidates must have no Thread Sanitizer findings and must complete
the matrix in `Tests/HardwareAudioMatrix.md`.

## Diagnostics

The Audio Diagnostics Settings tab polls numeric C11 atomic publications four
times per second while visible. Render and decoder threads never log or call
the UI. Metrics cover buffer depth, output and underflow frames, discarded PCM,
device rate, transition progress, and decode/conversion latency. Cumulative
values last for the app session and can be reset without interrupting audio.
AVAudioConverter input timing and failure publication share a stack-scoped
locked value state on the decoder worker. That lock is never used by the
real-time render callback and is not held during source reads.
