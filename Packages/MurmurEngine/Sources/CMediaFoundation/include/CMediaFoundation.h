#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    double duration;
    int32_t hasAudio;
    int32_t hasVideo;
} MFMediaInfo;

/// Duration and track kinds of a media file. Returns 0 or a failing HRESULT. `path` is UTF-16.
int32_t mf_probe(const uint16_t *path, MFMediaInfo *info);

/// The first audio track mixed to mono and resampled to `sampleRate`, between `start` and `end`
/// seconds (pass negative values for the whole file). On success `*samples` holds `*count` floats
/// to release with `mf_free`. Returns 0 or a failing HRESULT.
int32_t mf_decode_mono(const uint16_t *path, double sampleRate, double start, double end,
                       float **samples, size_t *count);

void mf_free(float *samples);

#ifdef __cplusplus
}
#endif
