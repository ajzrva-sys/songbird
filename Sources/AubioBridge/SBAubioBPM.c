#include "SBAubioBPM.h"
#include "aubio/types.h"
#include "aubio/fvec.h"
#include "aubio/tempo/tempo.h"

int SBAubioDetectBPM(uint32_t sample_rate, const float *samples, uint32_t frame_count) {
    if (frame_count == 0 || sample_rate == 0 || samples == NULL) return 0;

    uint_t hop_size = 256;
    uint_t buf_size = hop_size * 4;  // 1024

    aubio_tempo_t *tempo = new_aubio_tempo("default", buf_size, hop_size, sample_rate);
    if (!tempo) return 0;

    fvec_t *input = new_fvec(hop_size);
    fvec_t *output = new_fvec(1);

    uint_t frames_processed = 0;
    smpl_t bpm = 0;

    while (frames_processed + hop_size <= frame_count) {
        for (uint_t i = 0; i < hop_size; i++) {
            fvec_set_sample(input, samples[frames_processed + i], i);
        }

        aubio_tempo_do(tempo, input, output);

        if (fvec_get_sample(output, 0) > 0) {
            bpm = aubio_tempo_get_bpm(tempo);
        }

        frames_processed += hop_size;
    }

    del_fvec(input);
    del_fvec(output);
    del_aubio_tempo(tempo);

    return (int)(bpm + 0.5f);
}
