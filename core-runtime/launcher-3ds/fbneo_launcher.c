#include <3ds.h>
#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "libretro.h"

extern void retro_init(void);
extern void retro_deinit(void);
extern void retro_set_environment(retro_environment_t);
extern void retro_set_video_refresh(retro_video_refresh_t);
extern void retro_set_audio_sample(retro_audio_sample_t);
extern void retro_set_audio_sample_batch(retro_audio_sample_batch_t);
extern void retro_set_input_poll(retro_input_poll_t);
extern void retro_set_input_state(retro_input_state_t);
extern bool retro_load_game(const struct retro_game_info *);
extern void retro_unload_game(void);
extern void retro_run(void);
extern void retro_reset(void);
extern size_t retro_get_memory_size(unsigned);
extern void *retro_get_memory_data(unsigned);

static volatile u32 g_keys;
static unsigned g_width = 320;
static unsigned g_height = 240;
static unsigned g_pitch = 320 * sizeof(u16);
static u16 g_frame[400 * 240];

#define AUDIO_FRAMES 1024
#define AUDIO_BUFFERS 3
static s16 *g_audio;
static ndspWaveBuf g_wave[AUDIO_BUFFERS];
static unsigned g_audio_write;

static size_t audio_sample_batch(const s16 *data, size_t frames);

static void log_line(const char *message)
{
    FILE *file = fopen("sdmc:/vcoven/fbneo.log", "ab");
    if (!file)
        return;
    fputs(message, file);
    fputc('\n', file);
    fclose(file);
}

static bool environment(unsigned command, void *data)
{
    static const char *system_dir = "sdmc:/vcoven/system";
    static const char *save_dir = "sdmc:/vcoven/saves";
    static const struct retro_log_callback log_callback = {0};

    switch (command)
    {
    case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
        return data && (*(enum retro_pixel_format *)data == RETRO_PIXEL_FORMAT_RGB565 ||
                        *(enum retro_pixel_format *)data == RETRO_PIXEL_FORMAT_0RGB1555);
    case RETRO_ENVIRONMENT_SET_GEOMETRY:
        if (data)
        {
            const struct retro_game_geometry *geometry = data;
            g_width = geometry->base_width > 400 ? 400 : geometry->base_width;
            g_height = geometry->base_height > 240 ? 240 : geometry->base_height;
            g_pitch = g_width * sizeof(u16);
        }
        return true;
    case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
        if (data) { *(const char **)data = system_dir; return true; }
        return false;
    case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
        if (data) { *(const char **)data = save_dir; return true; }
        return false;
    case RETRO_ENVIRONMENT_GET_VARIABLE:
        if (data)
        {
            struct retro_variable *variable = data;
            variable->value = NULL;
        }
        return false;
    case RETRO_ENVIRONMENT_SET_VARIABLES:
        return true;
    case RETRO_ENVIRONMENT_GET_CAN_DUPE:
        if (data) { *(bool *)data = true; return true; }
        return false;
    case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
        if (data) { *(struct retro_log_callback *)data = log_callback; return false; }
        return false;
    case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
    case RETRO_ENVIRONMENT_SET_PERFORMANCE_LEVEL:
    case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME:
    case RETRO_ENVIRONMENT_SET_MESSAGE:
        return true;
    default:
        return false;
    }
}

static void video_refresh(const void *data, unsigned width, unsigned height, size_t pitch)
{
    if (!data || width == 0 || height == 0)
        return;

    const u16 *source = data;
    u16 *framebuffer = (u16 *)gfxGetFramebuffer(GFX_TOP, GFX_LEFT, NULL, NULL);
    unsigned draw_width = width > 400 ? 400 : width;
    unsigned draw_height = height > 240 ? 240 : height;
    for (unsigned y = 0; y < draw_height; ++y)
    {
        const u16 *row = (const u16 *)((const u8 *)source + y * pitch);
        for (unsigned x = 0; x < draw_width; ++x)
            g_frame[x * 240 + (239 - y)] = row[x];
    }
    if (framebuffer)
        memcpy(framebuffer, g_frame, sizeof(g_frame));
}

static void audio_sample(s16 left, s16 right)
{
    s16 sample[2] = {left, right};
    (void)audio_sample_batch(sample, 1);
}

