#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#import <MetalKit/MTKView.h>
#import <pthread/qos.h>
#import <objc/runtime.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <errno.h>

#include <atomic>
#include <cmath>
#include <cstring>

typedef NS_ENUM(NSInteger, GBModuleMode) {
    GBModuleModeNone = 0,
    GBModuleModeGameBoost = 1,
    GBModuleModeEnhanceGraphics = 2,
};

typedef NS_ENUM(NSInteger, GBIpadProfile) {
    GBIpadProfileRobloxTablet = 0,
    GBIpadProfilePUBGView = 1,
};

FOUNDATION_EXPORT NSString * const GBModuleModeKey;
FOUNDATION_EXPORT NSString * const GBPerformanceKey;
FOUNDATION_EXPORT NSString * const GBResolutionScaleKey;
FOUNDATION_EXPORT NSString * const GBLandscapeLockKey;
FOUNDATION_EXPORT NSString * const GBFrameRateKey;
FOUNDATION_EXPORT NSString * const GBLowLatencyKey;
FOUNDATION_EXPORT NSString * const GBKeepAwakeKey;
FOUNDATION_EXPORT NSString * const GBGraphicsScaleKey;
FOUNDATION_EXPORT NSString * const GBLinearFilteringKey;
FOUNDATION_EXPORT NSString * const GBTrilinearFilteringKey;
FOUNDATION_EXPORT NSString * const GBAnisotropyKey;
FOUNDATION_EXPORT NSString * const GBWideColorKey;
FOUNDATION_EXPORT NSString * const GBHighQualityScalingKey;
FOUNDATION_EXPORT NSString * const GBMenuScaleKey;
FOUNDATION_EXPORT NSString * const GBMenuDragKey;
FOUNDATION_EXPORT NSString * const GBMenuHueKey;
FOUNDATION_EXPORT NSString * const GBMenuOpacityKey;
FOUNDATION_EXPORT NSString * const GBLiquidGlassKey;
FOUNDATION_EXPORT NSString * const GBIpadModeEnabledKey;
FOUNDATION_EXPORT NSString * const GBIpadProfileKey;
FOUNDATION_EXPORT NSString * const GBSettingsDidChangeNotification;

extern std::atomic<int> gModuleMode;
extern GBModuleMode gLaunchedModuleMode;
extern std::atomic_bool gPerformanceEnabled;
extern std::atomic_bool gLandscapeLockEnabled;
extern std::atomic<int> gFrameRate;
extern std::atomic_bool gLowLatencyEnabled;
extern std::atomic_bool gKeepAwakeEnabled;
extern std::atomic_bool gLinearFilteringEnabled;
extern std::atomic_bool gTrilinearFilteringEnabled;
extern std::atomic<int> gAnisotropyLevel;
extern std::atomic_bool gWideColorEnabled;
extern std::atomic_bool gHighQualityScalingEnabled;
extern std::atomic<double> gConfiguredGraphicsScale;
extern std::atomic<double> gMenuScale;
extern std::atomic_bool gMenuDragEnabled;
extern std::atomic<double> gMenuHue;
extern std::atomic<double> gMenuOpacity;
extern std::atomic_bool gLiquidGlassEnabled;
extern std::atomic_bool gConfiguredIpadModeEnabled;
extern std::atomic<int> gConfiguredIpadProfile;
extern BOOL gLaunchedIpadModeEnabled;
extern GBIpadProfile gLaunchedIpadProfile;
extern std::atomic<double> gResolutionScale;
extern std::atomic<double> gConfiguredResolutionScale;
extern id gProcessActivity;
extern BOOL gIdleTimerOverrideActive;
extern BOOL gOriginalIdleTimerDisabled;
extern NSHashTable<CADisplayLink *> *gDisplayLinks;
extern UIScreen *gMainScreen;
extern UIScreenMode *gMainScreenMode;
extern CGFloat gOriginalMainScreenScale;
extern CGFloat gOriginalMainNativeScale;
extern CGRect gOriginalMainScreenBounds;
extern CGRect gOriginalMainNativeBounds;
extern CGSize gOriginalMainScreenModeSize;
extern NSInteger gMaximumFramesPerSecond;

extern const void *GBMetalKitManagedLayerKey;
extern const void *GBOverlayWindowKey;
extern const void *GBOriginalDisplayLinkFPSKey;
extern const void *GBOriginalMTKViewFPSKey;
extern const void *GBOriginalDrawableCountKey;
extern const void *GBOriginalMetalColorSpaceKey;
extern const void *GBOriginalMinificationFilterKey;
extern const void *GBOriginalMagnificationFilterKey;
extern const void *GBRequestedSamplerMinKey;
extern const void *GBRequestedSamplerMagKey;
extern const void *GBRequestedSamplerMipKey;
extern const void *GBRequestedSamplerAnisotropyKey;
extern const void *GBOrientationMaskOverrideKey;
extern const void *GBAutorotateOverrideKey;
extern const void *GBPreferredOrientationOverrideKey;

