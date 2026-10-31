#include "CMediaFoundation.h"

#ifdef _WIN32

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mfreadwrite.h>

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <numeric>
#include <vector>

namespace {

constexpr double kPi = 3.14159265358979323846;
constexpr DWORD kAudio = (DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM;

template <class T> struct Com {
    T *p = nullptr;
    Com() = default;
    Com(const Com &) = delete;
    ~Com() { if (p) p->Release(); }
    T **operator&() { return &p; }
    T *operator->() const { return p; }
};

/// COM and Media Foundation for the length of one call. A caller already in a single-threaded
/// apartment keeps it (RPC_E_CHANGED_MODE); Media Foundation works there too.
struct Session {
    HRESULT hr;
    bool co;
    Session() {
        co = SUCCEEDED(CoInitializeEx(nullptr, COINIT_MULTITHREADED));
        hr = MFStartup(MF_VERSION, MFSTARTUP_LITE);
    }
    ~Session() {
        if (SUCCEEDED(hr)) MFShutdown();
        if (co) CoUninitialize();
    }
};

HRESULT open(const uint16_t *path, IMFSourceReader **reader) {
    return MFCreateSourceReaderFromURL(reinterpret_cast<LPCWSTR>(path), nullptr, reader);
}

/// Asks for 32-bit float at the track's own rate and channel count, and reports both.
HRESULT configure(IMFSourceReader *reader, UINT32 *channels, UINT32 *rate) {
    Com<IMFMediaType> want;
    HRESULT hr = MFCreateMediaType(&want);
    if (FAILED(hr)) return hr;
    want->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
    want->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_Float);
    hr = reader->SetCurrentMediaType(kAudio, nullptr, want.p);
    if (FAILED(hr)) return hr;
    Com<IMFMediaType> got;
    hr = reader->GetCurrentMediaType(kAudio, &got);
    if (FAILED(hr)) return hr;
    *channels = MFGetAttributeUINT32(got.p, MF_MT_AUDIO_NUM_CHANNELS, 0);
    *rate = MFGetAttributeUINT32(got.p, MF_MT_AUDIO_SAMPLES_PER_SECOND, 0);
    return (*channels && *rate) ? S_OK : MF_E_INVALIDMEDIATYPE;
}

/// Windowed-sinc resampling, polyphase: the kernel for each of the `up` phases is computed once.
/// The cutoff sits at the lower Nyquist so downsampling does not alias into speech.
std::vector<float> resample(const std::vector<float> &in, uint32_t from, uint32_t to) {
    if (from == to || in.empty()) return in;
    const uint32_t g = std::gcd(from, to);
    const uint64_t up = to / g, down = from / g;
    const double cutoff = std::min(1.0, double(to) / double(from));
    const int zeros = 16;
    const int radius = int(std::ceil(zeros / cutoff));
    const int taps = 2 * radius + 1;

    std::vector<float> kernels(size_t(up) * taps);
    for (uint64_t p = 0; p < up; p++) {
        const double frac = double(p) / double(up);
        double sum = 0;
        for (int t = 0; t < taps; t++) {
            const double d = double(t - radius) - frac;
            const double x = d * cutoff;
            const double sinc = x == 0 ? 1 : std::sin(kPi * x) / (kPi * x);
            const double window = std::abs(d) >= radius ? 0 : 0.5 * (1 + std::cos(kPi * d / radius));
            kernels[p * taps + t] = float(sinc * window);
            sum += sinc * window;
        }
        // Unity gain at DC for every phase.
        for (int t = 0; t < taps; t++) kernels[p * taps + t] = float(kernels[p * taps + t] / sum);
    }

    const uint64_t n = uint64_t(in.size()) * up / down;
    std::vector<float> out(n);
    const int64_t size = int64_t(in.size());
    for (uint64_t i = 0; i < n; i++) {
        const uint64_t pos = i * down;
        const int64_t base = int64_t(pos / up);
        const float *k = &kernels[(pos % up) * taps];
        float acc = 0;
        const int64_t lo = base - radius;
        for (int t = 0; t < taps; t++) {
            const int64_t j = lo + t;
            if (j >= 0 && j < size) acc += in[size_t(j)] * k[t];
        }
        out[i] = acc;
    }
    return out;
}

} // namespace

