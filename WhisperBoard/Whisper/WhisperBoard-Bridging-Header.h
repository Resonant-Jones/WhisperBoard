//
//  WhisperBoard-Bridging-Header.h
//  WhisperBoard
//
//  Bridging header for whisper.cpp C++ integration
//  This header exposes whisper.cpp C/C++ functions to Swift
//
//  Usage:
//  1. Add whisper.cpp source files to Xcode project under WhisperBoard/Whisper/whisper-src/
//  2. Set this file as "Objective-C Bridging Header" in Build Settings
//  3. Link against Accelerate, Metal, and MetalKit frameworks
//

#ifndef WhisperBoard_Bridging_Header_h
#define WhisperBoard_Bridging_Header_h

// When whisper.cpp is properly integrated, uncomment this line:
// #import "whisper-src/whisper.h"

// Until then, we need to declare the essential whisper.cpp C API functions
// that Swift will call. These declarations match whisper.cpp's actual API.

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stdbool.h>

// Opaque types
struct whisper_context;
struct whisper_state;

// Sampling strategies
enum whisper_sampling_strategy {
    WHISPER_SAMPLING_GREEDY,      // Greedy sampling (fastest)
    WHISPER_SAMPLING_BEAM_SEARCH, // Beam search (more accurate)
};

// Alignment parameters
enum whisper_alignment_heads_preset {
    WHISPER_AHEADS_NONE,
    WHISPER_AHEADS_N_TOP_MOST,
    WHISPER_AHEADS_CUSTOM,
    WHISPER_AHEADS_TINY_EN,
    WHISPER_AHEADS_TINY,
    WHISPER_AHEADS_BASE_EN,
    WHISPER_AHEADS_BASE,
    WHISPER_AHEADS_SMALL_EN,
    WHISPER_AHEADS_SMALL,
    WHISPER_AHEADS_MEDIUM_EN,
    WHISPER_AHEADS_MEDIUM,
    WHISPER_AHEADS_LARGE_V1,
    WHISPER_AHEADS_LARGE_V2,
    WHISPER_AHEADS_LARGE_V3,
};

// Full parameters struct
struct whisper_full_params {
    enum whisper_sampling_strategy strategy;

    int n_threads;
    int n_max_text_ctx;
    int offset_ms;
    int duration_ms;

    bool translate;
    bool no_context;
    bool no_timestamps;
    bool single_segment;
    bool print_special;
    bool print_progress;
    bool print_realtime;
    bool print_timestamps;

    bool token_timestamps;
    float thold_pt;
    float thold_ptsum;
    int max_len;
    bool split_on_word;
    int max_tokens;

    bool speed_up;
    bool debug_mode;
    int audio_ctx;

    bool tdrz_enable;

    bool suppress_blank;
    bool suppress_non_speech_tokens;

    float temperature;
    float max_initial_ts;
    float length_penalty;

    float temperature_inc;
    float entropy_thold;
    float logprob_thold;
    float no_speech_thold;

    struct {
        int n_past;
    } greedy;

    struct {
        int beam_size;
        float patience;
    } beam_search;

    const char * language;
    bool detect_language;

    const char * prompt;
    int prompt_n_tokens;

    int n_processors;
};

// Context management
struct whisper_context * whisper_init_from_file_with_params(const char * path_model, struct whisper_context_params params);
struct whisper_context * whisper_init_from_file(const char * path_model);
void whisper_free(struct whisper_context * ctx);
void whisper_free_state(struct whisper_state * state);

// Context parameters
struct whisper_context_params {
    bool use_gpu;
    int  gpu_device;
    bool flash_attn;

    // Metal-specific
    void * metal_context;
};

struct whisper_context_params whisper_context_default_params(void);

// Get default parameters
struct whisper_full_params whisper_full_default_params(enum whisper_sampling_strategy strategy);

