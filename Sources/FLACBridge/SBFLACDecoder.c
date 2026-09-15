#include "SBFLACDecoder.h"
#include <FLAC/stream_decoder.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

struct SBFLACDecoder {
    FLAC__StreamDecoder *decoder;
    float *block;
    size_t blockFrames;
    size_t blockOffset;
    uint32_t sampleRate;
    uint32_t channels;
    uint32_t bitsPerSample;
    uint64_t totalFrames;
    int atEnd;
    int failed;
    char **comments;
    size_t commentCount;
    uint8_t *artwork;
    size_t artworkSize;
};

static FLAC__StreamDecoderWriteStatus write_callback(
    const FLAC__StreamDecoder *decoder,
    const FLAC__Frame *frame,
    const FLAC__int32 *const channels[],
    void *clientData
) {
    (void)decoder;
    SBFLACDecoder *state = clientData;
    const size_t frames = frame->header.blocksize;
    float *resized = realloc(state->block, frames * 2 * sizeof(float));
    if (!resized) {
        state->failed = 1;
        return FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
    }
    state->block = resized;
    state->blockFrames = frames;
    state->blockOffset = 0;
    state->sampleRate = frame->header.sample_rate;
    state->channels = frame->header.channels;
    state->bitsPerSample = frame->header.bits_per_sample;

    const double scale = (double)(1ULL << (state->bitsPerSample - 1));
    for (size_t frameIndex = 0; frameIndex < frames; ++frameIndex) {
        float left = (float)((double)channels[0][frameIndex] / scale);
        float right = state->channels > 1
            ? (float)((double)channels[1][frameIndex] / scale)
            : left;
        state->block[frameIndex * 2] = left;
        state->block[frameIndex * 2 + 1] = right;
    }
    return FLAC__STREAM_DECODER_WRITE_STATUS_CONTINUE;
}

static void metadata_callback(
    const FLAC__StreamDecoder *decoder,
    const FLAC__StreamMetadata *metadata,
    void *clientData
) {
    (void)decoder;
    SBFLACDecoder *state = clientData;
    if (metadata->type == FLAC__METADATA_TYPE_STREAMINFO) {
        state->sampleRate = metadata->data.stream_info.sample_rate;
        state->channels = metadata->data.stream_info.channels;
        state->bitsPerSample = metadata->data.stream_info.bits_per_sample;
        state->totalFrames = metadata->data.stream_info.total_samples;
    } else if (metadata->type == FLAC__METADATA_TYPE_VORBIS_COMMENT) {
        const FLAC__StreamMetadata_VorbisComment *comments =
            &metadata->data.vorbis_comment;
        for (uint32_t index = 0; index < comments->num_comments; ++index) {
            const FLAC__StreamMetadata_VorbisComment_Entry *entry =
                &comments->comments[index];
            char *copy = malloc((size_t)entry->length + 1);
            if (!copy) {
                state->failed = 1;
                return;
            }
            char **resized = realloc(
                state->comments,
                (state->commentCount + 1) * sizeof(char *)
            );
            if (!resized) {
                free(copy);
                state->failed = 1;
                return;
            }
            state->comments = resized;
            memcpy(copy, entry->entry, entry->length);
            copy[entry->length] = '\0';
            state->comments[state->commentCount++] = copy;
        }
    } else if (metadata->type == FLAC__METADATA_TYPE_PICTURE &&
               state->artwork == NULL &&
               metadata->data.picture.data_length > 0) {
        state->artworkSize = metadata->data.picture.data_length;
        state->artwork = malloc(state->artworkSize);
        if (!state->artwork) {
            state->artworkSize = 0;
            state->failed = 1;
            return;
        }
        memcpy(state->artwork, metadata->data.picture.data, state->artworkSize);
    }
}

static void error_callback(
    const FLAC__StreamDecoder *decoder,
    FLAC__StreamDecoderErrorStatus status,
    void *clientData
) {
    (void)decoder;
    (void)status;
    ((SBFLACDecoder *)clientData)->failed = 1;
}

