#include <stddef.h>
#include <stdint.h>

typedef struct SBFLACDecoder SBFLACDecoder;

SBFLACDecoder *SBFLACOpen(const char *path);
void SBFLACClose(SBFLACDecoder *decoder);
uint32_t SBFLACSampleRate(const SBFLACDecoder *decoder);
uint32_t SBFLACChannels(const SBFLACDecoder *decoder);
uint64_t SBFLACTotalFrames(const SBFLACDecoder *decoder);
int SBFLACSeek(SBFLACDecoder *decoder, uint64_t frame);
size_t SBFLACReadStereoFloat(
    SBFLACDecoder *decoder,
    float *output,
    size_t maximumFrames
);
int SBFLACAtEnd(const SBFLACDecoder *decoder);
const char *SBFLACTag(const SBFLACDecoder *decoder, const char *key);
const uint8_t *SBFLACArtwork(const SBFLACDecoder *decoder, size_t *size);

/// Write Vorbis comment tags to a FLAC file. Returns 0 on success, -1 on error.
/// `keys` and `values` are parallel arrays of length `count`.
int SBFLACWriteTags(
    const char *path,
    const char *const *keys,
    const char *const *values,
    size_t count
);

/// Write front-cover artwork to a FLAC file. Returns 0 on success, -1 on error.
/// `mime_type` should be "image/jpeg" or "image/png".
int SBFLACWriteArtwork(
    const char *path,
    const uint8_t *data,
    size_t data_length,
    const char *mime_type
);
