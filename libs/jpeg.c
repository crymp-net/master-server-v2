#include <lua.h>
#include <lauxlib.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <jpeglib.h>
#include <setjmp.h>

// Dummy typedef for the framework's serve_params to make the code compilable
typedef struct serve_params serve_params;
#ifndef LIB_EXPORT
#define LIB_EXPORT
#endif

// libjpeg error handling boilerplate to prevent exit() on corrupt images
struct my_error_mgr {
    struct jpeg_error_mgr pub;
    jmp_buf setjmp_buffer;
};

typedef struct my_error_mgr * my_error_ptr;

static void my_error_exit(j_common_ptr cinfo) {
    my_error_ptr myerr = (my_error_ptr) cinfo->err;
    longjmp(myerr->setjmp_buffer, 1);
}

// function jpeg.resize(source_bytes, target_px_area)
static int l_jpeg_resize(lua_State *L) {
    // 1. Validate Arguments
    if(lua_gettop(L) != 2 || lua_type(L, 1) != LUA_TSTRING || lua_type(L, 2) != LUA_TNUMBER) {
        return luaL_error(L, "expecting 2 arguments: source_bytes (string), target_px_area (number)");
    }
    
    size_t src_len;
    const unsigned char *src_buf = (const unsigned char *)lua_tolstring(L, 1, &src_len);
    double target_area = lua_tonumber(L, 2);
    
    if (target_area <= 0) {
        return luaL_error(L, "target_px_area must be greater than 0");
    }

    // 2. Setup libjpeg decompression
    struct jpeg_decompress_struct cinfo;
    struct my_error_mgr jerr;
    
    cinfo.err = jpeg_std_error(&jerr.pub);
    jerr.pub.error_exit = my_error_exit;
    
    if (setjmp(jerr.setjmp_buffer)) {
        jpeg_destroy_decompress(&cinfo);
        return luaL_error(L, "libjpeg error during decompression");
    }
    
    jpeg_create_decompress(&cinfo);
    jpeg_mem_src(&cinfo, src_buf, src_len);
    jpeg_read_header(&cinfo, TRUE);
    jpeg_start_decompress(&cinfo);
    
    int orig_w = cinfo.output_width;
    int orig_h = cinfo.output_height;
    int channels = cinfo.output_components;
    
    // 3. Calculate new dimensions (maintaining aspect ratio)
    double scale = sqrt(target_area / (double)(orig_w * orig_h));
    int new_w = (int)round(orig_w * scale);
    int new_h = (int)round(orig_h * scale);
    
    if (new_w < 1) new_w = 1;
    if (new_h < 1) new_h = 1;

    // 4. Read original image into memory
    unsigned char *orig_pixels = malloc(orig_w * orig_h * channels);
    if (!orig_pixels) {
        jpeg_destroy_decompress(&cinfo);
        return luaL_error(L, "out of memory allocating source image buffer");
    }
    
    while (cinfo.output_scanline < cinfo.output_height) {
        unsigned char *row_pointer = orig_pixels + (cinfo.output_scanline * orig_w * channels);
        jpeg_read_scanlines(&cinfo, &row_pointer, 1);
    }
    jpeg_finish_decompress(&cinfo);
    jpeg_destroy_decompress(&cinfo);

    // 5. Scale image (Nearest-Neighbor interpolation for brevity/performance)
    unsigned char *scaled_pixels = malloc(new_w * new_h * channels);
    if (!scaled_pixels) {
        free(orig_pixels);
        return luaL_error(L, "out of memory allocating scaled image buffer");
    }
    
    for (int y = 0; y < new_h; y++) {
        int src_y = y * orig_h / new_h;
        for (int x = 0; x < new_w; x++) {
            int src_x = x * orig_w / new_w;
            for (int c = 0; c < channels; c++) {
                scaled_pixels[(y * new_w + x) * channels + c] = 
                    orig_pixels[(src_y * orig_w + src_x) * channels + c];
            }
        }
    }
    free(orig_pixels); // Clean up old buffer

    // 6. Setup libjpeg compression
    struct jpeg_compress_struct cinfo_out;
    struct my_error_mgr jerr_out;
    
    cinfo_out.err = jpeg_std_error(&jerr_out.pub);
    jerr_out.pub.error_exit = my_error_exit;
    
    unsigned char *out_buf = NULL;
    unsigned long out_size = 0;
    
    if (setjmp(jerr_out.setjmp_buffer)) {
        free(scaled_pixels);
        if (out_buf) free(out_buf);
        jpeg_destroy_compress(&cinfo_out);
        return luaL_error(L, "libjpeg error during compression");
    }

    jpeg_create_compress(&cinfo_out);
    jpeg_mem_dest(&cinfo_out, &out_buf, &out_size);
    
    cinfo_out.image_width = new_w;
    cinfo_out.image_height = new_h;
    cinfo_out.input_components = channels;
    cinfo_out.in_color_space = (channels == 3) ? JCS_RGB : JCS_GRAYSCALE;
    
    jpeg_set_defaults(&cinfo_out);
    jpeg_set_quality(&cinfo_out, 85, TRUE); // 85 is a standard web quality
    
    jpeg_start_compress(&cinfo_out, TRUE);
    
    // 7. Write scaled image to memory
    int row_stride = new_w * channels;
    while (cinfo_out.next_scanline < cinfo_out.image_height) {
        unsigned char *row_pointer = scaled_pixels + (cinfo_out.next_scanline * row_stride);
        jpeg_write_scanlines(&cinfo_out, &row_pointer, 1);
    }
    
    jpeg_finish_compress(&cinfo_out);
    jpeg_destroy_compress(&cinfo_out);
    free(scaled_pixels); // Done with raw scaled pixels

    // 8. Return binary string to Lua and clean up
    lua_pushlstring(L, (const char *)out_buf, out_size);
    free(out_buf); // jpeg_mem_dest allocates with malloc, we must free it
    
    return 1;
}

// ---------------------------------------------------------
// Framework Lifecycle Methods
// ---------------------------------------------------------

static int luaopen_jpeg(lua_State *L) {
    const luaL_Reg jpeglib[] = {
        {"resize", l_jpeg_resize},
        {NULL, NULL}
    };

#if LUA_VERSION_NUM > 501
    luaL_newlib(L, jpeglib);
#else
    luaL_openlib(L, "jpeg", jpeglib, 0);
#endif
    return 1;
}

LIB_EXPORT int on_load(lua_State *L, serve_params *params, int reload) {
    // Register the 'jpeg' library globally in the Lua state
#if LUA_VERSION_NUM > 501
    luaL_requiref(L, "jpeg", luaopen_jpeg, 1);
    lua_pop(L, 1);
#else
    luaopen_jpeg(L);
#endif

    return 0;
}

LIB_EXPORT int on_unload(lua_State *L, serve_params *params, int reload) {
    // Clean up any persistent global state if necessary
    return 0;
}