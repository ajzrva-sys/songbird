#ifndef SBAubioBPM_h
#define SBAubioBPM_h

#include <stdint.h>

/// Detect BPM from audio samples using aubio tempo detection.
/// @param sample_rate Audio sample rate (e.g., 44100)
/// @param samples Float audio samples (mono)
/// @param frame_count Number of frames
/// @return Detected BPM (e.g., 120), or 0 on failure
int SBAubioDetectBPM(uint32_t sample_rate, const float *samples, uint32_t frame_count);

#endif
