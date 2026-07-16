#import "Sources/GameBoostShared.h"

void GBInitializeRuntimeState(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (!GBShouldLoadInCurrentProcess()) {
            return;
        }

        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        gMainScreen = UIScreen.mainScreen;
        gMainScreenMode = gMainScreen.currentMode;
        gOriginalMainScreenScale = MAX(1.0, gMainScreen.scale);
        gOriginalMainNativeScale = MAX(1.0, gMainScreen.nativeScale);
        gOriginalMainScreenBounds = gMainScreen.bounds;
        gOriginalMainNativeBounds = gMainScreen.nativeBounds;
        gMaximumFramesPerSecond = MAX(60, gMainScreen.maximumFramesPerSecond);
        gOriginalMainScreenModeSize = gMainScreenMode != nil
            ? gMainScreenMode.size
            : gOriginalMainNativeBounds.size;
        double savedScale = [defaults objectForKey:GBResolutionScaleKey] == nil
            ? 1.0
            : [defaults doubleForKey:GBResolutionScaleKey];
        double savedGraphicsScale = [defaults objectForKey:GBGraphicsScaleKey] == nil
            ? 1.0
            : [defaults doubleForKey:GBGraphicsScaleKey];
        const BOOL hasLegacyConfiguration =
            [defaults objectForKey:GBPerformanceKey] != nil ||
            [defaults objectForKey:GBResolutionScaleKey] != nil ||
            [defaults objectForKey:GBLandscapeLockKey] != nil;
        NSInteger savedModeValue = [defaults objectForKey:GBModuleModeKey] == nil
            ? (hasLegacyConfiguration ? GBModuleModeGameBoost : GBModuleModeNone)
            : [defaults integerForKey:GBModuleModeKey];
        GBModuleMode savedMode = savedModeValue == GBModuleModeGameBoost ||
                savedModeValue == GBModuleModeEnhanceGraphics
            ? (GBModuleMode)savedModeValue
            : GBModuleModeNone;
        BOOL savedPerformance = [defaults boolForKey:GBPerformanceKey];
        BOOL savedLandscapeLock = [defaults boolForKey:GBLandscapeLockKey];
        BOOL savedIpadMode = [defaults boolForKey:GBIpadModeEnabledKey];
        GBIpadProfile savedIpadProfile = GBSanitizeIpadProfile(
            [defaults objectForKey:GBIpadProfileKey] == nil
                ? GBIpadProfileRobloxTablet
                : [defaults integerForKey:GBIpadProfileKey]);

        const double gameScale = GBClampGameScale(savedScale);
        const double graphicsScale = GBClampGraphicsScale(savedGraphicsScale);
        const double initialScale = savedMode == GBModuleModeGameBoost
            ? gameScale
            : savedMode == GBModuleModeEnhanceGraphics
                ? graphicsScale
                : 1.0;
        gLaunchedModuleMode = savedMode;
        gModuleMode.store((int)savedMode, std::memory_order_relaxed);
        gResolutionScale.store(initialScale, std::memory_order_relaxed);
        gConfiguredResolutionScale.store(gameScale, std::memory_order_relaxed);
        gConfiguredGraphicsScale.store(graphicsScale, std::memory_order_relaxed);
        gPerformanceEnabled.store(savedPerformance, std::memory_order_relaxed);
        gLandscapeLockEnabled.store(savedLandscapeLock, std::memory_order_relaxed);
        gConfiguredIpadModeEnabled.store(savedIpadMode, std::memory_order_relaxed);
        gConfiguredIpadProfile.store((int)savedIpadProfile, std::memory_order_relaxed);
        gLaunchedIpadModeEnabled = savedIpadMode;
        gLaunchedIpadProfile = savedIpadProfile;
        gFrameRate.store(GBSanitizeFrameRate([defaults integerForKey:GBFrameRateKey]),
                         std::memory_order_relaxed);
        gLowLatencyEnabled.store([defaults boolForKey:GBLowLatencyKey],
                                 std::memory_order_relaxed);
        gKeepAwakeEnabled.store([defaults boolForKey:GBKeepAwakeKey],
                               std::memory_order_relaxed);
        gLinearFilteringEnabled.store([defaults objectForKey:GBLinearFilteringKey] == nil
                ? YES
                : [defaults boolForKey:GBLinearFilteringKey],
            std::memory_order_relaxed);
        gTrilinearFilteringEnabled.store([defaults objectForKey:GBTrilinearFilteringKey] == nil
                ? YES
                : [defaults boolForKey:GBTrilinearFilteringKey],
            std::memory_order_relaxed);
        NSInteger savedAnisotropy = [defaults objectForKey:GBAnisotropyKey] == nil
            ? 4
            : [defaults integerForKey:GBAnisotropyKey];
        gAnisotropyLevel.store(GBSanitizeAnisotropy(savedAnisotropy),
                               std::memory_order_relaxed);
        gWideColorEnabled.store([defaults boolForKey:GBWideColorKey],
                                std::memory_order_relaxed);
        gHighQualityScalingEnabled.store([defaults objectForKey:GBHighQualityScalingKey] == nil
                ? YES
                : [defaults boolForKey:GBHighQualityScalingKey],
            std::memory_order_relaxed);
        gMenuScale.store(GBClampMenuScale([defaults objectForKey:GBMenuScaleKey] == nil
                ? 1.0
                : [defaults doubleForKey:GBMenuScaleKey]),
            std::memory_order_relaxed);
        gMenuDragEnabled.store([defaults objectForKey:GBMenuDragKey] == nil
                ? YES
                : [defaults boolForKey:GBMenuDragKey],
            std::memory_order_relaxed);
        gMenuHue.store(GBClampUnit([defaults objectForKey:GBMenuHueKey] == nil
                ? 0.55
                : [defaults doubleForKey:GBMenuHueKey], 0.55),
            std::memory_order_relaxed);
        double savedOpacity = [defaults objectForKey:GBMenuOpacityKey] == nil
            ? 0.96
            : [defaults doubleForKey:GBMenuOpacityKey];
        gMenuOpacity.store(fmin(1.0, fmax(0.45, savedOpacity)),
                           std::memory_order_relaxed);
        gLiquidGlassEnabled.store([defaults objectForKey:GBLiquidGlassKey] == nil
                ? YES
                : [defaults boolForKey:GBLiquidGlassKey],
            std::memory_order_relaxed);
        gDisplayLinks = [NSHashTable weakObjectsHashTable];
    });
}

%ctor {
    @autoreleasepool {
        if (!GBShouldLoadInCurrentProcess()) {
            return;
        }
        GBInitializeRuntimeState();

        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(__unused NSNotification *notification) {
            GBInstallOverlayIfPossible();
            GBRefreshApplicationResolution();
            GBRefreshFrameRateTargets();
            GBRefreshMetalOptions();
            GBUpdateIdleTimerOverride();
            if (GBShouldKeepLandscape()) {
                GBRequestOrientationUpdate();
            }
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            GBUpdateProcessActivity(GBIsGameBoostActive() &&
                gPerformanceEnabled.load(std::memory_order_relaxed));
            GBUpdateIdleTimerOverride();
            GBInstallOverlayIfPossible();
            GBRefreshApplicationResolution();
            GBRefreshFrameRateTargets();
            GBRefreshMetalOptions();
            if (GBShouldKeepLandscape()) {
                GBRequestOrientationUpdate();
            }
        });
    }
}
