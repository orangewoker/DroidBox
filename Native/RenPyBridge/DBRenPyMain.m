#include <stdio.h>

int launcher_main(int argc, char **argv);
int SDL_UIKitRunApp(int argc, char **argv, int (*mainFunction)(int, char **));
int DroidBoxFrontendMain(int argc, char **argv);

static int droidbox_main(int argc, char **argv) {
    int result = DroidBoxFrontendMain(argc, argv);
    if (result != 0) return result;
    return launcher_main(argc, argv);
}

int main(int argc, char **argv) {
    return SDL_UIKitRunApp(argc, argv, droidbox_main);
}
