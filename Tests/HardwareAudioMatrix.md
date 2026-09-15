# Manual audio hardware matrix

Run this matrix before an audio-engine release. Record the exact macOS build,
device model/firmware, result, and any audible discontinuity.

| Scenario | Expected result | macOS | Device | Result |
|---|---|---|---|---|
| Built-in output, gapless album | Exact boundary; no click or silence | | | |
| Wired output connect/disconnect | Same track resumes near confirmed position | | | |
| Bluetooth connect/disconnect | Same track resumes; queue does not advance | | | |
| Bluetooth profile/sample-rate change | Engine rebuilds and resumes same track | | | |
| AirPlay receiver select from Songbird | Current track continues on the chosen receiver near the confirmed position | | | |
| AirPlay receiver switch while paused | Selection changes; playback remains paused and resumes on the chosen receiver | | | |
| AirPlay receiver disconnect | Songbird returns to System Output without advancing the queue or crashing | | | |
| AirPlay gapless album and crossfade | Transition remains deterministic; record receiver buffering latency or audible discontinuity | | | |
| Sleep/wake while using AirPlay | Same track safely resumes on the route or falls back visibly to System Output | | | |
| Sleep during ordinary playback | Wake resumes same track safely | | | |
| Sleep during crossfade | No crash; deterministic same-track recovery | | | |
| Live 44.1 ↔ 48/96 kHz device change | Pitch unchanged; same position resumes | | | |
| Rapid skip while device changes | Latest requested track wins | | | |
| Corrupt active track | Playback stops with track-specific error | | | |
| Corrupt pending track | Playback stops with track-specific error | | | |