extern thread_local BOOL gApplyingDisplayLinkFPS;
extern thread_local BOOL gApplyingMTKViewFPS;
extern thread_local BOOL gApplyingSamplerSettings;
extern thread_local BOOL gApplyingIdleTimerOverride;

GBModuleMode GBCurrentModuleMode(void);
BOOL GBIsGameBoostActive(void);
BOOL GBIsEnhanceGraphicsActive(void);
GBIpadProfile GBSanitizeIpadProfile(NSInteger profile);
BOOL GBIsIpadModeActive(void);
BOOL GBIsRobloxTabletActive(void);
BOOL GBIsPUBGIpadViewActive(void);
const char *GBIpadMachineIdentifier(void);
int GBWriteSpoofedCString(const char *value, void *oldValue, size_t *oldLength);
CGFloat GBRobloxLogicalScaleFactor(CGSize size);
CGSize GBRobloxVirtualLogicalSize(CGSize size);
CGSize GBPUBGDrawableSize(CGSize size);
double GBClampGameScale(double scale);
double GBClampGraphicsScale(double scale);
double GBClampMenuScale(double scale);
double GBClampUnit(double value, double fallback);
int GBSanitizeFrameRate(NSInteger frameRate);
int GBSanitizeAnisotropy(NSInteger level);
BOOL GBIsUsableSize(CGSize size);
CGFloat GBCurrentScreenScale(void);
CGSize GBPixelSizeForBounds(CGSize boundsSize);
BOOL GBShouldLoadInCurrentProcess(void);

void GBPostSettingsChanged(void);
void GBUpdateProcessActivity(BOOL enabled);
void GBSetPerformanceEnabled(BOOL enabled, BOOL persist);
void GBApplyQoSToCurrentRenderThread(void);
NSArray<UIWindow *> *GBApplicationWindows(void);
BOOL GBIsOverlayWindow(UIWindow *window);
CGPoint GBRemapPUBGTouchPoint(CGPoint point, UIView *view);
UIInterfaceOrientationMask GBDeclaredOrientationMask(void);
UIWindow *GBHostApplicationWindow(void);
UIViewController *GBTopViewController(UIViewController *controller);
UIInterfaceOrientationMask GBHostOrientationMask(void);
BOOL GBAppIsLandscapeOnly(void);
BOOL GBShouldKeepLandscape(void);
UIInterfaceOrientationMask GBLandscapeMask(void);
BOOL GBMaskContainsOrientation(UIInterfaceOrientationMask mask,
                               UIInterfaceOrientation orientation);
UIInterfaceOrientation GBPreferredLandscapeOrientation(void);
void GBInstallControllerOrientationOverrides(UIViewController *controller);
void GBRequestOrientationUpdate(void);
void GBSetLandscapeLockEnabled(BOOL enabled, BOOL persist);
void GBApplyResolutionToViewTree(UIView *view, CGFloat screenScale);
void GBApplyResolutionToLayerTree(CALayer *layer, CGFloat screenScale);
void GBRefreshApplicationResolution(void);
void GBSetGameResolutionScale(double scale, BOOL persist);
void GBSetGraphicsResolutionScale(double scale, BOOL persist);
NSInteger GBEffectiveFrameRate(NSInteger requestedFrameRate);
void GBApplyFrameRateToViewTree(UIView *view);
void GBRegisterDisplayLink(CADisplayLink *displayLink);
void GBRefreshFrameRateTargets(void);
CGColorSpaceRef GBDisplayP3ColorSpace(void);
void GBApplyMetalLayerOptions(CAMetalLayer *layer);
void GBApplyMetalOptionsToLayerTree(CALayer *layer);
void GBRefreshMetalOptions(void);
void GBUpdateIdleTimerOverride(void);
void GBSetIpadModeEnabled(BOOL enabled, BOOL persist);
void GBSetIpadProfile(GBIpadProfile profile, BOOL persist);
void GBSetModuleMode(GBModuleMode mode, BOOL persist);
void GBSetFrameRate(NSInteger frameRate, BOOL persist);
void GBSetLowLatencyEnabled(BOOL enabled, BOOL persist);
void GBSetKeepAwakeEnabled(BOOL enabled, BOOL persist);
void GBSetGraphicsBoolean(std::atomic_bool &storage,
                          NSString *key,
                          BOOL enabled,
                          BOOL refreshMetal);
void GBSetAnisotropy(NSInteger level);

void GBInitializeRuntimeState(void);
void GBInstallOverlayIfPossible(void);
