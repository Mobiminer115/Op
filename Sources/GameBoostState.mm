#import "GameBoostShared.h"

NSString * const GBModuleModeKey = @"com.gameboost.universal.module-mode";
NSString * const GBPerformanceKey = @"com.gameboost.universal.performance-enabled";
NSString * const GBResolutionScaleKey = @"com.gameboost.universal.resolution-scale";
NSString * const GBLandscapeLockKey = @"com.gameboost.universal.landscape-lock-enabled";
NSString * const GBFrameRateKey = @"com.gameboost.universal.frame-rate";
NSString * const GBLowLatencyKey = @"com.gameboost.universal.low-latency";
NSString * const GBKeepAwakeKey = @"com.gameboost.universal.keep-awake";
NSString * const GBGraphicsScaleKey = @"com.gameboost.universal.graphics-scale";
NSString * const GBLinearFilteringKey = @"com.gameboost.universal.linear-filtering";
NSString * const GBTrilinearFilteringKey = @"com.gameboost.universal.trilinear-filtering";
NSString * const GBAnisotropyKey = @"com.gameboost.universal.anisotropy";
NSString * const GBWideColorKey = @"com.gameboost.universal.wide-color";
NSString * const GBHighQualityScalingKey = @"com.gameboost.universal.high-quality-scaling";
NSString * const GBMenuScaleKey = @"com.gameboost.universal.menu-scale";
NSString * const GBMenuDragKey = @"com.gameboost.universal.menu-drag";
NSString * const GBMenuHueKey = @"com.gameboost.universal.menu-hue";
NSString * const GBMenuOpacityKey = @"com.gameboost.universal.menu-opacity";
NSString * const GBLiquidGlassKey = @"com.gameboost.universal.liquid-glass";
NSString * const GBIpadModeEnabledKey = @"com.gameboost.universal.ipad-mode-enabled";
NSString * const GBIpadProfileKey = @"com.gameboost.universal.ipad-profile";
NSString * const GBSettingsDidChangeNotification = @"com.gameboost.universal.settings-changed";

std::atomic<int> gModuleMode((int)GBModuleModeNone);
GBModuleMode gLaunchedModuleMode = GBModuleModeNone;
std::atomic_bool gPerformanceEnabled(false);
std::atomic_bool gLandscapeLockEnabled(false);
std::atomic<int> gFrameRate(0);
std::atomic_bool gLowLatencyEnabled(false);
std::atomic_bool gKeepAwakeEnabled(false);
std::atomic_bool gLinearFilteringEnabled(true);
std::atomic_bool gTrilinearFilteringEnabled(true);
std::atomic<int> gAnisotropyLevel(4);
std::atomic_bool gWideColorEnabled(false);
std::atomic_bool gHighQualityScalingEnabled(true);
std::atomic<double> gConfiguredGraphicsScale(1.0);
std::atomic<double> gMenuScale(1.0);
std::atomic_bool gMenuDragEnabled(true);
std::atomic<double> gMenuHue(0.55);
std::atomic<double> gMenuOpacity(0.96);
std::atomic_bool gLiquidGlassEnabled(true);
std::atomic_bool gConfiguredIpadModeEnabled(false);
std::atomic<int> gConfiguredIpadProfile((int)GBIpadProfileRobloxTablet);
BOOL gLaunchedIpadModeEnabled = NO;
GBIpadProfile gLaunchedIpadProfile = GBIpadProfileRobloxTablet;
// gResolutionScale is the scale currently active in the renderer. The menu
// writes one of the configured scales; the selected module and scale become
// active on the next app launch so cached engine viewports never half-update.
std::atomic<double> gResolutionScale(1.0);
std::atomic<double> gConfiguredResolutionScale(1.0);
id gProcessActivity = nil;
BOOL gIdleTimerOverrideActive = NO;
BOOL gOriginalIdleTimerDisabled = NO;
NSHashTable<CADisplayLink *> *gDisplayLinks = nil;
UIScreen *gMainScreen = nil;
UIScreenMode *gMainScreenMode = nil;
CGFloat gOriginalMainScreenScale = 1.0;
CGFloat gOriginalMainNativeScale = 1.0;
CGRect gOriginalMainScreenBounds = CGRectZero;
CGRect gOriginalMainNativeBounds = CGRectZero;
CGSize gOriginalMainScreenModeSize = CGSizeZero;
NSInteger gMaximumFramesPerSecond = 60;