extern "C" int32_t mf_probe(const uint16_t *path, MFMediaInfo *info) {
    *info = MFMediaInfo{0, 0, 0};
    Session session;
    if (FAILED(session.hr)) return session.hr;
    Com<IMFSourceReader> reader;
    HRESULT hr = open(path, &reader);
    if (FAILED(hr)) return hr;

    PROPVARIANT value;
    PropVariantInit(&value);
    if (SUCCEEDED(reader->GetPresentationAttribute((DWORD)MF_SOURCE_READER_MEDIASOURCE, MF_PD_DURATION, &value))) {
        if (value.vt == VT_UI8) info->duration = double(value.uhVal.QuadPart) / 1e7;
        PropVariantClear(&value);
    }
    Com<IMFMediaType> audio, video;
    info->hasAudio = SUCCEEDED(reader->GetNativeMediaType(kAudio, 0, &audio));
    info->hasVideo = SUCCEEDED(reader->GetNativeMediaType((DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, &video));
    return 0;
}

extern "C" int32_t mf_decode_mono(const uint16_t *path, double sampleRate, double start, double end,
                                  float **samples, size_t *count) {
    *samples = nullptr;
    *count = 0;
    Session session;
    if (FAILED(session.hr)) return session.hr;
    Com<IMFSourceReader> reader;
    HRESULT hr = open(path, &reader);
    if (FAILED(hr)) return hr;

    reader->SetStreamSelection((DWORD)MF_SOURCE_READER_ALL_STREAMS, FALSE);
    hr = reader->SetStreamSelection(kAudio, TRUE);
    if (FAILED(hr)) return hr;
    UINT32 channels = 0, rate = 0;
    hr = configure(reader.p, &channels, &rate);
    if (FAILED(hr)) return hr;

    if (start > 0) {
        PROPVARIANT position;
        PropVariantInit(&position);
        position.vt = VT_I8;
        position.hVal.QuadPart = LONGLONG(start * 1e7);
        reader->SetCurrentPosition(GUID_NULL, position);
    }

    std::vector<float> mono;
    double first = -1; // time of the first decoded frame: seeking lands on or before `start`
    for (;;) {
        DWORD flags = 0;
        LONGLONG time = 0;
        Com<IMFSample> sample;
        hr = reader->ReadSample(kAudio, 0, nullptr, &flags, &time, &sample);
        if (FAILED(hr)) return hr;
        if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
        if (flags & MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED) {
            UINT32 c = 0, r = 0;
            hr = configure(reader.p, &c, &r);
            if (FAILED(hr)) return hr;
            // Mono is resampled once at the end, so a rate change mid-file cannot be honoured.
            if (r != rate) return MF_E_INVALIDMEDIATYPE;
            channels = c;
        }
        if (!sample.p) continue;
        if (first < 0) first = double(time) / 1e7;
        if (end > 0 && double(time) / 1e7 >= end) break;

        Com<IMFMediaBuffer> buffer;
        hr = sample->ConvertToContiguousBuffer(&buffer);
        if (FAILED(hr)) return hr;
        BYTE *data = nullptr;
        DWORD length = 0;
        hr = buffer->Lock(&data, nullptr, &length);
        if (FAILED(hr)) return hr;
        const float *f = reinterpret_cast<const float *>(data);
        const size_t frames = length / (sizeof(float) * channels);
        const size_t at = mono.size();
        mono.resize(at + frames);
        for (size_t i = 0; i < frames; i++) {
            float sum = 0;
            for (UINT32 c = 0; c < channels; c++) sum += f[i * channels + c];
            mono[at + i] = sum / float(channels);
        }
        buffer->Unlock();
    }

    if (start > 0 && first >= 0 && start > first) {
        const size_t skip = std::min(mono.size(), size_t((start - first) * rate));
        mono.erase(mono.begin(), mono.begin() + skip);
    }
    if (end > 0) {
        const double from = start > 0 ? start : 0;
        const size_t keep = size_t(std::max(0.0, end - from) * rate);
        if (mono.size() > keep) mono.resize(keep);
    }

    std::vector<float> out = resample(mono, rate, uint32_t(sampleRate));
    if (out.empty()) return 0;
    float *buffer = static_cast<float *>(std::malloc(out.size() * sizeof(float)));
    if (!buffer) return E_OUTOFMEMORY;
    std::memcpy(buffer, out.data(), out.size() * sizeof(float));
    *samples = buffer;
    *count = out.size();
    return 0;
}

extern "C" void mf_free(float *samples) { std::free(samples); }

#endif