static size_t audio_sample_batch(const s16 *data, size_t frames)
{
    if (!data)
        return 0;
    if (frames > AUDIO_FRAMES)
        frames = AUDIO_FRAMES;
    unsigned index = g_audio_write++ % AUDIO_BUFFERS;
    if (!g_audio || g_wave[index].status)
        return 0;
    s16 *buffer = g_audio + index * AUDIO_FRAMES * 2;
    memcpy(buffer, data, frames * sizeof(s16) * 2);
    DSP_FlushDataCache(buffer, frames * sizeof(s16) * 2);
    if (!g_wave[index].status)
    {
        memset(&g_wave[index], 0, sizeof(g_wave[index]));
        g_wave[index].data_vaddr = buffer;
        g_wave[index].nsamples = (u32)frames;
        ndspChnWaveBufAdd(0, &g_wave[index]);
    }
    return frames;
}

static void input_poll(void)
{
    hidScanInput();
    g_keys = hidKeysHeld();
}

static int16_t input_state(unsigned port, unsigned device, unsigned index, unsigned id)
{
    if (port != 0 || device != RETRO_DEVICE_JOYPAD || index != 0)
        return 0;
    const u32 mapping[] = {KEY_B, KEY_Y, KEY_SELECT, KEY_START, KEY_UP, KEY_DOWN,
                           KEY_LEFT, KEY_RIGHT, KEY_A, KEY_X, KEY_L, KEY_R};
    return id < sizeof(mapping) / sizeof(mapping[0]) && (g_keys & mapping[id]) ? 1 : 0;
}

static bool load_rom_path(char *path, size_t capacity)
{
    DIR *directory = opendir("romfs:/content");
    if (!directory)
        return false;
    struct dirent *entry;
    while ((entry = readdir(directory)) != NULL)
    {
        if (entry->d_name[0] == '.' || strlen(entry->d_name) + 17 >= capacity)
            continue;
        snprintf(path, capacity, "romfs:/content/%s", entry->d_name);
        closedir(directory);
        return true;
    }
    closedir(directory);
    return false;
}

static void mkdirs(void)
{
    mkdir("sdmc:/vcoven", 0777);
    mkdir("sdmc:/vcoven/system", 0777);
    mkdir("sdmc:/vcoven/saves", 0777);
}

static void save_ram(const char *rom_path)
{
    size_t size = retro_get_memory_size(RETRO_MEMORY_SAVE_RAM);
    void *data = retro_get_memory_data(RETRO_MEMORY_SAVE_RAM);
    if (!size || !data)
        return;
    const char *name = strrchr(rom_path, '/');
    name = name ? name + 1 : rom_path;
    char save_path[256];
    snprintf(save_path, sizeof(save_path), "sdmc:/vcoven/saves/%s.sav", name);
    FILE *file = fopen(save_path, "wb");
    if (file) { fwrite(data, 1, size, file); fclose(file); }
}

int main(void)
{
    gfxInitDefault();
    romfsInit();
    ndspInit();
    g_audio = (s16 *)linearAlloc(AUDIO_BUFFERS * AUDIO_FRAMES * 2 * sizeof(s16));
    if (!g_audio)
    {
        ndspExit();
        romfsExit();
        gfxExit();
        return 1;
    }
    memset(g_audio, 0, AUDIO_BUFFERS * AUDIO_FRAMES * 2 * sizeof(s16));
    mkdirs();
    log_line("vcoven FBNeo launcher start");

    ndspChnSetInterp(0, NDSP_INTERP_LINEAR);
    ndspChnSetRate(0, 44100.0f);
    ndspChnSetFormat(0, NDSP_FORMAT_STEREO_PCM16);
    memset(g_wave, 0, sizeof(g_wave));

    retro_set_environment(environment);
    retro_set_video_refresh(video_refresh);
    retro_set_audio_sample(audio_sample);
    retro_set_audio_sample_batch(audio_sample_batch);
    retro_set_input_poll(input_poll);
    retro_set_input_state(input_state);
    retro_init();

    char rom_path[256] = {0};
    struct retro_game_info game = {0};
    if (!load_rom_path(rom_path, sizeof(rom_path)))
        log_line("romfs:/content is empty");
    game.path = rom_path;
    if (!retro_load_game(&game))
    {
        log_line("retro_load_game failed");
        retro_deinit();
        linearFree(g_audio);
        ndspExit();
        romfsExit();
        gfxExit();
        return 1;
    }

    while (aptMainLoop())
    {
        hidScanInput();
        g_keys = hidKeysHeld();
        if ((g_keys & KEY_START) && (g_keys & KEY_SELECT))
            break;
        retro_run();
        gfxFlushBuffers();
        gfxSwapBuffers();
        gspWaitForVBlank();
    }

    save_ram(rom_path);
    retro_unload_game();
    retro_deinit();
    linearFree(g_audio);
    ndspExit();
    romfsExit();
    gfxExit();
    return 0;
}
