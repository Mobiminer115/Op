#import "GameBoostShared.h"

void GBSetIpadModeEnabled(BOOL enabled, BOOL persist) {
    gConfiguredIpadModeEnabled.store(enabled, std::memory_order_relaxed);
    if (persist) {
        [NSUserDefaults.standardUserDefaults setBool:enabled
                                              forKey:GBIpadModeEnabledKey];
        [NSUserDefaults.standardUserDefaults synchronize];
    }
    GBPostSettingsChanged();
}

void GBSetIpadProfile(GBIpadProfile profile, BOOL persist) {
    profile = GBSanitizeIpadProfile(profile);
    gConfiguredIpadProfile.store((int)profile, std::memory_order_relaxed);
    if (persist) {
        [NSUserDefaults.standardUserDefaults setInteger:profile
                                                 forKey:GBIpadProfileKey];
        [NSUserDefaults.standardUserDefaults synchronize];
    }
    GBPostSettingsChanged();
}

void GBSetModuleMode(GBModuleMode mode, BOOL persist) {
    if (mode != GBModuleModeNone &&
        mode != GBModuleModeGameBoost &&
        mode != GBModuleModeEnhanceGraphics) {
        mode = GBModuleModeNone;
    }
    GBModuleMode oldMode = (GBModuleMode)gModuleMode.exchange((int)mode,
                                                              std::memory_order_relaxed);
    if (persist) {
        [NSUserDefaults.standardUserDefaults setInteger:mode forKey:GBModuleModeKey];
        [NSUserDefaults.standardUserDefaults synchronize];
    }
    GBUpdateProcessActivity(GBIsGameBoostActive() &&
        gPerformanceEnabled.load(std::memory_order_relaxed));
    GBUpdateIdleTimerOverride();
    GBRefreshFrameRateTargets();
    GBRefreshMetalOptions();
    GBPostSettingsChanged();
    if (oldMode != mode) {
        GBRequestOrientationUpdate();
    }
}

void GBSetFrameRate(NSInteger frameRate, BOOL persist) {
    const int sanitized = GBSanitizeFrameRate(frameRate);
    gFrameRate.store(sanitized, std::memory_order_relaxed);
    if (persist) {
        [NSUserDefaults.standardUserDefaults setInteger:sanitized forKey:GBFrameRateKey];
    }
    GBRefreshFrameRateTargets();
    GBPostSettingsChanged();
}

void GBSetLowLatencyEnabled(BOOL enabled, BOOL persist) {
    gLowLatencyEnabled.store(enabled, std::memory_order_relaxed);
    if (persist) {
        [NSUserDefaults.standardUserDefaults setBool:enabled forKey:GBLowLatencyKey];
    }
    GBRefreshMetalOptions();
    GBPostSettingsChanged();
}

void GBSetKeepAwakeEnabled(BOOL enabled, BOOL persist) {
    gKeepAwakeEnabled.store(enabled, std::memory_order_relaxed);
    if (persist) {
        [NSUserDefaults.standardUserDefaults setBool:enabled forKey:GBKeepAwakeKey];
    }
    GBUpdateIdleTimerOverride();
    GBPostSettingsChanged();
}

void GBSetGraphicsBoolean(std::atomic_bool &storage,
                                 NSString *key,
                                 BOOL enabled,
                                 BOOL refreshMetal) {
    storage.store(enabled, std::memory_order_relaxed);
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:key];
    if (refreshMetal) {
        GBRefreshMetalOptions();
    }
    GBPostSettingsChanged();
}

void GBSetAnisotropy(NSInteger level) {
    const int sanitized = GBSanitizeAnisotropy(level);
    gAnisotropyLevel.store(sanitized, std::memory_order_relaxed);
    [NSUserDefaults.standardUserDefaults setInteger:sanitized forKey:GBAnisotropyKey];
    GBPostSettingsChanged();
}
