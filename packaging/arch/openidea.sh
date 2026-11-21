#!/bin/sh
# Use the native resource lookup even when launched from an AppImage's environment.
unset APPDIR APPIMAGE
exec /usr/lib/openidea/openidea "$@"