SBFLACDecoder *SBFLACOpen(const char *path) {
    SBFLACDecoder *state = calloc(1, sizeof(SBFLACDecoder));
    if (!state) return NULL;
    state->decoder = FLAC__stream_decoder_new();
    if (!state->decoder) {
        free(state);
        return NULL;
    }
    FLAC__stream_decoder_set_metadata_respond(
        state->decoder,
        FLAC__METADATA_TYPE_VORBIS_COMMENT
    );
    FLAC__stream_decoder_set_metadata_respond(
        state->decoder,
        FLAC__METADATA_TYPE_PICTURE
    );
    FLAC__StreamDecoderInitStatus status = FLAC__stream_decoder_init_file(
        state->decoder,
        path,
        write_callback,
        metadata_callback,
        error_callback,
        state
    );
    if (status != FLAC__STREAM_DECODER_INIT_STATUS_OK ||
        !FLAC__stream_decoder_process_until_end_of_metadata(state->decoder) ||
        state->channels == 0 || state->channels > 2) {
        SBFLACClose(state);
        return NULL;
    }
    return state;
}

void SBFLACClose(SBFLACDecoder *state) {
    if (!state) return;
    if (state->decoder) {
        FLAC__stream_decoder_finish(state->decoder);
        FLAC__stream_decoder_delete(state->decoder);
    }
    free(state->block);
    for (size_t index = 0; index < state->commentCount; ++index) {
        free(state->comments[index]);
    }
    free(state->comments);
    free(state->artwork);
    free(state);
}

uint32_t SBFLACSampleRate(const SBFLACDecoder *state) { return state ? state->sampleRate : 0; }
uint32_t SBFLACChannels(const SBFLACDecoder *state) { return state ? state->channels : 0; }
uint64_t SBFLACTotalFrames(const SBFLACDecoder *state) { return state ? state->totalFrames : 0; }
int SBFLACAtEnd(const SBFLACDecoder *state) { return state ? state->atEnd : 1; }

const char *SBFLACTag(const SBFLACDecoder *state, const char *key) {
    if (!state || !key) return NULL;
    const size_t keyLength = strlen(key);
    for (size_t index = 0; index < state->commentCount; ++index) {
        const char *comment = state->comments[index];
        if (strncasecmp(comment, key, keyLength) == 0 &&
            comment[keyLength] == '=') {
            return comment + keyLength + 1;
        }
    }
    return NULL;
}

const uint8_t *SBFLACArtwork(const SBFLACDecoder *state, size_t *size) {
    if (size) *size = state ? state->artworkSize : 0;
    return state ? state->artwork : NULL;
}

int SBFLACSeek(SBFLACDecoder *state, uint64_t frame) {
    if (!state) return 0;
    state->blockFrames = 0;
    state->blockOffset = 0;
    state->atEnd = 0;
    state->failed = 0;
    return FLAC__stream_decoder_seek_absolute(state->decoder, frame) ? 1 : 0;
}

size_t SBFLACReadStereoFloat(
    SBFLACDecoder *state,
    float *output,
    size_t maximumFrames
) {
    if (!state || !output || state->failed || maximumFrames == 0) return 0;
    size_t copied = 0;
    while (copied < maximumFrames) {
        if (state->blockOffset < state->blockFrames) {
            size_t available = state->blockFrames - state->blockOffset;
            size_t count = available < (maximumFrames - copied)
                ? available : (maximumFrames - copied);
            memcpy(
                output + copied * 2,
                state->block + state->blockOffset * 2,
                count * 2 * sizeof(float)
            );
            state->blockOffset += count;
            copied += count;
            continue;
        }
        state->blockFrames = 0;
        state->blockOffset = 0;
        FLAC__StreamDecoderState decoderState =
            FLAC__stream_decoder_get_state(state->decoder);
        if (decoderState == FLAC__STREAM_DECODER_END_OF_STREAM) {
            state->atEnd = 1;
            break;
        }
        if (!FLAC__stream_decoder_process_single(state->decoder)) {
            state->failed = 1;
            break;
        }
    }
    return copied;
}
