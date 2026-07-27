#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <stdint.h>
#import <string.h>

void DroidBoxApplyGameResolution(int width, int height) {
    if (width <= 0 || height <= 0) return;
    void *(*getCurrentWindow)(void) = dlsym(RTLD_DEFAULT, "SDL_GL_GetCurrentWindow");
    void (*setWindowSize)(void *, int, int) = dlsym(RTLD_DEFAULT, "SDL_SetWindowSize");
    if (getCurrentWindow && setWindowSize) {
        void *window = getCurrentWindow();
        if (window) setWindowSize(window, width, height);
    }
}

void DroidBoxSendGameKey(int keycode, int pressed) {
    int (*pushEvent)(void *) = dlsym(RTLD_DEFAULT, "SDL_PushEvent");
    if (!pushEvent) return;

    // Binary layout of SDL_KeyboardEvent/SDL_Keysym. Keeping the bridge dynamic
    // avoids coupling the SwiftUI target to a particular SDL header directory.
    struct {
        uint32_t type;
        uint32_t timestamp;
        uint32_t windowID;
        uint8_t state;
        uint8_t repeat;
        uint8_t padding2;
        uint8_t padding3;
        int32_t scancode;
        int32_t sym;
        uint16_t mod;
        uint32_t unused;
        uint8_t tail[32];
    } event;
    memset(&event, 0, sizeof(event));
    event.type = pressed ? 0x300 : 0x301; // SDL_KEYDOWN / SDL_KEYUP
    event.state = pressed ? 1 : 0;
    event.sym = keycode;
    pushEvent(&event);
}
