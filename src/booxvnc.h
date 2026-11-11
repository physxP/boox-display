// Lets booxvnc.swift use libvncserver (Homebrew).
#include <rfb/rfb.h>

// rfbInitServer is a macro that picks the build variant; Swift can't see macros.
static inline void booxvnc_init(rfbScreenInfoPtr screen) { rfbInitServer(screen); }
