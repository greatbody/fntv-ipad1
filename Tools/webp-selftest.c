#include <webp/decode.h>
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc != 3) { fprintf(stderr, "Usage: webp-selftest fixture.webp expected-hex-checksum\n"); return 2; }
    FILE *file = fopen(argv[1], "rb");
    if (!file) { perror("fixture"); return 3; }
    assert(fseek(file, 0, SEEK_END) == 0);
    long length = ftell(file);
    assert(length > 0 && length < 65536);
    rewind(file);
    uint8_t *bytes = malloc((size_t)length);
    assert(bytes && fread(bytes, 1, (size_t)length, file) == (size_t)length);
    fclose(file);
    WebPDecoderConfig config;
    assert(WebPInitDecoderConfig(&config));
    assert(WebPGetFeatures(bytes, (size_t)length, &config.input) == VP8_STATUS_OK);
    assert(config.input.width == 64 && config.input.height == 96);
    config.options.use_scaling = 1;
    config.options.scaled_width = 32;
    config.options.scaled_height = 48;
    config.output.colorspace = MODE_RGBA;
    assert(WebPDecode(bytes, (size_t)length, &config) == VP8_STATUS_OK);
    assert(config.output.width == 32 && config.output.height == 48);
    assert(config.output.u.RGBA.stride >= 32 * 4);
    uint32_t checksum = 2166136261U;
    for (int y = 0; y < 48; y++) {
        const uint8_t *row = config.output.u.RGBA.rgba + y * config.output.u.RGBA.stride;
        for (int x = 0; x < 128; x++) checksum = (checksum ^ row[x]) * 16777619U;
    }
    char *end = NULL;
    unsigned long expected = strtoul(argv[2], &end, 16);
    assert(end != argv[2] && *end == 0 && expected <= UINT32_MAX && checksum == expected);
    WebPFreeDecBuffer(&config.output);
    assert(WebPInitDecoderConfig(&config));
    assert(WebPDecode(bytes, 8, &config) != VP8_STATUS_OK);
    WebPFreeDecBuffer(&config.output);
    free(bytes);
    printf("PASS libwebp=%06x source=64x96 scaled=32x48 RGBA checksum=%08x; truncated input rejected\n", WebPGetDecoderVersion(), checksum);
    return 0;
}