const void *GBMetalKitManagedLayerKey = &GBMetalKitManagedLayerKey;
const void *GBOverlayWindowKey = &GBOverlayWindowKey;
const void *GBOriginalDisplayLinkFPSKey = &GBOriginalDisplayLinkFPSKey;
const void *GBOriginalMTKViewFPSKey = &GBOriginalMTKViewFPSKey;
const void *GBOriginalDrawableCountKey = &GBOriginalDrawableCountKey;
const void *GBOriginalMetalColorSpaceKey = &GBOriginalMetalColorSpaceKey;
const void *GBOriginalMinificationFilterKey = &GBOriginalMinificationFilterKey;
const void *GBOriginalMagnificationFilterKey = &GBOriginalMagnificationFilterKey;
const void *GBRequestedSamplerMinKey = &GBRequestedSamplerMinKey;
const void *GBRequestedSamplerMagKey = &GBRequestedSamplerMagKey;
const void *GBRequestedSamplerMipKey = &GBRequestedSamplerMipKey;
const void *GBRequestedSamplerAnisotropyKey = &GBRequestedSamplerAnisotropyKey;
const void *GBOrientationMaskOverrideKey = &GBOrientationMaskOverrideKey;
const void *GBAutorotateOverrideKey = &GBAutorotateOverrideKey;
const void *GBPreferredOrientationOverrideKey = &GBPreferredOrientationOverrideKey;

thread_local BOOL gApplyingDisplayLinkFPS = NO;
thread_local BOOL gApplyingMTKViewFPS = NO;
thread_local BOOL gApplyingSamplerSettings = NO;
thread_local BOOL gApplyingIdleTimerOverride = NO;

GBModuleMode GBCurrentModuleMode(void) {
    return (GBModuleMode)gModuleMode.load(std::memory_order_relaxed);
}

BOOL GBIsGameBoostActive(void) {
    return GBCurrentModuleMode() == GBModuleModeGameBoost;
}

BOOL GBIsEnhanceGraphicsActive(void) {
    return GBCurrentModuleMode() == GBModuleModeEnhanceGraphics;
}

double GBClampGameScale(double scale) {
    if (!std::isfinite(scale)) {
        return 1.0;
    }
    return fmin(1.0, fmax(0.1, scale));
}

double GBClampGraphicsScale(double scale) {
    if (!std::isfinite(scale)) {
        return 1.0;
    }
    return fmin(1.5, fmax(1.0, scale));
}

double GBClampMenuScale(double scale) {
    if (!std::isfinite(scale)) {
        return 1.0;
    }
    return fmin(1.25, fmax(0.75, scale));
}

double GBClampUnit(double value, double fallback) {
    if (!std::isfinite(value)) {
        return fallback;
    }
    return fmin(1.0, fmax(0.0, value));
}

int GBSanitizeFrameRate(NSInteger frameRate) {
    return frameRate == 30 || frameRate == 60 || frameRate == 120
        ? (int)frameRate
        : 0;
}

int GBSanitizeAnisotropy(NSInteger level) {
    if (level >= 16) return 16;
    if (level >= 8) return 8;
    if (level >= 4) return 4;
    if (level >= 2) return 2;
    return 1;
}

BOOL GBIsUsableSize(CGSize size) {
    return size.width > 0.0 && size.height > 0.0 &&
           std::isfinite(size.width) && std::isfinite(size.height);
}

CGFloat GBCurrentScreenScale(void) {
    const CGFloat virtualFactor = GBRobloxLogicalScaleFactor(
        gOriginalMainScreenBounds.size);
    return MAX(0.1, (gOriginalMainScreenScale / virtualFactor) *
        (CGFloat)gResolutionScale.load(std::memory_order_relaxed));
}

CGSize GBPixelSizeForBounds(CGSize boundsSize) {
    if (!GBIsUsableSize(boundsSize)) {
        return CGSizeZero;
    }

    const CGFloat screenScale = GBCurrentScreenScale();
    CGSize pixelSize = CGSizeMake(MAX(1.0, round(boundsSize.width * screenScale)),
                                  MAX(1.0, round(boundsSize.height * screenScale)));
    return GBPUBGDrawableSize(pixelSize);
}

BOOL GBShouldLoadInCurrentProcess(void) {
    NSBundle *mainBundle = NSBundle.mainBundle;
    NSString *bundlePath = mainBundle.bundlePath != nil
        ? mainBundle.bundlePath
        : @"";
    NSString *bundleIdentifier = mainBundle.bundleIdentifier != nil
        ? mainBundle.bundleIdentifier
        : @"";

    // The com.apple.UIKit filter also matches SpringBoard, app extensions and
    // several UIKit helper processes. This tweak owns a UIWindow, so only run
    // inside a normal .app process and never inside SpringBoard.
    BOOL isRegularApplication =
        [bundlePath.pathExtension.lowercaseString isEqualToString:@"app"];
    BOOL isSpringBoard =
        [bundleIdentifier.lowercaseString isEqualToString:@"com.apple.springboard"];
    BOOL hasUIApplication = NSClassFromString(@"UIApplication") != Nil;

    return isRegularApplication && !isSpringBoard && hasUIApplication;
}
