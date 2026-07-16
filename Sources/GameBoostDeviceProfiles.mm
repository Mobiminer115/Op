#import "GameBoostShared.h"

GBIpadProfile GBSanitizeIpadProfile(NSInteger profile) {
    return profile == GBIpadProfilePUBGView
        ? GBIpadProfilePUBGView
        : GBIpadProfileRobloxTablet;
}

BOOL GBIsIpadModeActive(void) {
    return gLaunchedIpadModeEnabled;
}

BOOL GBIsRobloxTabletActive(void) {
    return GBIsIpadModeActive() &&
        gLaunchedIpadProfile == GBIpadProfileRobloxTablet;
}

BOOL GBIsPUBGIpadViewActive(void) {
    return GBIsIpadModeActive() &&
        gLaunchedIpadProfile == GBIpadProfilePUBGView;
}

const char *GBIpadMachineIdentifier(void) {
    return GBIsPUBGIpadViewActive() ? "iPad14,6" : "iPad14,3";
}

int GBWriteSpoofedCString(const char *value,
                          void *oldValue,
                          size_t *oldLength) {
    if (value == nullptr || oldLength == nullptr) {
        errno = EINVAL;
        return -1;
    }
    const size_t requiredLength = std::strlen(value) + 1;
    if (oldValue == nullptr) {
        *oldLength = requiredLength;
        return 0;
    }
    const size_t availableLength = *oldLength;
    *oldLength = requiredLength;
    if (availableLength < requiredLength) {
        errno = ENOMEM;
        return -1;
    }
    std::memcpy(oldValue, value, requiredLength);
    return 0;
}

CGFloat GBRobloxLogicalScaleFactor(CGSize size) {
    if (!GBIsRobloxTabletActive() || size.width <= 0.0 || size.height <= 0.0) {
        return 1.0;
    }

    // Roblox CoreGui classifies touch screens by logical resolution. Keep the
    // phone's real aspect ratio, but cross both known tablet cutoffs so the
    // hotbar and player list use their expanded layouts without stretching.
    const CGFloat longEdge = MAX(size.width, size.height);
    const CGFloat shortEdge = MIN(size.width, size.height);
    return MAX(1.0, MAX(1026.0 / longEdge, 502.0 / shortEdge));
}

CGSize GBRobloxVirtualLogicalSize(CGSize size) {
    const CGFloat factor = GBRobloxLogicalScaleFactor(size);
    return CGSizeMake(ceil(size.width * factor), ceil(size.height * factor));
}

CGSize GBPUBGDrawableSize(CGSize size) {
    if (!GBIsPUBGIpadViewActive() || size.width <= 0.0 || size.height <= 0.0 ||
        !std::isfinite(size.width) || !std::isfinite(size.height)) {
        return size;
    }

    // Render a real 4:3 surface, then let CoreAnimation fit that surface into
    // the phone layer. The old implementation left gravity at Resize, which
    // stretched the 4:3 drawable across the entire wide display.
    if (size.width >= size.height) {
        size.width = MAX(1.0, round(size.height * (4.0 / 3.0)));
    } else {
        size.height = MAX(1.0, round(size.width * (4.0 / 3.0)));
    }
    return size;
}