// Convert RAW PCM audio to log mel spectrogram
int whisper_pcm_to_mel(
    struct whisper_context * ctx,
    const float * samples,
    int n_samples,
    int n_threads
);

int whisper_pcm_to_mel_with_state(
    struct whisper_context * ctx,
    struct whisper_state * state,
    const float * samples,
    int n_samples,
    int n_threads
);

// Run inference
int whisper_full(
    struct whisper_context * ctx,
    struct whisper_full_params params,
    const float * samples,
    int n_samples
);

int whisper_full_with_state(
    struct whisper_context * ctx,
    struct whisper_state * state,
    struct whisper_full_params params,
    const float * samples,
    int n_samples
);

// Get results
int whisper_full_n_segments(struct whisper_context * ctx);
int whisper_full_n_segments_from_state(struct whisper_state * state);

int64_t whisper_full_get_segment_t0(struct whisper_context * ctx, int i_segment);
int64_t whisper_full_get_segment_t1(struct whisper_context * ctx, int i_segment);
int64_t whisper_full_get_segment_t0_from_state(struct whisper_state * state, int i_segment);
int64_t whisper_full_get_segment_t1_from_state(struct whisper_state * state, int i_segment);

const char * whisper_full_get_segment_text(struct whisper_context * ctx, int i_segment);
const char * whisper_full_get_segment_text_from_state(struct whisper_state * state, int i_segment);

int whisper_full_n_tokens(struct whisper_context * ctx, int i_segment);
int whisper_full_n_tokens_from_state(struct whisper_state * state, int i_segment);

const char * whisper_full_get_token_text(struct whisper_context * ctx, int i_segment, int i_token);
int32_t whisper_full_get_token_id(struct whisper_context * ctx, int i_segment, int i_token);
const char * whisper_full_get_token_text_from_state(struct whisper_context * ctx, struct whisper_state * state, int i_segment, int i_token);
int32_t whisper_full_get_token_id_from_state(struct whisper_state * state, int i_segment, int i_token);

float whisper_full_get_token_p(struct whisper_context * ctx, int i_segment, int i_token);
float whisper_full_get_token_p_from_state(struct whisper_state * state, int i_segment, int i_token);

// Language detection
int whisper_full_lang_id(struct whisper_context * ctx);
int whisper_full_lang_id_from_state(struct whisper_state * state);

// Performance
void whisper_print_timings(struct whisper_context * ctx);
void whisper_reset_timings(struct whisper_context * ctx);

// System info
const char * whisper_print_system_info(void);

// Model info
int whisper_model_n_vocab(struct whisper_context * ctx);
int whisper_model_n_audio_ctx(struct whisper_context * ctx);
int whisper_model_n_audio_state(struct whisper_context * ctx);
int whisper_model_n_audio_head(struct whisper_context * ctx);
int whisper_model_n_audio_layer(struct whisper_context * ctx);
int whisper_model_n_text_ctx(struct whisper_context * ctx);
int whisper_model_n_text_state(struct whisper_context * ctx);
int whisper_model_n_text_head(struct whisper_context * ctx);
int whisper_model_n_text_layer(struct whisper_context * ctx);
int whisper_model_n_mels(struct whisper_context * ctx);
int whisper_model_ftype(struct whisper_context * ctx);
int whisper_model_type(struct whisper_context * ctx);

// Token utilities
int whisper_token_eot(struct whisper_context * ctx);
int whisper_token_sot(struct whisper_context * ctx);
int whisper_token_solm(struct whisper_context * ctx);
int whisper_token_prev(struct whisper_context * ctx);
int whisper_token_nosp(struct whisper_context * ctx);
int whisper_token_not(struct whisper_context * ctx);
int whisper_token_beg(struct whisper_context * ctx);
int whisper_token_lang(struct whisper_context * ctx, int lang_id);

const char * whisper_token_to_str(struct whisper_context * ctx, int token);

#ifdef __cplusplus
}
#endif

#endif /* WhisperBoard_Bridging_Header_h */
