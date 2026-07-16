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

static NSString * const GBModuleModeKey = @"com.gameboost.universal.module-mode";
static NSString * const GBPerformanceKey = @"com.gameboost.universal.performance-enabled";
static NSString * const GBResolutionScaleKey = @"com.gameboost.universal.resolution-scale";
static NSString * const GBLandscapeLockKey = @"com.gameboost.universal.landscape-lock-enabled";
static NSString * const GBFrameRateKey = @"com.gameboost.universal.frame-rate";
static NSString * const GBLowLatencyKey = @"com.gameboost.universal.low-latency";
static NSString * const GBKeepAwakeKey = @"com.gameboost.universal.keep-awake";
static NSString * const GBGraphicsScaleKey = @"com.gameboost.universal.graphics-scale";
static NSString * const GBLinearFilteringKey = @"com.gameboost.universal.linear-filtering";
static NSString * const GBTrilinearFilteringKey = @"com.gameboost.universal.trilinear-filtering";
static NSString * const GBAnisotropyKey = @"com.gameboost.universal.anisotropy";
static NSString * const GBWideColorKey = @"com.gameboost.universal.wide-color";
static NSString * const GBHighQualityScalingKey = @"com.gameboost.universal.high-quality-scaling";
static NSString * const GBMenuScaleKey = @"com.gameboost.universal.menu-scale";
static NSString * const GBMenuDragKey = @"com.gameboost.universal.menu-drag";
static NSString * const GBMenuHueKey = @"com.gameboost.universal.menu-hue";
static NSString * const GBMenuOpacityKey = @"com.gameboost.universal.menu-opacity";
static NSString * const GBLiquidGlassKey = @"com.gameboost.universal.liquid-glass";
static NSString * const GBIpadModeEnabledKey = @"com.gameboost.universal.ipad-mode-enabled";
static NSString * const GBIpadProfileKey = @"com.gameboost.universal.ipad-profile";
static NSString * const GBSettingsDidChangeNotification = @"com.gameboost.universal.settings-changed";

static std::atomic<int> gModuleMode((int)GBModuleModeNone);
static GBModuleMode gLaunchedModuleMode = GBModuleModeNone;
static std::atomic_bool gPerformanceEnabled(false);
static std::atomic_bool gLandscapeLockEnabled(false);
static std::atomic<int> gFrameRate(0);
static std::atomic_bool gLowLatencyEnabled(false);
static std::atomic_bool gKeepAwakeEnabled(false);
static std::atomic_bool gLinearFilteringEnabled(true);
static std::atomic_bool gTrilinearFilteringEnabled(true);
static std::atomic<int> gAnisotropyLevel(4);
static std::atomic_bool gWideColorEnabled(false);
static std::atomic_bool gHighQualityScalingEnabled(true);
static std::atomic<double> gConfiguredGraphicsScale(1.0);
static std::atomic<double> gMenuScale(1.0);
static std::atomic_bool gMenuDragEnabled(true);
static std::atomic<double> gMenuHue(0.55);
static std::atomic<double> gMenuOpacity(0.96);
static std::atomic_bool gLiquidGlassEnabled(true);
static std::atomic_bool gConfiguredIpadModeEnabled(false);
static std::atomic<int> gConfiguredIpadProfile((int)GBIpadProfileRobloxTablet);
static BOOL gLaunchedIpadModeEnabled = NO;
static GBIpadProfile gLaunchedIpadProfile = GBIpadProfileRobloxTablet;
// gResolutionScale is the scale currently active in the renderer. The menu
// writes one of the configured scales; the selected module and scale become
// active on the next app launch so cached engine viewports never half-update.
static std::atomic<double> gResolutionScale(1.0);
static std::atomic<double> gConfiguredResolutionScale(1.0);
static id gProcessActivity = nil;
static BOOL gIdleTimerOverrideActive = NO;
static BOOL gOriginalIdleTimerDisabled = NO;
static NSHashTable<CADisplayLink *> *gDisplayLinks = nil;
static UIScreen *gMainScreen = nil;
static UIScreenMode *gMainScreenMode = nil;
static CGFloat gOriginalMainScreenScale = 1.0;
static CGFloat gOriginalMainNativeScale = 1.0;
static CGRect gOriginalMainScreenBounds = CGRectZero;
static CGRect gOriginalMainNativeBounds = CGRectZero;
static CGSize gOriginalMainScreenModeSize = CGSizeZero;
static NSInteger gMaximumFramesPerSecond = 60;

static const void *GBMetalKitManagedLayerKey = &GBMetalKitManagedLayerKey;
static const void *GBOverlayWindowKey = &GBOverlayWindowKey;
static const void *GBOriginalDisplayLinkFPSKey = &GBOriginalDisplayLinkFPSKey;
static const void *GBOriginalMTKViewFPSKey = &GBOriginalMTKViewFPSKey;
static const void *GBOriginalDrawableCountKey = &GBOriginalDrawableCountKey;
static const void *GBOriginalMetalColorSpaceKey = &GBOriginalMetalColorSpaceKey;
static const void *GBOriginalMinificationFilterKey = &GBOriginalMinificationFilterKey;
static const void *GBOriginalMagnificationFilterKey = &GBOriginalMagnificationFilterKey;
static const void *GBRequestedSamplerMinKey = &GBRequestedSamplerMinKey;
static const void *GBRequestedSamplerMagKey = &GBRequestedSamplerMagKey;
static const void *GBRequestedSamplerMipKey = &GBRequestedSamplerMipKey;
static const void *GBRequestedSamplerAnisotropyKey = &GBRequestedSamplerAnisotropyKey;
static const void *GBOrientationMaskOverrideKey = &GBOrientationMaskOverrideKey;
static const void *GBAutorotateOverrideKey = &GBAutorotateOverrideKey;
static const void *GBPreferredOrientationOverrideKey = &GBPreferredOrientationOverrideKey;

static thread_local BOOL gApplyingDisplayLinkFPS = NO;
static thread_local BOOL gApplyingMTKViewFPS = NO;
static thread_local BOOL gApplyingSamplerSettings = NO;
static thread_local BOOL gApplyingIdleTimerOverride = NO;

static GBModuleMode GBCurrentModuleMode(void) {
    return (GBModuleMode)gModuleMode.load(std::memory_order_relaxed);
}

static BOOL GBIsGameBoostActive(void) {
    return GBCurrentModuleMode() == GBModuleModeGameBoost;
}

static BOOL GBIsEnhanceGraphicsActive(void) {
    return GBCurrentModuleMode() == GBModuleModeEnhanceGraphics;
}

static GBIpadProfile GBSanitizeIpadProfile(NSInteger profile) {
    return profile == GBIpadProfilePUBGView
        ? GBIpadProfilePUBGView
        : GBIpadProfileRobloxTablet;
}

static BOOL GBIsIpadModeActive(void) {
    return gLaunchedIpadModeEnabled;
}

static BOOL GBIsRobloxTabletActive(void) {
    return GBIsIpadModeActive() &&
        gLaunchedIpadProfile == GBIpadProfileRobloxTablet;
}

static BOOL GBIsPUBGIpadViewActive(void) {
    return GBIsIpadModeActive() &&
        gLaunchedIpadProfile == GBIpadProfilePUBGView;
}

static const char *GBIpadMachineIdentifier(void) {
    return GBIsPUBGIpadViewActive() ? "iPad14,6" : "iPad14,3";
}

static int GBWriteSpoofedCString(const char *value,
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

static CGFloat GBRobloxLogicalScaleFactor(CGSize size) {
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

static CGSize GBRobloxVirtualLogicalSize(CGSize size) {
    const CGFloat factor = GBRobloxLogicalScaleFactor(size);
    return CGSizeMake(ceil(size.width * factor), ceil(size.height * factor));
}

static CGSize GBPUBGDrawableSize(CGSize size) {
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

static double GBClampGameScale(double scale) {
    if (!std::isfinite(scale)) {
        return 1.0;
    }
    return fmin(1.0, fmax(0.1, scale));
}

static double GBClampGraphicsScale(double scale) {
    if (!std::isfinite(scale)) {
        return 1.0;
    }
    return fmin(1.5, fmax(1.0, scale));
}

static double GBClampMenuScale(double scale) {
    if (!std::isfinite(scale)) {
        return 1.0;
    }
    return fmin(1.25, fmax(0.75, scale));
}

static double GBClampUnit(double value, double fallback) {
    if (!std::isfinite(value)) {
        return fallback;
    }
    return fmin(1.0, fmax(0.0, value));
}

static int GBSanitizeFrameRate(NSInteger frameRate) {
    return frameRate == 30 || frameRate == 60 || frameRate == 120
        ? (int)frameRate
        : 0;
}

static int GBSanitizeAnisotropy(NSInteger level) {
    if (level >= 16) return 16;
    if (level >= 8) return 8;
    if (level >= 4) return 4;
    if (level >= 2) return 2;
    return 1;
}

static BOOL GBIsUsableSize(CGSize size) {
    return size.width > 0.0 && size.height > 0.0 &&
           std::isfinite(size.width) && std::isfinite(size.height);
}

static CGFloat GBCurrentScreenScale(void) {
    const CGFloat virtualFactor = GBRobloxLogicalScaleFactor(
        gOriginalMainScreenBounds.size);
    return MAX(0.1, (gOriginalMainScreenScale / virtualFactor) *
        (CGFloat)gResolutionScale.load(std::memory_order_relaxed));
}

static CGSize GBPixelSizeForBounds(CGSize boundsSize) {
    if (!GBIsUsableSize(boundsSize)) {
        return CGSizeZero;
    }

    const CGFloat screenScale = GBCurrentScreenScale();
    CGSize pixelSize = CGSizeMake(MAX(1.0, round(boundsSize.width * screenScale)),
                                  MAX(1.0, round(boundsSize.height * screenScale)));
    return GBPUBGDrawableSize(pixelSize);
}

static BOOL GBShouldLoadInCurrentProcess(void) {
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

static void GBPostSettingsChanged(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:GBSettingsDidChangeNotification
                                                          object:nil];
    });
}

static void GBUpdateProcessActivity(BOOL enabled) {
    dispatch_block_t update = ^{
        if (enabled && gProcessActivity == nil) {
            NSActivityOptions options = NSActivityUserInitiated;
            gProcessActivity = [NSProcessInfo.processInfo beginActivityWithOptions:options
                                                                            reason:@"GameBoost interactive rendering"];
        } else if (!enabled && gProcessActivity != nil) {
            [NSProcessInfo.processInfo endActivity:gProcessActivity];
            gProcessActivity = nil;
        }
    };

    if (NSThread.isMainThread) {
        update();
    } else {
        dispatch_async(dispatch_get_main_queue(), update);
    }
}

static void GBSetPerformanceEnabled(BOOL enabled, BOOL persist) {
    gPerformanceEnabled.store(enabled, std::memory_order_relaxed);
    GBUpdateProcessActivity(enabled && GBIsGameBoostActive());

    if (persist) {
        [NSUserDefaults.standardUserDefaults setBool:enabled forKey:GBPerformanceKey];
    }
    GBPostSettingsChanged();
}

static void GBApplyQoSToCurrentRenderThread(void) {
    static thread_local BOOL promoted = NO;
    static thread_local qos_class_t previousClass = QOS_CLASS_UNSPECIFIED;
    static thread_local int previousRelativePriority = 0;

    const BOOL shouldPromote = GBIsGameBoostActive() &&
        gPerformanceEnabled.load(std::memory_order_relaxed);
    if (shouldPromote && !promoted) {
        qos_class_t detectedClass = QOS_CLASS_UNSPECIFIED;
        int detectedRelativePriority = 0;
        if (pthread_get_qos_class_np(pthread_self(),
                                     &detectedClass,
                                     &detectedRelativePriority) == 0) {
            previousClass = detectedClass;
            previousRelativePriority = detectedRelativePriority;
        }
        if (pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0) == 0) {
            promoted = YES;
        }
    } else if (!shouldPromote && promoted) {
        qos_class_t restoreClass = previousClass == QOS_CLASS_UNSPECIFIED
            ? QOS_CLASS_DEFAULT
            : previousClass;
        pthread_set_qos_class_self_np(restoreClass, previousRelativePriority);
        promoted = NO;
    }
}

static NSArray<UIWindow *> *GBApplicationWindows(void) {
    if (@available(iOS 13.0, *)) {
        NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) {
                continue;
            }
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            [windows addObjectsFromArray:windowScene.windows];
        }
        if (windows.count > 0) {
            return windows.copy;
        }
    }
    NSArray<UIWindow *> *legacyWindows =
        [UIApplication.sharedApplication valueForKey:@"windows"];
    return legacyWindows != nil ? legacyWindows : @[];
}

static BOOL GBIsOverlayWindow(UIWindow *window) {
    return [objc_getAssociatedObject(window, GBOverlayWindowKey) boolValue];
}

static CGPoint GBRemapPUBGTouchPoint(CGPoint point, UIView *view) {
    if (!GBIsPUBGIpadViewActive() || view == nil ||
        GBIsOverlayWindow(view.window) || !GBIsUsableSize(view.bounds.size)) {
        return point;
    }

    BOOL metalBacked = NO;
    for (UIView *candidate = view; candidate != nil; candidate = candidate.superview) {
        if ([candidate.layer isKindOfClass:CAMetalLayer.class]) {
            metalBacked = YES;
            break;
        }
    }
    if (!metalBacked) {
        return point;
    }

    const CGFloat aspect = 4.0 / 3.0;
    const CGFloat width = view.bounds.size.width;
    const CGFloat height = view.bounds.size.height;
    if (width / height > aspect) {
        const CGFloat contentWidth = height * aspect;
        const CGFloat inset = (width - contentWidth) * 0.5;
        const CGFloat normalized = fmin(1.0, fmax(0.0,
            (point.x - inset) / contentWidth));
        point.x = normalized * width;
    } else if (width / height < aspect) {
        const CGFloat contentHeight = width / aspect;
        const CGFloat inset = (height - contentHeight) * 0.5;
        const CGFloat normalized = fmin(1.0, fmax(0.0,
            (point.y - inset) / contentHeight));
        point.y = normalized * height;
    }
    return point;
}

static UIInterfaceOrientationMask GBDeclaredOrientationMask(void) {
    static UIInterfaceOrientationMask mask;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSBundle *bundle = NSBundle.mainBundle;
        BOOL isPad = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad;
        NSString *deviceKey = isPad
            ? @"UISupportedInterfaceOrientations~ipad"
            : @"UISupportedInterfaceOrientations~iphone";
        NSArray<NSString *> *names = [bundle objectForInfoDictionaryKey:deviceKey];
        if (![names isKindOfClass:NSArray.class] || names.count == 0) {
            names = [bundle objectForInfoDictionaryKey:@"UISupportedInterfaceOrientations"];
        }

        for (NSString *name in names) {
            if ([name isEqualToString:@"UIInterfaceOrientationPortrait"]) {
                mask |= UIInterfaceOrientationMaskPortrait;
            } else if ([name isEqualToString:@"UIInterfaceOrientationPortraitUpsideDown"]) {
                mask |= UIInterfaceOrientationMaskPortraitUpsideDown;
            } else if ([name isEqualToString:@"UIInterfaceOrientationLandscapeLeft"]) {
                mask |= UIInterfaceOrientationMaskLandscapeLeft;
            } else if ([name isEqualToString:@"UIInterfaceOrientationLandscapeRight"]) {
                mask |= UIInterfaceOrientationMaskLandscapeRight;
            }
        }

        if (mask == 0) {
            mask = isPad ? UIInterfaceOrientationMaskAll
                         : UIInterfaceOrientationMaskPortrait;
        }
    });
    return mask;
}

static UIWindow *GBHostApplicationWindow(void) {
    UIWindow *fallback = nil;
    for (UIWindow *window in GBApplicationWindows()) {
        if (GBIsOverlayWindow(window) || window.hidden || window.alpha <= 0.01 ||
            window.rootViewController == nil) {
            continue;
        }
        if (window.isKeyWindow) {
            return window;
        }
        if (fallback == nil || window.windowLevel < fallback.windowLevel) {
            fallback = window;
        }
    }
    return fallback;
}

static UIViewController *GBTopViewController(UIViewController *controller) {
    while (controller != nil) {
        UIViewController *next = nil;
        if (controller.presentedViewController != nil &&
            !controller.presentedViewController.isBeingDismissed) {
            next = controller.presentedViewController;
        } else if ([controller isKindOfClass:UINavigationController.class]) {
            next = ((UINavigationController *)controller).visibleViewController;
        } else if ([controller isKindOfClass:UITabBarController.class]) {
            next = ((UITabBarController *)controller).selectedViewController;
        } else if ([controller isKindOfClass:UISplitViewController.class]) {
            next = ((UISplitViewController *)controller).viewControllers.lastObject;
        }

        if (next == nil || next == controller) {
            break;
        }
        controller = next;
    }
    return controller;
}

static UIInterfaceOrientationMask GBHostOrientationMask(void) {
    UIWindow *hostWindow = GBHostApplicationWindow();
    UIViewController *controller =
        GBTopViewController(hostWindow.rootViewController);
    UIInterfaceOrientationMask mask = controller != nil
        ? controller.supportedInterfaceOrientations
        : 0;
    return mask != 0 ? mask : GBDeclaredOrientationMask();
}

static BOOL GBAppIsLandscapeOnly(void) {
    const UIInterfaceOrientationMask mask = GBDeclaredOrientationMask();
    const BOOL supportsLandscape = (mask & UIInterfaceOrientationMaskLandscape) != 0;
    const UIInterfaceOrientationMask portraitMask =
        UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskPortraitUpsideDown;
    return supportsLandscape && (mask & portraitMask) == 0;
}

static BOOL GBShouldKeepLandscape(void) {
    return (GBIsGameBoostActive() &&
            gLandscapeLockEnabled.load(std::memory_order_relaxed)) ||
           GBAppIsLandscapeOnly();
}

static UIInterfaceOrientationMask GBLandscapeMask(void) {
    UIInterfaceOrientationMask landscapeMask =
        GBHostOrientationMask() & UIInterfaceOrientationMaskLandscape;
    return landscapeMask != 0 ? landscapeMask : UIInterfaceOrientationMaskLandscape;
}

static BOOL GBMaskContainsOrientation(UIInterfaceOrientationMask mask,
                                      UIInterfaceOrientation orientation) {
    return orientation != UIInterfaceOrientationUnknown &&
           (mask & (1UL << orientation)) != 0;
}

static UIInterfaceOrientation GBPreferredLandscapeOrientation(void) {
    const UIInterfaceOrientationMask mask = GBLandscapeMask();
    UIWindow *hostWindow = GBHostApplicationWindow();
    UIInterfaceOrientation current = UIInterfaceOrientationUnknown;
    if (@available(iOS 13.0, *)) {
        current = hostWindow.windowScene.interfaceOrientation;
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        current = UIApplication.sharedApplication.statusBarOrientation;
#pragma clang diagnostic pop
    }
    if (UIInterfaceOrientationIsLandscape(current) &&
        GBMaskContainsOrientation(mask, current)) {
        return current;
    }

    UIDeviceOrientation deviceOrientation = UIDevice.currentDevice.orientation;
    UIInterfaceOrientation candidate = UIInterfaceOrientationUnknown;
    if (deviceOrientation == UIDeviceOrientationLandscapeLeft) {
        candidate = UIInterfaceOrientationLandscapeRight;
    } else if (deviceOrientation == UIDeviceOrientationLandscapeRight) {
        candidate = UIInterfaceOrientationLandscapeLeft;
    }
    if (GBMaskContainsOrientation(mask, candidate)) {
        return candidate;
    }
    if ((mask & UIInterfaceOrientationMaskLandscapeRight) != 0) {
        return UIInterfaceOrientationLandscapeRight;
    }
    return UIInterfaceOrientationLandscapeLeft;
}

static void GBInstallControllerOrientationOverrides(UIViewController *controller) {
    if (controller == nil ||
        [controller isKindOfClass:NSClassFromString(@"OAGameBoostOverlayViewController")]) {
        return;
    }

    Class controllerClass = object_getClass(controller);

    if (![objc_getAssociatedObject(controllerClass, GBOrientationMaskOverrideKey) boolValue]) {
        SEL selector = @selector(supportedInterfaceOrientations);
        Method method = class_getInstanceMethod(controllerClass, selector);
        IMP original = class_getMethodImplementation(controllerClass, selector);
        const char *types = method_getTypeEncoding(method);
        IMP replacement = imp_implementationWithBlock(^UIInterfaceOrientationMask(id object) {
            using OriginalFunction = UIInterfaceOrientationMask (*)(id, SEL);
            UIInterfaceOrientationMask originalMask =
                ((OriginalFunction)original)(object, selector);
            if (GBShouldKeepLandscape()) {
                UIInterfaceOrientationMask landscapeMask =
                    originalMask & UIInterfaceOrientationMaskLandscape;
                return landscapeMask != 0
                    ? landscapeMask
                    : UIInterfaceOrientationMaskLandscape;
            }
            return originalMask;
        });
        class_replaceMethod(controllerClass, selector, replacement, types);
        objc_setAssociatedObject(controllerClass,
                                 GBOrientationMaskOverrideKey,
                                 @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (![objc_getAssociatedObject(controllerClass, GBAutorotateOverrideKey) boolValue]) {
        SEL selector = @selector(shouldAutorotate);
        Method method = class_getInstanceMethod(controllerClass, selector);
        IMP original = class_getMethodImplementation(controllerClass, selector);
        const char *types = method_getTypeEncoding(method);
        IMP replacement = imp_implementationWithBlock(^BOOL(id object) {
            if (GBShouldKeepLandscape()) {
                return YES;
            }
            using OriginalFunction = BOOL (*)(id, SEL);
            return ((OriginalFunction)original)(object, selector);
        });
        class_replaceMethod(controllerClass, selector, replacement, types);
        objc_setAssociatedObject(controllerClass,
                                 GBAutorotateOverrideKey,
                                 @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (![objc_getAssociatedObject(controllerClass, GBPreferredOrientationOverrideKey) boolValue]) {
        SEL selector = @selector(preferredInterfaceOrientationForPresentation);
        Method method = class_getInstanceMethod(controllerClass, selector);
        IMP original = class_getMethodImplementation(controllerClass, selector);
        const char *types = method_getTypeEncoding(method);
        IMP replacement = imp_implementationWithBlock(^UIInterfaceOrientation(id object) {
            if (GBShouldKeepLandscape()) {
                return GBPreferredLandscapeOrientation();
            }
            using OriginalFunction = UIInterfaceOrientation (*)(id, SEL);
            return ((OriginalFunction)original)(object, selector);
        });
        class_replaceMethod(controllerClass, selector, replacement, types);
        objc_setAssociatedObject(controllerClass,
                                 GBPreferredOrientationOverrideKey,
                                 @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void GBRequestOrientationUpdate(void) {
    dispatch_block_t update = ^{
        UIWindow *hostWindow = GBHostApplicationWindow();
        UIViewController *controller =
            GBTopViewController(hostWindow.rootViewController);
        GBInstallControllerOrientationOverrides(hostWindow.rootViewController);
        GBInstallControllerOrientationOverrides(controller);
        const BOOL keepLandscape = GBShouldKeepLandscape();
        const UIInterfaceOrientationMask requestedMask = keepLandscape
            ? GBLandscapeMask()
            : GBHostOrientationMask();

        if (@available(iOS 16.0, *)) {
            [hostWindow.rootViewController setNeedsUpdateOfSupportedInterfaceOrientations];
            [controller setNeedsUpdateOfSupportedInterfaceOrientations];
            UIWindowScene *windowScene = hostWindow.windowScene;
            if (windowScene != nil && requestedMask != 0) {
                UIWindowSceneGeometryPreferencesIOS *preferences =
                    [[UIWindowSceneGeometryPreferencesIOS alloc]
                        initWithInterfaceOrientations:requestedMask];
                [windowScene requestGeometryUpdateWithPreferences:preferences
                                                      errorHandler:^(__unused NSError *error) {
                }];
            }
        } else {
            if (keepLandscape) {
                @try {
                    [UIDevice.currentDevice
                        setValue:@(GBPreferredLandscapeOrientation())
                          forKey:@"orientation"];
                } @catch (__unused NSException *exception) {
                }
            }
            [UIViewController attemptRotationToDeviceOrientation];
        }
    };

    if (NSThread.isMainThread) {
        update();
    } else {
        dispatch_async(dispatch_get_main_queue(), update);
    }
}

static void GBSetLandscapeLockEnabled(BOOL enabled, BOOL persist) {
    const BOOL oldValue =
        gLandscapeLockEnabled.exchange(enabled, std::memory_order_relaxed);
    if (persist) {
        [NSUserDefaults.standardUserDefaults setBool:enabled forKey:GBLandscapeLockKey];
        [NSUserDefaults.standardUserDefaults synchronize];
    }
    if (oldValue == enabled && !GBAppIsLandscapeOnly()) {
        return;
    }

    GBPostSettingsChanged();
    GBRequestOrientationUpdate();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        GBRequestOrientationUpdate();
    });
}

static void GBApplyResolutionToViewTree(UIView *view, CGFloat screenScale) {
    view.contentScaleFactor = screenScale;

    if ([view isKindOfClass:MTKView.class]) {
        MTKView *metalView = (MTKView *)view;
        CAMetalLayer *metalLayer = (CAMetalLayer *)metalView.layer;
        objc_setAssociatedObject(metalLayer,
                                 GBMetalKitManagedLayerKey,
                                 @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        CGSize targetSize = GBPixelSizeForBounds(metalView.bounds.size);
        if (GBIsUsableSize(targetSize)) {
            // Going through MTKView is important: its delegate receives the new
            // drawable size and can rebuild projection/viewport state. Changing
            // only the underlying CAMetalLayer is what caused the zoom/crop bug.
            metalView.drawableSize = targetSize;
        }
    }

    for (UIView *subview in view.subviews.copy) {
        GBApplyResolutionToViewTree(subview, screenScale);
    }
}

static void GBApplyResolutionToLayerTree(CALayer *layer, CGFloat screenScale) {
    layer.contentsScale = screenScale;

    if ([layer isKindOfClass:CAMetalLayer.class] &&
        ![objc_getAssociatedObject(layer, GBMetalKitManagedLayerKey) boolValue]) {
        CAMetalLayer *metalLayer = (CAMetalLayer *)layer;
        CGSize targetSize = GBPixelSizeForBounds(metalLayer.bounds.size);
        if (GBIsUsableSize(targetSize)) {
            metalLayer.drawableSize = targetSize;
        }
    }

    for (CALayer *sublayer in layer.sublayers.copy) {
        GBApplyResolutionToLayerTree(sublayer, screenScale);
    }
}

static void GBRefreshApplicationResolution(void) {
    dispatch_block_t refresh = ^{
        const CGFloat screenScale = GBCurrentScreenScale();
        for (UIWindow *window in GBApplicationWindows()) {
            if ([objc_getAssociatedObject(window, GBOverlayWindowKey) boolValue]) {
                continue;
            }
            GBApplyResolutionToViewTree(window, screenScale);
            GBApplyResolutionToLayerTree(window.layer, screenScale);
        }
    };

    if (NSThread.isMainThread) {
        refresh();
    } else {
        dispatch_async(dispatch_get_main_queue(), refresh);
    }
}

static void GBSetGameResolutionScale(double scale, BOOL persist) {
    scale = GBClampGameScale(scale);
    const double oldScale =
        gConfiguredResolutionScale.exchange(scale, std::memory_order_relaxed);

    if (fabs(oldScale - scale) < 0.001) {
        return;
    }

    if (persist) {
        [NSUserDefaults.standardUserDefaults setDouble:scale forKey:GBResolutionScaleKey];
        [NSUserDefaults.standardUserDefaults synchronize];
    }
    GBPostSettingsChanged();
}

static void GBSetGraphicsResolutionScale(double scale, BOOL persist) {
    scale = GBClampGraphicsScale(scale);
    const double oldScale =
        gConfiguredGraphicsScale.exchange(scale, std::memory_order_relaxed);
    if (fabs(oldScale - scale) < 0.001) {
        return;
    }
    if (persist) {
        [NSUserDefaults.standardUserDefaults setDouble:scale forKey:GBGraphicsScaleKey];
        [NSUserDefaults.standardUserDefaults synchronize];
    }
    GBPostSettingsChanged();
}

static NSInteger GBEffectiveFrameRate(NSInteger requestedFrameRate) {
    if (!GBIsGameBoostActive()) {
        return requestedFrameRate;
    }
    NSInteger selected = gFrameRate.load(std::memory_order_relaxed);
    if (selected <= 0) {
        return requestedFrameRate;
    }
    return MIN(selected, gMaximumFramesPerSecond);
}

static void GBApplyFrameRateToViewTree(UIView *view) {
    if ([view isKindOfClass:MTKView.class]) {
        MTKView *metalView = (MTKView *)view;
        NSNumber *original = objc_getAssociatedObject(metalView, GBOriginalMTKViewFPSKey);
        if (original == nil) {
            original = @(metalView.preferredFramesPerSecond);
            objc_setAssociatedObject(metalView,
                                     GBOriginalMTKViewFPSKey,
                                     original,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        gApplyingMTKViewFPS = YES;
        metalView.preferredFramesPerSecond =
            GBEffectiveFrameRate(original.integerValue);
        gApplyingMTKViewFPS = NO;
    }
    for (UIView *subview in view.subviews.copy) {
        GBApplyFrameRateToViewTree(subview);
    }
}

static void GBRegisterDisplayLink(CADisplayLink *displayLink) {
    if (displayLink == nil) {
        return;
    }
    @synchronized (gDisplayLinks) {
        [gDisplayLinks addObject:displayLink];
    }
    NSNumber *original = objc_getAssociatedObject(displayLink,
                                                   GBOriginalDisplayLinkFPSKey);
    if (original == nil) {
        original = @(displayLink.preferredFramesPerSecond);
        objc_setAssociatedObject(displayLink,
                                 GBOriginalDisplayLinkFPSKey,
                                 original,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    gApplyingDisplayLinkFPS = YES;
    displayLink.preferredFramesPerSecond =
        GBEffectiveFrameRate(original.integerValue);
    gApplyingDisplayLinkFPS = NO;
}

static void GBRefreshFrameRateTargets(void) {
    dispatch_block_t refresh = ^{
        NSArray<CADisplayLink *> *links = nil;
        @synchronized (gDisplayLinks) {
            links = gDisplayLinks.allObjects;
        }
        for (CADisplayLink *displayLink in links) {
            NSNumber *original = objc_getAssociatedObject(displayLink,
                                                           GBOriginalDisplayLinkFPSKey);
            gApplyingDisplayLinkFPS = YES;
            displayLink.preferredFramesPerSecond =
                GBEffectiveFrameRate(original.integerValue);
            gApplyingDisplayLinkFPS = NO;
        }
        for (UIWindow *window in GBApplicationWindows()) {
            if (!GBIsOverlayWindow(window)) {
                GBApplyFrameRateToViewTree(window);
            }
        }
    };
    if (NSThread.isMainThread) {
        refresh();
    } else {
        dispatch_async(dispatch_get_main_queue(), refresh);
    }
}

static CGColorSpaceRef GBDisplayP3ColorSpace(void) {
    static CGColorSpaceRef colorSpace = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
    });
    return colorSpace;
}

static void GBApplyMetalLayerOptions(CAMetalLayer *layer) {
    if (GBIsPUBGIpadViewActive()) {
        layer.contentsGravity = kCAGravityResizeAspect;
        layer.backgroundColor = UIColor.blackColor.CGColor;
        layer.masksToBounds = YES;
    }

    const BOOL boostLowLatency = GBIsGameBoostActive() &&
        gLowLatencyEnabled.load(std::memory_order_relaxed);
    NSNumber *originalDrawableCount =
        objc_getAssociatedObject(layer, GBOriginalDrawableCountKey);
    if (boostLowLatency) {
        if (originalDrawableCount == nil) {
            objc_setAssociatedObject(layer,
                                     GBOriginalDrawableCountKey,
                                     @(layer.maximumDrawableCount),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (layer.maximumDrawableCount != 2) {
            layer.maximumDrawableCount = 2;
        }
    } else if (originalDrawableCount != nil) {
        layer.maximumDrawableCount = MAX(2, originalDrawableCount.integerValue);
        objc_setAssociatedObject(layer,
                                 GBOriginalDrawableCountKey,
                                 nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    const BOOL graphicsActive = GBIsEnhanceGraphicsActive();
    const BOOL useWideColor = graphicsActive &&
        gWideColorEnabled.load(std::memory_order_relaxed);
    id originalColorSpace = objc_getAssociatedObject(layer,
                                                      GBOriginalMetalColorSpaceKey);
    if (useWideColor) {
        if (originalColorSpace == nil) {
            CGColorSpaceRef current = layer.colorspace;
            objc_setAssociatedObject(layer,
                                     GBOriginalMetalColorSpaceKey,
                                     current != NULL ? (__bridge id)current : NSNull.null,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        CGColorSpaceRef displayP3 = GBDisplayP3ColorSpace();
        if (displayP3 != NULL) {
            layer.colorspace = displayP3;
        }
    } else if (originalColorSpace != nil) {
        layer.colorspace = originalColorSpace == NSNull.null
            ? NULL
            : (__bridge CGColorSpaceRef)originalColorSpace;
        objc_setAssociatedObject(layer,
                                 GBOriginalMetalColorSpaceKey,
                                 nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    const BOOL useHighQualityScaling = graphicsActive &&
        gHighQualityScalingEnabled.load(std::memory_order_relaxed);
    id originalMinFilter = objc_getAssociatedObject(layer,
                                                     GBOriginalMinificationFilterKey);
    id originalMagFilter = objc_getAssociatedObject(layer,
                                                     GBOriginalMagnificationFilterKey);
    if (useHighQualityScaling) {
        if (originalMinFilter == nil) {
            objc_setAssociatedObject(layer,
                                     GBOriginalMinificationFilterKey,
                                     layer.minificationFilter != nil
                                         ? layer.minificationFilter
                                         : NSNull.null,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(layer,
                                     GBOriginalMagnificationFilterKey,
                                     layer.magnificationFilter != nil
                                         ? layer.magnificationFilter
                                         : NSNull.null,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        layer.minificationFilter = kCAFilterTrilinear;
        layer.magnificationFilter = kCAFilterLinear;
    } else if (originalMinFilter != nil || originalMagFilter != nil) {
        layer.minificationFilter = originalMinFilter == NSNull.null
            ? kCAFilterLinear
            : originalMinFilter;
        layer.magnificationFilter = originalMagFilter == NSNull.null
            ? kCAFilterLinear
            : originalMagFilter;
        objc_setAssociatedObject(layer,
                                 GBOriginalMinificationFilterKey,
                                 nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(layer,
                                 GBOriginalMagnificationFilterKey,
                                 nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void GBApplyMetalOptionsToLayerTree(CALayer *layer) {
    if ([layer isKindOfClass:CAMetalLayer.class]) {
        GBApplyMetalLayerOptions((CAMetalLayer *)layer);
    }
    for (CALayer *sublayer in layer.sublayers.copy) {
        GBApplyMetalOptionsToLayerTree(sublayer);
    }
}

static void GBRefreshMetalOptions(void) {
    dispatch_block_t refresh = ^{
        for (UIWindow *window in GBApplicationWindows()) {
            if (!GBIsOverlayWindow(window)) {
                GBApplyMetalOptionsToLayerTree(window.layer);
            }
        }
    };
    if (NSThread.isMainThread) {
        refresh();
    } else {
        dispatch_async(dispatch_get_main_queue(), refresh);
    }
}

static void GBUpdateIdleTimerOverride(void) {
    dispatch_block_t update = ^{
        UIApplication *application = UIApplication.sharedApplication;
        const BOOL shouldKeepAwake = GBIsGameBoostActive() &&
            gKeepAwakeEnabled.load(std::memory_order_relaxed);
        if (shouldKeepAwake && !gIdleTimerOverrideActive) {
            gOriginalIdleTimerDisabled = application.idleTimerDisabled;
            gApplyingIdleTimerOverride = YES;
            application.idleTimerDisabled = YES;
            gApplyingIdleTimerOverride = NO;
            gIdleTimerOverrideActive = YES;
        } else if (!shouldKeepAwake && gIdleTimerOverrideActive) {
            gApplyingIdleTimerOverride = YES;
            application.idleTimerDisabled = gOriginalIdleTimerDisabled;
            gApplyingIdleTimerOverride = NO;
            gIdleTimerOverrideActive = NO;
        }
    };
    if (NSThread.isMainThread) {
        update();
    } else {
        dispatch_async(dispatch_get_main_queue(), update);
    }
}

static void GBSetIpadModeEnabled(BOOL enabled, BOOL persist) {
    gConfiguredIpadModeEnabled.store(enabled, std::memory_order_relaxed);
    if (persist) {
        [NSUserDefaults.standardUserDefaults setBool:enabled
                                              forKey:GBIpadModeEnabledKey];
        [NSUserDefaults.standardUserDefaults synchronize];
    }
    GBPostSettingsChanged();
}

static void GBSetIpadProfile(GBIpadProfile profile, BOOL persist) {
    profile = GBSanitizeIpadProfile(profile);
    gConfiguredIpadProfile.store((int)profile, std::memory_order_relaxed);
    if (persist) {
        [NSUserDefaults.standardUserDefaults setInteger:profile
                                                 forKey:GBIpadProfileKey];
        [NSUserDefaults.standardUserDefaults synchronize];
    }
    GBPostSettingsChanged();
}

static void GBSetModuleMode(GBModuleMode mode, BOOL persist) {
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

static void GBSetFrameRate(NSInteger frameRate, BOOL persist) {
    const int sanitized = GBSanitizeFrameRate(frameRate);
    gFrameRate.store(sanitized, std::memory_order_relaxed);
    if (persist) {
        [NSUserDefaults.standardUserDefaults setInteger:sanitized forKey:GBFrameRateKey];
    }
    GBRefreshFrameRateTargets();
    GBPostSettingsChanged();
}

static void GBSetLowLatencyEnabled(BOOL enabled, BOOL persist) {
    gLowLatencyEnabled.store(enabled, std::memory_order_relaxed);
    if (persist) {
        [NSUserDefaults.standardUserDefaults setBool:enabled forKey:GBLowLatencyKey];
    }
    GBRefreshMetalOptions();
    GBPostSettingsChanged();
}

static void GBSetKeepAwakeEnabled(BOOL enabled, BOOL persist) {
    gKeepAwakeEnabled.store(enabled, std::memory_order_relaxed);
    if (persist) {
        [NSUserDefaults.standardUserDefaults setBool:enabled forKey:GBKeepAwakeKey];
    }
    GBUpdateIdleTimerOverride();
    GBPostSettingsChanged();
}

static void GBSetGraphicsBoolean(std::atomic_bool &storage,
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

static void GBSetAnisotropy(NSInteger level) {
    const int sanitized = GBSanitizeAnisotropy(level);
    gAnisotropyLevel.store(sanitized, std::memory_order_relaxed);
    [NSUserDefaults.standardUserDefaults setInteger:sanitized forKey:GBAnisotropyKey];
    GBPostSettingsChanged();
}

static UIColor *GBThemeColor(void) {
    return [UIColor colorWithHue:(CGFloat)gMenuHue.load(std::memory_order_relaxed)
                      saturation:0.58
                      brightness:0.98
                           alpha:1.0];
}

@interface OAGameBoostPassthroughWindow : UIWindow
@end

@implementation OAGameBoostPassthroughWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self || hitView == self.rootViewController.view) {
        return nil;
    }
    return hitView;
}

- (BOOL)canBecomeKeyWindow {
    return NO;
}

@end


@interface OAGameBoostOverlayViewController : UIViewController <UIGestureRecognizerDelegate>
@property(nonatomic, strong) UIButton *menuButton;
@property(nonatomic, strong) UIVisualEffectView *menuButtonGlass;
@property(nonatomic, strong) UIView *panel;
@property(nonatomic, strong) UIVisualEffectView *glassView;
@property(nonatomic, strong) UIView *glassTintView;
@property(nonatomic, strong) UIView *shineView;
@property(nonatomic, strong) CAGradientLayer *shineGradient;
@property(nonatomic, strong) CAGradientLayer *glassRimGradient;
@property(nonatomic, strong) CAShapeLayer *glassRimMask;
@property(nonatomic, strong) UIView *sidebar;
@property(nonatomic, strong) UIView *gameTabRow;
@property(nonatomic, strong) UIView *graphicsTabRow;
@property(nonatomic, strong) UIView *ipadTabRow;
@property(nonatomic, strong) UIView *settingsTabRow;
@property(nonatomic, strong) UIButton *gameTabButton;
@property(nonatomic, strong) UIButton *graphicsTabButton;
@property(nonatomic, strong) UIButton *ipadTabButton;
@property(nonatomic, strong) UIButton *settingsTabButton;
@property(nonatomic, strong) UISwitch *gameMasterSwitch;
@property(nonatomic, strong) UISwitch *graphicsMasterSwitch;
@property(nonatomic, strong) UISwitch *ipadMasterSwitch;
@property(nonatomic, strong) UIButton *closeButton;
@property(nonatomic, strong) UIScrollView *gameScroll;
@property(nonatomic, strong) UIScrollView *graphicsScroll;
@property(nonatomic, strong) UIScrollView *ipadScroll;
@property(nonatomic, strong) UIScrollView *settingsScroll;
@property(nonatomic, strong) UILabel *gameStatusLabel;
@property(nonatomic, strong) UILabel *graphicsStatusLabel;
@property(nonatomic, strong) UILabel *ipadStatusLabel;
@property(nonatomic, strong) UISegmentedControl *ipadProfileControl;
@property(nonatomic, strong) UILabel *ipadProfileHintLabel;
@property(nonatomic, strong) UISwitch *performanceSwitch;
@property(nonatomic, strong) UISwitch *lowLatencySwitch;
@property(nonatomic, strong) UISwitch *keepAwakeSwitch;
@property(nonatomic, strong) UISwitch *landscapeSwitch;
@property(nonatomic, strong) UILabel *landscapeHintLabel;
@property(nonatomic, strong) UISegmentedControl *fpsControl;
@property(nonatomic, strong) UISlider *scaleSlider;
@property(nonatomic, strong) UILabel *scaleValueLabel;
@property(nonatomic, strong) UILabel *scaleHintLabel;
@property(nonatomic, strong) UISlider *graphicsScaleSlider;
@property(nonatomic, strong) UILabel *graphicsScaleValueLabel;
@property(nonatomic, strong) UILabel *graphicsScaleHintLabel;
@property(nonatomic, strong) UISwitch *linearFilteringSwitch;
@property(nonatomic, strong) UISwitch *trilinearFilteringSwitch;
@property(nonatomic, strong) UISlider *anisotropySlider;
@property(nonatomic, strong) UILabel *anisotropyValueLabel;
@property(nonatomic, strong) UISwitch *wideColorSwitch;
@property(nonatomic, strong) UISwitch *highQualityScalingSwitch;
@property(nonatomic, strong) UISlider *menuScaleSlider;
@property(nonatomic, strong) UILabel *menuScaleValueLabel;
@property(nonatomic, strong) UISwitch *menuDragSwitch;
@property(nonatomic, strong) UISlider *hueSlider;
@property(nonatomic, strong) UISlider *opacitySlider;
@property(nonatomic, strong) UILabel *opacityValueLabel;
@property(nonatomic, strong) UISwitch *liquidGlassSwitch;
@property(nonatomic, strong) UIPanGestureRecognizer *panelPanGesture;
@property(nonatomic, assign) NSInteger selectedTab;
@property(nonatomic, assign) BOOL hasInitialButtonPosition;
@property(nonatomic, assign) BOOL hasPanelPosition;
@end

@implementation OAGameBoostOverlayViewController

- (UILabel *)labelWithText:(NSString *)text
                       frame:(CGRect)frame
                        font:(UIFont *)font
                       color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] initWithFrame:frame];
    label.text = text;
    label.textColor = color;
    label.font = font;
    label.numberOfLines = 0;
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    return label;
}

- (UISwitch *)addSwitchRowTo:(UIScrollView *)scroll
                       title:(NSString *)title
                        hint:(NSString *)hint
                           y:(CGFloat)y
                    selector:(SEL)selector {
    const CGFloat width = CGRectGetWidth(scroll.bounds);
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(10.0,
                                                            y - 7.0,
                                                            width - 20.0,
                                                            66.0)];
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    card.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.040];
    card.layer.cornerRadius = 18.0;
    card.layer.borderWidth = 0.6;
    card.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.075].CGColor;
    card.userInteractionEnabled = NO;
    [scroll addSubview:card];

    UILabel *titleLabel = [self labelWithText:title
                                         frame:CGRectMake(16.0, y, width - 92.0, 24.0)
                                          font:[UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold]
                                         color:UIColor.whiteColor];
    [scroll addSubview:titleLabel];

    UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectMake(width - 67.0,
                                                                  y - 3.0,
                                                                  51.0,
                                                                  31.0)];
    toggle.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [toggle addTarget:self action:selector forControlEvents:UIControlEventValueChanged];
    [scroll addSubview:toggle];

    UILabel *hintLabel = [self labelWithText:hint
                                        frame:CGRectMake(16.0, y + 27.0, width - 32.0, 34.0)
                                         font:[UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular]
                                        color:[UIColor colorWithWhite:0.72 alpha:1.0]];
    [scroll addSubview:hintLabel];
    return toggle;
}

- (UILabel *)addPageTitle:(NSString *)title to:(UIScrollView *)scroll {
    UILabel *label = [self labelWithText:title
                                    frame:CGRectMake(16.0, 12.0,
                                                     CGRectGetWidth(scroll.bounds) - 74.0,
                                                     30.0)
                                     font:[UIFont systemFontOfSize:21.0 weight:UIFontWeightSemibold]
                                    color:UIColor.whiteColor];
    [scroll addSubview:label];
    return label;
}

- (UILabel *)addStatusLabelTo:(UIScrollView *)scroll y:(CGFloat)y {
    UILabel *label = [self labelWithText:@""
                                    frame:CGRectMake(16.0, y,
                                                     CGRectGetWidth(scroll.bounds) - 32.0,
                                                     24.0)
                                     font:[UIFont systemFontOfSize:10.0 weight:UIFontWeightSemibold]
                                    color:UIColor.whiteColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.layer.cornerRadius = 12.0;
    label.layer.borderWidth = 0.6;
    label.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;
    label.layer.masksToBounds = YES;
    [scroll addSubview:label];
    return label;
}

- (UIButton *)sidebarButtonWithTitle:(NSString *)title selector:(SEL)selector {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    button.titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
    button.titleLabel.numberOfLines = 1;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UIVisualEffect *)glassEffectWithTint:(UIColor *)tint interactive:(BOOL)interactive {
    // UIGlassEffect ships with iOS 26, but this project is intentionally built
    // with the iOS 18 SDK as well. Resolve it at runtime so one package can use
    // the real material when available and keep a stable fallback on iOS 12–18.
    Class glassClass = NSClassFromString(@"UIGlassEffect");
    if (glassClass != Nil) {
        id effect = [[glassClass alloc] init];
        @try {
            if ([effect respondsToSelector:NSSelectorFromString(@"setTintColor:")]) {
                [effect setValue:tint forKey:@"tintColor"];
            }
            if ([effect respondsToSelector:NSSelectorFromString(@"setInteractive:")]) {
                [effect setValue:@(interactive) forKey:@"interactive"];
            }
        } @catch (NSException *exception) {
            (void)exception;
        }
        if ([effect isKindOfClass:UIVisualEffect.class]) {
            return (UIVisualEffect *)effect;
        }
    }

    if (@available(iOS 13.0, *)) {
        return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
}

- (void)updateNativeGlassView:(UIVisualEffectView *)effectView
                    tintColor:(UIColor *)tintColor {
    Class glassClass = NSClassFromString(@"UIGlassEffect");
    id effect = effectView.effect;
    if (glassClass == Nil || ![effect isKindOfClass:glassClass]) {
        return;
    }

    @try {
        if ([effect respondsToSelector:NSSelectorFromString(@"setTintColor:")]) {
            [effect setValue:tintColor forKey:@"tintColor"];
        }
    } @catch (NSException *exception) {
        (void)exception;
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    self.selectedTab = GBIsEnhanceGraphicsActive()
        ? 1
        : (gConfiguredIpadModeEnabled.load(std::memory_order_relaxed) ? 2 : 0);

    self.menuButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.menuButton.frame = CGRectMake(16.0, 96.0, 48.0, 48.0);
    self.menuButton.backgroundColor = UIColor.clearColor;
    self.menuButton.layer.cornerRadius = 24.0;
    self.menuButton.layer.borderWidth = 0.75;
    self.menuButton.layer.shadowColor = UIColor.blackColor.CGColor;
    self.menuButton.layer.shadowOpacity = 0.34;
    self.menuButton.layer.shadowRadius = 16.0;
    self.menuButton.layer.shadowOffset = CGSizeMake(0.0, 7.0);
    self.menuButton.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    self.menuButton.accessibilityLabel = @"Open GameBoost menu";
    [self.menuButton setTitle:@"G" forState:UIControlStateNormal];
    [self.menuButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    UIVisualEffect *buttonEffect = [self glassEffectWithTint:
        [GBThemeColor() colorWithAlphaComponent:0.16] interactive:YES];
    self.menuButtonGlass = [[UIVisualEffectView alloc] initWithEffect:buttonEffect];
    self.menuButtonGlass.frame = self.menuButton.bounds;
    self.menuButtonGlass.autoresizingMask = UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;
    self.menuButtonGlass.userInteractionEnabled = NO;
    self.menuButtonGlass.layer.cornerRadius = 24.0;
    self.menuButtonGlass.layer.masksToBounds = YES;
    [self.menuButton insertSubview:self.menuButtonGlass atIndex:0];
    [self.menuButton addTarget:self action:@selector(togglePanel)
              forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *buttonPan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragMenuButton:)];
    buttonPan.delegate = self;
    [self.menuButton addGestureRecognizer:buttonPan];
    [self.view addSubview:self.menuButton];

    self.panel = [[UIView alloc] initWithFrame:CGRectMake(76.0, 80.0, 510.0, 370.0)];
    self.panel.layer.cornerRadius = 28.0;
    self.panel.layer.borderWidth = 0.75;
    self.panel.layer.masksToBounds = NO;
    self.panel.layer.shadowColor = UIColor.blackColor.CGColor;
    self.panel.layer.shadowOpacity = 0.42;
    self.panel.layer.shadowRadius = 28.0;
    self.panel.layer.shadowOffset = CGSizeMake(0.0, 14.0);
    self.panel.hidden = YES;
    [self.view addSubview:self.panel];

    UIVisualEffect *panelEffect = [self glassEffectWithTint:
        [GBThemeColor() colorWithAlphaComponent:0.12] interactive:NO];
    self.glassView = [[UIVisualEffectView alloc] initWithEffect:panelEffect];
    self.glassView.userInteractionEnabled = NO;
    self.glassView.layer.cornerRadius = 28.0;
    self.glassView.layer.masksToBounds = YES;
    [self.panel addSubview:self.glassView];

    self.glassTintView = [[UIView alloc] initWithFrame:self.panel.bounds];
    self.glassTintView.userInteractionEnabled = NO;
    self.glassTintView.layer.cornerRadius = 28.0;
    self.glassTintView.layer.masksToBounds = YES;
    [self.panel addSubview:self.glassTintView];

    self.shineView = [[UIView alloc] initWithFrame:self.panel.bounds];
    self.shineView.userInteractionEnabled = NO;
    self.shineView.layer.cornerRadius = 28.0;
    self.shineView.layer.masksToBounds = YES;
    self.shineGradient = [CAGradientLayer layer];
    self.shineGradient.startPoint = CGPointMake(0.0, 0.0);
    self.shineGradient.endPoint = CGPointMake(1.0, 1.0);
    [self.shineView.layer addSublayer:self.shineGradient];

    self.glassRimGradient = [CAGradientLayer layer];
    self.glassRimGradient.startPoint = CGPointMake(0.0, 0.0);
    self.glassRimGradient.endPoint = CGPointMake(1.0, 1.0);
    self.glassRimMask = [CAShapeLayer layer];
    self.glassRimMask.fillColor = UIColor.clearColor.CGColor;
    self.glassRimMask.strokeColor = UIColor.whiteColor.CGColor;
    self.glassRimMask.lineWidth = 1.35;
    self.glassRimGradient.mask = self.glassRimMask;
    [self.shineView.layer addSublayer:self.glassRimGradient];
    [self.panel addSubview:self.shineView];

    self.sidebar = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 148.0, 370.0)];
    self.sidebar.layer.cornerRadius = 28.0;
    self.sidebar.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner;
    self.sidebar.layer.masksToBounds = YES;
    self.sidebar.layer.borderWidth = 0.5;
    self.sidebar.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.08].CGColor;
    [self.panel addSubview:self.sidebar];

    UILabel *brandLabel = [self labelWithText:@"GameBoost\n3.2 • Liquid"
                                         frame:CGRectMake(16.0, 12.0, 112.0, 38.0)
                                          font:[UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold]
                                         color:UIColor.whiteColor];
    brandLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.sidebar addSubview:brandLabel];

    self.gameTabRow = [UIView new];
    self.gameTabRow.layer.cornerRadius = 14.0;
    [self.sidebar addSubview:self.gameTabRow];
    self.gameTabButton = [self sidebarButtonWithTitle:@"Boost"
                                             selector:@selector(selectGameTab)];
    [self.gameTabRow addSubview:self.gameTabButton];
    self.gameMasterSwitch = [UISwitch new];
    [self.gameMasterSwitch addTarget:self
                              action:@selector(gameMasterChanged:)
                    forControlEvents:UIControlEventValueChanged];
    [self.gameTabRow addSubview:self.gameMasterSwitch];

    self.graphicsTabRow = [UIView new];
    self.graphicsTabRow.layer.cornerRadius = 14.0;
    [self.sidebar addSubview:self.graphicsTabRow];
    self.graphicsTabButton = [self sidebarButtonWithTitle:@"Graphics"
                                                 selector:@selector(selectGraphicsTab)];
    [self.graphicsTabRow addSubview:self.graphicsTabButton];
    self.graphicsMasterSwitch = [UISwitch new];
    [self.graphicsMasterSwitch addTarget:self
                                  action:@selector(graphicsMasterChanged:)
                        forControlEvents:UIControlEventValueChanged];
    [self.graphicsTabRow addSubview:self.graphicsMasterSwitch];

    self.ipadTabRow = [UIView new];
    self.ipadTabRow.layer.cornerRadius = 14.0;
    [self.sidebar addSubview:self.ipadTabRow];
    self.ipadTabButton = [self sidebarButtonWithTitle:@"Spoof"
                                             selector:@selector(selectIpadTab)];
    [self.ipadTabRow addSubview:self.ipadTabButton];
    self.ipadMasterSwitch = [UISwitch new];
    [self.ipadMasterSwitch addTarget:self
                              action:@selector(ipadMasterChanged:)
                    forControlEvents:UIControlEventValueChanged];
    [self.ipadTabRow addSubview:self.ipadMasterSwitch];

    self.settingsTabRow = [UIView new];
    self.settingsTabRow.layer.cornerRadius = 14.0;
    [self.sidebar addSubview:self.settingsTabRow];
    self.settingsTabButton = [self sidebarButtonWithTitle:@"Settings"
                                                 selector:@selector(selectSettingsTab)];
    [self.settingsTabRow addSubview:self.settingsTabButton];

    CGRect pageFrame = CGRectMake(148.0, 0.0, 362.0, 370.0);
    self.gameScroll = [[UIScrollView alloc] initWithFrame:pageFrame];
    self.graphicsScroll = [[UIScrollView alloc] initWithFrame:pageFrame];
    self.ipadScroll = [[UIScrollView alloc] initWithFrame:pageFrame];
    self.settingsScroll = [[UIScrollView alloc] initWithFrame:pageFrame];
    for (UIScrollView *scroll in @[self.gameScroll,
                                   self.graphicsScroll,
                                   self.ipadScroll,
                                   self.settingsScroll]) {
        scroll.alwaysBounceVertical = YES;
        scroll.showsVerticalScrollIndicator = YES;
        scroll.backgroundColor = UIColor.clearColor;
        [self.panel addSubview:scroll];
    }

    [self buildGamePage];
    [self buildGraphicsPage];
    [self buildIpadPage];
    [self buildSettingsPage];

    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeButton.frame = CGRectMake(432.0, 4.0, 44.0, 44.0);
    self.closeButton.titleLabel.font = [UIFont systemFontOfSize:24.0 weight:UIFontWeightRegular];
    self.closeButton.accessibilityLabel = @"Close GameBoost menu";
    [self.closeButton setTitle:@"×" forState:UIControlStateNormal];
    [self.closeButton setTitleColor:[UIColor colorWithWhite:0.88 alpha:1.0]
                           forState:UIControlStateNormal];
    [self.closeButton addTarget:self action:@selector(hidePanel)
               forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:self.closeButton];

    self.panelPanGesture =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPanel:)];
    self.panelPanGesture.delegate = self;
    [self.panel addGestureRecognizer:self.panelPanGesture];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(settingsDidChange)
                                               name:GBSettingsDidChangeNotification
                                             object:nil];
    [self settingsDidChange];
}

- (void)buildGamePage {
    const CGFloat width = CGRectGetWidth(self.gameScroll.bounds);
    [self addPageTitle:@"GameBoost" to:self.gameScroll];
    self.gameStatusLabel = [self addStatusLabelTo:self.gameScroll y:48.0];

    self.performanceSwitch = [self addSwitchRowTo:self.gameScroll
                                            title:@"Performance QoS"
                                             hint:@"Ưu tiên thread render; không còn tự tắt theo nhiệt."
                                                y:84.0
                                         selector:@selector(performanceSwitchChanged:)];
    self.lowLatencySwitch = [self addSwitchRowTo:self.gameScroll
                                           title:@"Low latency 2-buffer"
                                            hint:@"Giảm hàng đợi Metal; thử tắt nếu game bị khựng."
                                               y:154.0
                                        selector:@selector(lowLatencySwitchChanged:)];
    self.keepAwakeSwitch = [self addSwitchRowTo:self.gameScroll
                                          title:@"Giữ màn hình sáng"
                                           hint:@"Không cho máy tự khóa khi đang chơi."
                                              y:224.0
                                       selector:@selector(keepAwakeSwitchChanged:)];
    self.landscapeSwitch = [self addSwitchRowTo:self.gameScroll
                                          title:@"Khóa ngang game"
                                           hint:@""
                                              y:294.0
                                       selector:@selector(landscapeSwitchChanged:)];
    self.landscapeHintLabel = (UILabel *)self.gameScroll.subviews.lastObject;

    UILabel *fpsLabel = [self labelWithText:@"Giới hạn / ưu tiên FPS"
                                       frame:CGRectMake(16.0, 368.0, width - 32.0, 22.0)
                                        font:[UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold]
                                       color:UIColor.whiteColor];
    [self.gameScroll addSubview:fpsLabel];
    self.fpsControl = [[UISegmentedControl alloc] initWithItems:@[@"Auto", @"30", @"60", @"120"]];
    self.fpsControl.frame = CGRectMake(16.0, 397.0, width - 32.0, 32.0);
    self.fpsControl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.fpsControl addTarget:self action:@selector(fpsChanged:)
              forControlEvents:UIControlEventValueChanged];
    [self.gameScroll addSubview:self.fpsControl];
    UILabel *fpsHint = [self labelWithText:@"120 chỉ áp dụng khi màn hình và game hỗ trợ."
                                      frame:CGRectMake(16.0, 434.0, width - 32.0, 20.0)
                                       font:[UIFont systemFontOfSize:11.0]
                                      color:[UIColor colorWithWhite:0.69 alpha:1.0]];
    [self.gameScroll addSubview:fpsHint];

    UILabel *scaleLabel = [self labelWithText:@"Độ phân giải app"
                                         frame:CGRectMake(16.0, 466.0, width - 100.0, 24.0)
                                          font:[UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold]
                                         color:UIColor.whiteColor];
    [self.gameScroll addSubview:scaleLabel];
    self.scaleValueLabel = [self labelWithText:@"100%"
                                         frame:CGRectMake(width - 82.0, 466.0, 66.0, 24.0)
                                          font:[UIFont monospacedDigitSystemFontOfSize:14.0 weight:UIFontWeightSemibold]
                                         color:UIColor.whiteColor];
    self.scaleValueLabel.textAlignment = NSTextAlignmentRight;
    self.scaleValueLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.gameScroll addSubview:self.scaleValueLabel];
    self.scaleSlider = [[UISlider alloc] initWithFrame:CGRectMake(16.0, 495.0, width - 32.0, 30.0)];
    self.scaleSlider.minimumValue = 0.1f;
    self.scaleSlider.maximumValue = 1.0f;
    self.scaleSlider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.scaleSlider addTarget:self action:@selector(scaleSliderChanged:)
               forControlEvents:UIControlEventValueChanged];
    [self.gameScroll addSubview:self.scaleSlider];
    self.scaleHintLabel = [self labelWithText:@""
                                        frame:CGRectMake(16.0, 528.0, width - 32.0, 34.0)
                                         font:[UIFont systemFontOfSize:11.0]
                                        color:[UIColor colorWithWhite:0.69 alpha:1.0]];
    [self.gameScroll addSubview:self.scaleHintLabel];
    UIButton *resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    resetButton.frame = CGRectMake(16.0, 570.0, width - 32.0, 34.0);
    resetButton.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    resetButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.09];
    resetButton.layer.cornerRadius = 9.0;
    [resetButton setTitle:@"Đặt lại độ phân giải 100%" forState:UIControlStateNormal];
    [resetButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [resetButton addTarget:self action:@selector(resetGameScale)
          forControlEvents:UIControlEventTouchUpInside];
    [self.gameScroll addSubview:resetButton];
    self.gameScroll.contentSize = CGSizeMake(width, 622.0);
}

- (void)buildGraphicsPage {
    const CGFloat width = CGRectGetWidth(self.graphicsScroll.bounds);
    [self addPageTitle:@"Enhance Graphic" to:self.graphicsScroll];
    self.graphicsStatusLabel = [self addStatusLabelTo:self.graphicsScroll y:48.0];

    UILabel *scaleLabel = [self labelWithText:@"Super Resolution"
                                         frame:CGRectMake(16.0, 86.0, width - 100.0, 24.0)
                                          font:[UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold]
                                         color:UIColor.whiteColor];
    [self.graphicsScroll addSubview:scaleLabel];
    self.graphicsScaleValueLabel = [self labelWithText:@"100%"
                                                 frame:CGRectMake(width - 82.0, 86.0, 66.0, 24.0)
                                                  font:[UIFont monospacedDigitSystemFontOfSize:14.0 weight:UIFontWeightSemibold]
                                                 color:UIColor.whiteColor];
    self.graphicsScaleValueLabel.textAlignment = NSTextAlignmentRight;
    self.graphicsScaleValueLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.graphicsScroll addSubview:self.graphicsScaleValueLabel];
    self.graphicsScaleSlider = [[UISlider alloc] initWithFrame:CGRectMake(16.0, 115.0, width - 32.0, 30.0)];
    self.graphicsScaleSlider.minimumValue = 1.0f;
    self.graphicsScaleSlider.maximumValue = 1.5f;
    self.graphicsScaleSlider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.graphicsScaleSlider addTarget:self action:@selector(graphicsScaleChanged:)
                       forControlEvents:UIControlEventValueChanged];
    [self.graphicsScroll addSubview:self.graphicsScaleSlider];
    self.graphicsScaleHintLabel = [self labelWithText:@""
                                                frame:CGRectMake(16.0, 148.0, width - 32.0, 38.0)
                                                 font:[UIFont systemFontOfSize:11.0]
                                                color:[UIColor colorWithWhite:0.69 alpha:1.0]];
    [self.graphicsScroll addSubview:self.graphicsScaleHintLabel];

    self.linearFilteringSwitch = [self addSwitchRowTo:self.graphicsScroll
                                                title:@"Linear texture filter"
                                                 hint:@"Làm mượt phóng/thu texture trên Metal."
                                                    y:196.0
                                             selector:@selector(linearFilteringChanged:)];
    self.trilinearFilteringSwitch = [self addSwitchRowTo:self.graphicsScroll
                                                   title:@"Trilinear mip filter"
                                                    hint:@"Chuyển mipmap mượt hơn ở vật thể xa."
                                                       y:266.0
                                                selector:@selector(trilinearFilteringChanged:)];

    UILabel *anisoLabel = [self labelWithText:@"Anisotropic filtering"
                                         frame:CGRectMake(16.0, 340.0, width - 100.0, 24.0)
                                          font:[UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold]
                                         color:UIColor.whiteColor];
    [self.graphicsScroll addSubview:anisoLabel];
    self.anisotropyValueLabel = [self labelWithText:@"4×"
                                              frame:CGRectMake(width - 82.0, 340.0, 66.0, 24.0)
                                               font:[UIFont monospacedDigitSystemFontOfSize:14.0 weight:UIFontWeightSemibold]
                                              color:UIColor.whiteColor];
    self.anisotropyValueLabel.textAlignment = NSTextAlignmentRight;
    self.anisotropyValueLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.graphicsScroll addSubview:self.anisotropyValueLabel];
    self.anisotropySlider = [[UISlider alloc] initWithFrame:CGRectMake(16.0, 369.0, width - 32.0, 30.0)];
    self.anisotropySlider.minimumValue = 0.0f;
    self.anisotropySlider.maximumValue = 4.0f;
    self.anisotropySlider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.anisotropySlider addTarget:self action:@selector(anisotropyChanged:)
                     forControlEvents:UIControlEventValueChanged];
    [self.graphicsScroll addSubview:self.anisotropySlider];
    UILabel *anisoHint = [self labelWithText:@"1× / 2× / 4× / 8× / 16× • pipeline tạo mới"
                                        frame:CGRectMake(16.0, 401.0, width - 32.0, 24.0)
                                         font:[UIFont systemFontOfSize:11.0]
                                        color:[UIColor colorWithWhite:0.69 alpha:1.0]];
    [self.graphicsScroll addSubview:anisoHint];

    self.wideColorSwitch = [self addSwitchRowTo:self.graphicsScroll
                                          title:@"Display-P3 output"
                                           hint:@"Dải màu rộng cho CAMetalLayer khi màn hình hỗ trợ."
                                              y:438.0
                                       selector:@selector(wideColorChanged:)];
    self.highQualityScalingSwitch = [self addSwitchRowTo:self.graphicsScroll
                                                   title:@"High-quality layer scaling"
                                                    hint:@"Dùng lọc trilinear khi Metal layer được scale."
                                                       y:508.0
                                                selector:@selector(highQualityScalingChanged:)];
    UILabel *compatibility = [self labelWithText:@"Lưu ý: hiệu quả tùy engine. Tweak không ép shader, texture pack hay MSAA vì có thể làm game crash."
                                             frame:CGRectMake(16.0, 580.0, width - 32.0, 52.0)
                                              font:[UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium]
                                             color:[UIColor colorWithRed:1.0 green:0.76 blue:0.36 alpha:1.0]];
    [self.graphicsScroll addSubview:compatibility];
    self.graphicsScroll.contentSize = CGSizeMake(width, 644.0);
}

- (void)buildIpadPage {
    const CGFloat width = CGRectGetWidth(self.ipadScroll.bounds);
    [self addPageTitle:@"Device Spoof" to:self.ipadScroll];
    self.ipadStatusLabel = [self addStatusLabelTo:self.ipadScroll y:48.0];

    UILabel *intro = [self labelWithText:@"Mỗi preset dùng metrics riêng; đổi xong phải đóng hẳn rồi mở lại game."
                                    frame:CGRectMake(16.0, 82.0, width - 32.0, 42.0)
                                     font:[UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium]
                                    color:[UIColor colorWithWhite:0.82 alpha:1.0]];
    [self.ipadScroll addSubview:intro];

    UIView *profileCard = [[UIView alloc] initWithFrame:CGRectMake(10.0,
                                                                   130.0,
                                                                   width - 20.0,
                                                                   196.0)];
    profileCard.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    profileCard.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.040];
    profileCard.layer.cornerRadius = 18.0;
    profileCard.layer.borderWidth = 0.6;
    profileCard.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.075].CGColor;
    profileCard.userInteractionEnabled = NO;
    [self.ipadScroll addSubview:profileCard];

    UILabel *profileLabel = [self labelWithText:@"Game adapter"
                                           frame:CGRectMake(18.0, 144.0, width - 36.0, 24.0)
                                            font:[UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold]
                                           color:UIColor.whiteColor];
    [self.ipadScroll addSubview:profileLabel];

    self.ipadProfileControl = [[UISegmentedControl alloc]
        initWithItems:@[@"Roblox Tablet", @"PUBG 4:3 Fit"]];
    self.ipadProfileControl.frame = CGRectMake(18.0, 176.0, width - 36.0, 34.0);
    self.ipadProfileControl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.ipadProfileControl addTarget:self
                                action:@selector(ipadProfileChanged:)
                      forControlEvents:UIControlEventValueChanged];
    [self.ipadScroll addSubview:self.ipadProfileControl];

    self.ipadProfileHintLabel = [self labelWithText:@""
                                                frame:CGRectMake(18.0,
                                                                 220.0,
                                                                 width - 36.0,
                                                                 94.0)
                                                 font:[UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular]
                                                color:[UIColor colorWithWhite:0.72 alpha:1.0]];
    [self.ipadScroll addSubview:self.ipadProfileHintLabel];

    UILabel *relaunch = [self labelWithText:@"↻ Bắt buộc force-close game. Bật/tắt giữa phiên chỉ lưu cấu hình cho lần mở kế tiếp."
                                         frame:CGRectMake(16.0, 340.0, width - 32.0, 48.0)
                                          font:[UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium]
                                         color:[UIColor colorWithRed:1.0 green:0.78 blue:0.42 alpha:1.0]];
    [self.ipadScroll addSubview:relaunch];

    UIButton *resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    resetButton.frame = CGRectMake(16.0, 398.0, width - 32.0, 36.0);
    resetButton.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    resetButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.070];
    resetButton.layer.cornerRadius = 14.0;
    resetButton.layer.borderWidth = 0.6;
    resetButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;
    [resetButton setTitle:@"Khôi phục thiết bị thật" forState:UIControlStateNormal];
    [resetButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [resetButton addTarget:self action:@selector(resetIpadMode)
          forControlEvents:UIControlEventTouchUpInside];
    [self.ipadScroll addSubview:resetButton];
    self.ipadScroll.contentSize = CGSizeMake(width, 454.0);
}

- (void)buildSettingsPage {
    const CGFloat width = CGRectGetWidth(self.settingsScroll.bounds);
    [self addPageTitle:@"Settings" to:self.settingsScroll];

    UILabel *sizeLabel = [self labelWithText:@"Kích thước menu"
                                        frame:CGRectMake(16.0, 62.0, width - 100.0, 24.0)
                                         font:[UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold]
                                        color:UIColor.whiteColor];
    [self.settingsScroll addSubview:sizeLabel];
    self.menuScaleValueLabel = [self labelWithText:@"100%"
                                             frame:CGRectMake(width - 82.0, 62.0, 66.0, 24.0)
                                              font:[UIFont monospacedDigitSystemFontOfSize:14.0 weight:UIFontWeightSemibold]
                                             color:UIColor.whiteColor];
    self.menuScaleValueLabel.textAlignment = NSTextAlignmentRight;
    self.menuScaleValueLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.settingsScroll addSubview:self.menuScaleValueLabel];
    self.menuScaleSlider = [[UISlider alloc] initWithFrame:CGRectMake(16.0, 91.0, width - 32.0, 30.0)];
    self.menuScaleSlider.minimumValue = 0.75f;
    self.menuScaleSlider.maximumValue = 1.25f;
    self.menuScaleSlider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.menuScaleSlider addTarget:self action:@selector(menuScaleChanged:)
                    forControlEvents:UIControlEventValueChanged];
    [self.settingsScroll addSubview:self.menuScaleSlider];

    self.menuDragSwitch = [self addSwitchRowTo:self.settingsScroll
                                         title:@"Cho phép kéo menu"
                                          hint:@"Tắt để panel luôn cố định giữa màn hình."
                                             y:142.0
                                      selector:@selector(menuDragChanged:)];

    UILabel *hueLabel = [self labelWithText:@"Màu chủ đề"
                                       frame:CGRectMake(16.0, 218.0, width - 32.0, 24.0)
                                        font:[UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold]
                                       color:UIColor.whiteColor];
    [self.settingsScroll addSubview:hueLabel];
    self.hueSlider = [[UISlider alloc] initWithFrame:CGRectMake(16.0, 247.0, width - 32.0, 30.0)];
    self.hueSlider.minimumValue = 0.0f;
    self.hueSlider.maximumValue = 1.0f;
    self.hueSlider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.hueSlider addTarget:self action:@selector(hueChanged:)
              forControlEvents:UIControlEventValueChanged];
    [self.settingsScroll addSubview:self.hueSlider];

    UILabel *opacityLabel = [self labelWithText:@"Độ đậm của kính"
                                           frame:CGRectMake(16.0, 298.0, width - 100.0, 24.0)
                                            font:[UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold]
                                           color:UIColor.whiteColor];
    [self.settingsScroll addSubview:opacityLabel];
    self.opacityValueLabel = [self labelWithText:@"96%"
                                           frame:CGRectMake(width - 82.0, 298.0, 66.0, 24.0)
                                            font:[UIFont monospacedDigitSystemFontOfSize:14.0 weight:UIFontWeightSemibold]
                                           color:UIColor.whiteColor];
    self.opacityValueLabel.textAlignment = NSTextAlignmentRight;
    self.opacityValueLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.settingsScroll addSubview:self.opacityValueLabel];
    self.opacitySlider = [[UISlider alloc] initWithFrame:CGRectMake(16.0, 327.0, width - 32.0, 30.0)];
    self.opacitySlider.minimumValue = 0.45f;
    self.opacitySlider.maximumValue = 1.0f;
    self.opacitySlider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.opacitySlider addTarget:self action:@selector(opacityChanged:)
                  forControlEvents:UIControlEventValueChanged];
    [self.settingsScroll addSubview:self.opacitySlider];

    self.liquidGlassSwitch = [self addSwitchRowTo:self.settingsScroll
                                            title:@"Liquid Glass 26"
                                             hint:@"Kính nổi, tint động và viền phản quang • fallback iOS 12–18."
                                                y:380.0
                                         selector:@selector(liquidGlassChanged:)];
    UILabel *settingsHint = [self labelWithText:@"Settings luôn hoạt động, kể cả khi hai module đang tắt."
                                            frame:CGRectMake(16.0, 456.0, width - 32.0, 36.0)
                                             font:[UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium]
                                            color:[UIColor colorWithWhite:0.69 alpha:1.0]];
    [self.settingsScroll addSubview:settingsHint];
    self.settingsScroll.contentSize = CGSizeMake(width, 510.0);
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return GBShouldKeepLandscape() ? GBLandscapeMask() : GBHostOrientationMask();
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    if (GBShouldKeepLandscape()) {
        return GBPreferredLandscapeOrientation();
    }
    UIWindow *hostWindow = GBHostApplicationWindow();
    UIViewController *hostController = GBTopViewController(hostWindow.rootViewController);
    UIInterfaceOrientation preferred =
        hostController.preferredInterfaceOrientationForPresentation;
    const UIInterfaceOrientationMask mask = GBHostOrientationMask();
    if (GBMaskContainsOrientation(mask, preferred)) {
        return preferred;
    }
    if ((mask & UIInterfaceOrientationMaskPortrait) != 0) {
        return UIInterfaceOrientationPortrait;
    }
    return GBPreferredLandscapeOrientation();
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.hasInitialButtonPosition) {
        self.menuButton.center = CGPointMake(41.0,
            MAX(108.0, self.view.safeAreaInsets.top + 38.0));
        self.hasInitialButtonPosition = YES;
    }
    [self clampMenuButton];
    [self layoutPanel];
}

- (void)layoutPanel {
    CGRect safeBounds = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    const CGFloat margin = 8.0;
    const CGFloat scale = (CGFloat)gMenuScale.load(std::memory_order_relaxed);
    const CGFloat maxWidth = MAX(1.0, CGRectGetWidth(safeBounds) - margin * 2.0);
    const CGFloat maxHeight = MAX(1.0, CGRectGetHeight(safeBounds) - margin * 2.0);
    const CGFloat width = MIN(maxWidth, MAX(MIN(350.0, maxWidth), 510.0 * scale));
    const CGFloat height = MIN(maxHeight, MAX(MIN(270.0, maxHeight), 370.0 * scale));

    CGPoint center = self.panel.center;
    if (!self.hasPanelPosition || !gMenuDragEnabled.load(std::memory_order_relaxed)) {
        center = CGPointMake(CGRectGetMidX(safeBounds), CGRectGetMidY(safeBounds));
        self.hasPanelPosition = YES;
    }
    self.panel.bounds = CGRectMake(0.0, 0.0, width, height);
    self.panel.center = center;
    [self clampPanel];

    self.glassView.frame = self.panel.bounds;
    self.glassTintView.frame = self.panel.bounds;
    self.shineView.frame = self.panel.bounds;
    self.shineGradient.frame = self.shineView.bounds;
    self.glassRimGradient.frame = self.shineView.bounds;
    CGRect rimRect = CGRectInset(self.shineView.bounds, 0.75, 0.75);
    self.glassRimMask.frame = self.shineView.bounds;
    self.glassRimMask.path = [UIBezierPath bezierPathWithRoundedRect:rimRect
                                                       cornerRadius:27.25].CGPath;
    const CGFloat sidebarWidth = MIN(154.0, MAX(136.0, width * 0.30));
    self.sidebar.frame = CGRectMake(0.0, 0.0, sidebarWidth, height);

    self.gameTabRow.frame = CGRectMake(8.0, 54.0, sidebarWidth - 16.0, 48.0);
    self.graphicsTabRow.frame = CGRectMake(8.0, 108.0, sidebarWidth - 16.0, 48.0);
    self.ipadTabRow.frame = CGRectMake(8.0, 162.0, sidebarWidth - 16.0, 48.0);
    self.settingsTabRow.frame = CGRectMake(8.0,
                                           MIN(216.0, height - 54.0),
                                           sidebarWidth - 16.0,
                                           46.0);
    CGFloat rowWidth = CGRectGetWidth(self.gameTabRow.bounds);
    self.gameTabButton.frame = CGRectMake(8.0, 0.0, MAX(40.0, rowWidth - 58.0), 48.0);
    self.gameMasterSwitch.frame = CGRectMake(MAX(0.0, rowWidth - 52.0), 8.0, 51.0, 31.0);
    rowWidth = CGRectGetWidth(self.graphicsTabRow.bounds);
    self.graphicsTabButton.frame = CGRectMake(8.0, 0.0, MAX(40.0, rowWidth - 58.0), 48.0);
    self.graphicsMasterSwitch.frame = CGRectMake(MAX(0.0, rowWidth - 52.0), 8.0, 51.0, 31.0);
    rowWidth = CGRectGetWidth(self.ipadTabRow.bounds);
    self.ipadTabButton.frame = CGRectMake(8.0, 0.0, MAX(40.0, rowWidth - 58.0), 48.0);
    self.ipadMasterSwitch.frame = CGRectMake(MAX(0.0, rowWidth - 52.0), 8.0, 51.0, 31.0);
    self.settingsTabButton.frame = CGRectMake(8.0, 0.0,
                                              CGRectGetWidth(self.settingsTabRow.bounds) - 16.0,
                                              46.0);

    CGRect pageFrame = CGRectMake(sidebarWidth, 0.0, width - sidebarWidth, height);
    for (UIScrollView *scroll in @[self.gameScroll,
                                   self.graphicsScroll,
                                   self.ipadScroll,
                                   self.settingsScroll]) {
        scroll.frame = pageFrame;
        scroll.contentSize = CGSizeMake(CGRectGetWidth(pageFrame), scroll.contentSize.height);
        scroll.scrollIndicatorInsets = UIEdgeInsetsMake(45.0, 0.0, 8.0, 2.0);
    }
    self.closeButton.frame = CGRectMake(width - 46.0, 2.0, 44.0, 44.0);
}

- (void)clampPanel {
    CGRect safeBounds = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    const CGFloat margin = 8.0;
    CGFloat halfWidth = CGRectGetWidth(self.panel.bounds) / 2.0;
    CGFloat halfHeight = CGRectGetHeight(self.panel.bounds) / 2.0;
    CGFloat minX = CGRectGetMinX(safeBounds) + halfWidth + margin;
    CGFloat maxX = CGRectGetMaxX(safeBounds) - halfWidth - margin;
    CGFloat minY = CGRectGetMinY(safeBounds) + halfHeight + margin;
    CGFloat maxY = CGRectGetMaxY(safeBounds) - halfHeight - margin;
    self.panel.center = CGPointMake(minX > maxX ? CGRectGetMidX(safeBounds)
                                                : MIN(MAX(self.panel.center.x, minX), maxX),
                                    minY > maxY ? CGRectGetMidY(safeBounds)
                                                : MIN(MAX(self.panel.center.y, minY), maxY));
}

- (void)clampMenuButton {
    CGRect bounds = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    const CGFloat halfWidth = CGRectGetWidth(self.menuButton.bounds) / 2.0;
    const CGFloat halfHeight = CGRectGetHeight(self.menuButton.bounds) / 2.0;
    CGFloat minX = CGRectGetMinX(bounds) + halfWidth + 8.0;
    CGFloat maxX = CGRectGetMaxX(bounds) - halfWidth - 8.0;
    CGFloat minY = CGRectGetMinY(bounds) + halfHeight + 8.0;
    CGFloat maxY = CGRectGetMaxY(bounds) - halfHeight - 8.0;
    self.menuButton.center = CGPointMake(MIN(MAX(self.menuButton.center.x, minX), maxX),
                                         MIN(MAX(self.menuButton.center.y, minY), maxY));
}

- (void)applyTintToView:(UIView *)view color:(UIColor *)color {
    if ([view isKindOfClass:UISwitch.class]) {
        ((UISwitch *)view).onTintColor = color;
    } else if ([view isKindOfClass:UISlider.class]) {
        ((UISlider *)view).minimumTrackTintColor = color;
    } else if ([view isKindOfClass:UISegmentedControl.class]) {
        UISegmentedControl *control = (UISegmentedControl *)view;
        if (@available(iOS 13.0, *)) {
            control.selectedSegmentTintColor = color;
        } else {
            control.tintColor = color;
        }
    }
    for (UIView *subview in view.subviews) {
        [self applyTintToView:subview color:color];
    }
}

- (void)applyVisualSettings {
    UIColor *theme = GBThemeColor();
    const CGFloat density = (CGFloat)fmin(1.0, fmax(0.45,
        gMenuOpacity.load(std::memory_order_relaxed)));
    const CGFloat strength = (density - 0.45) / 0.55;
    const BOOL glass = gLiquidGlassEnabled.load(std::memory_order_relaxed);

    // Never fade the whole hierarchy: doing that leaves the blur fully opaque
    // while dimming every control above it. The slider now changes the glass
    // layers themselves, so tint and density update immediately and separately.
    self.panel.alpha = 1.0;
    self.menuButton.layer.borderColor =
        [UIColor colorWithWhite:1.0 alpha:0.34].CGColor;
    self.panel.layer.borderColor =
        [UIColor colorWithWhite:1.0 alpha:0.24].CGColor;
    self.panel.layer.shadowOpacity = glass ? 0.38 : 0.46;
    self.sidebar.backgroundColor = glass
        ? [UIColor colorWithWhite:0.0 alpha:0.10 + 0.07 * strength]
        : [UIColor colorWithWhite:0.0 alpha:0.23];
    [self applyTintToView:self.panel color:theme];

    self.gameTabRow.backgroundColor = self.selectedTab == 0
        ? [theme colorWithAlphaComponent:0.13]
        : UIColor.clearColor;
    self.graphicsTabRow.backgroundColor = self.selectedTab == 1
        ? [theme colorWithAlphaComponent:0.13]
        : UIColor.clearColor;
    self.ipadTabRow.backgroundColor = self.selectedTab == 2
        ? [theme colorWithAlphaComponent:0.13]
        : UIColor.clearColor;
    self.settingsTabRow.backgroundColor = self.selectedTab == 3
        ? [theme colorWithAlphaComponent:0.13]
        : UIColor.clearColor;
    for (UIView *tabRow in @[self.gameTabRow,
                             self.graphicsTabRow,
                             self.ipadTabRow,
                             self.settingsTabRow]) {
        const BOOL selected = (tabRow == self.gameTabRow && self.selectedTab == 0) ||
            (tabRow == self.graphicsTabRow && self.selectedTab == 1) ||
            (tabRow == self.ipadTabRow && self.selectedTab == 2) ||
            (tabRow == self.settingsTabRow && self.selectedTab == 3);
        tabRow.layer.borderWidth = 0.6;
        tabRow.layer.borderColor = selected
            ? [UIColor colorWithWhite:1.0 alpha:0.17].CGColor
            : UIColor.clearColor.CGColor;
    }
    self.gameStatusLabel.backgroundColor = GBIsGameBoostActive()
        ? [theme colorWithAlphaComponent:0.18]
        : [UIColor colorWithWhite:1.0 alpha:0.055];
    self.graphicsStatusLabel.backgroundColor = GBIsEnhanceGraphicsActive()
        ? [theme colorWithAlphaComponent:0.18]
        : [UIColor colorWithWhite:1.0 alpha:0.055];
    self.ipadStatusLabel.backgroundColor =
        gConfiguredIpadModeEnabled.load(std::memory_order_relaxed)
            ? [theme colorWithAlphaComponent:0.18]
            : [UIColor colorWithWhite:1.0 alpha:0.055];
    self.scaleValueLabel.textColor = theme;
    self.graphicsScaleValueLabel.textColor = theme;
    self.anisotropyValueLabel.textColor = theme;
    self.menuScaleValueLabel.textColor = theme;
    self.opacityValueLabel.textColor = theme;

    self.glassView.hidden = !glass;
    self.glassTintView.hidden = !glass;
    self.shineView.hidden = !glass;
    self.menuButtonGlass.hidden = !glass;
    self.glassView.alpha = 0.58 + 0.34 * strength;
    self.menuButtonGlass.alpha = 0.66 + 0.28 * strength;
    self.shineView.alpha = 0.72 + 0.26 * strength;
    UIColor *nativeTint = [theme colorWithAlphaComponent:0.09 + 0.11 * strength];
    [self updateNativeGlassView:self.glassView tintColor:nativeTint];
    [self updateNativeGlassView:self.menuButtonGlass
                      tintColor:[theme colorWithAlphaComponent:0.14 + 0.10 * strength]];

    self.menuButton.backgroundColor = glass
        ? [theme colorWithAlphaComponent:0.045 + 0.07 * strength]
        : [UIColor colorWithWhite:0.055 alpha:0.90 + 0.08 * strength];
    self.panel.backgroundColor = glass
        ? [UIColor colorWithWhite:0.025 alpha:0.11 + 0.10 * strength]
        : [UIColor colorWithWhite:0.040 alpha:0.82 + 0.16 * strength];
    self.glassTintView.backgroundColor =
        [theme colorWithAlphaComponent:0.025 + 0.095 * strength];
    self.shineGradient.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:0.27].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.060].CGColor,
        (id)UIColor.clearColor.CGColor,
        (id)[UIColor colorWithWhite:0.0 alpha:0.10].CGColor
    ];
    self.shineGradient.locations = @[@0.0, @0.18, @0.56, @1.0];
    self.glassRimGradient.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:0.74].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.10].CGColor,
        (id)[theme colorWithAlphaComponent:0.22].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.42].CGColor
    ];
    self.glassRimGradient.locations = @[@0.0, @0.27, @0.70, @1.0];
}

- (void)settingsDidChange {
    const GBModuleMode mode = GBCurrentModuleMode();
    self.gameMasterSwitch.on = mode == GBModuleModeGameBoost;
    self.graphicsMasterSwitch.on = mode == GBModuleModeEnhanceGraphics;
    const BOOL configuredIpadMode =
        gConfiguredIpadModeEnabled.load(std::memory_order_relaxed);
    const GBIpadProfile configuredIpadProfile = GBSanitizeIpadProfile(
        gConfiguredIpadProfile.load(std::memory_order_relaxed));
    self.ipadMasterSwitch.on = configuredIpadMode;
    self.gameScroll.userInteractionEnabled = mode == GBModuleModeGameBoost;
    self.graphicsScroll.userInteractionEnabled = mode == GBModuleModeEnhanceGraphics;
    self.ipadScroll.userInteractionEnabled = configuredIpadMode;
    self.gameScroll.alpha = mode == GBModuleModeGameBoost ? 1.0 : 0.34;
    self.graphicsScroll.alpha = mode == GBModuleModeEnhanceGraphics ? 1.0 : 0.34;
    self.ipadScroll.alpha = configuredIpadMode ? 1.0 : 0.42;
    self.gameStatusLabel.text = mode == GBModuleModeGameBoost
        ? @"● MODULE ĐANG BẬT"
        : @"MODULE ĐÃ KHÓA • BẬT Ở BÊN TRÁI";
    self.graphicsStatusLabel.text = mode == GBModuleModeEnhanceGraphics
        ? @"● MODULE ĐANG BẬT"
        : @"MODULE ĐÃ KHÓA • BẬT Ở BÊN TRÁI";
    const BOOL ipadNeedsRelaunch =
        configuredIpadMode != gLaunchedIpadModeEnabled ||
        (configuredIpadMode && configuredIpadProfile != gLaunchedIpadProfile);
    if (configuredIpadMode) {
        self.ipadStatusLabel.text = ipadNeedsRelaunch
            ? @"● ĐÃ LƯU • FORCE-CLOSE APP ↻"
            : @"● DEVICE SPOOF ĐANG BẬT";
    } else {
        self.ipadStatusLabel.text = ipadNeedsRelaunch
            ? @"ĐÃ TẮT • FORCE-CLOSE APP ↻"
            : @"MODULE ĐÃ KHÓA • BẬT Ở BÊN TRÁI";
    }
    self.ipadProfileControl.selectedSegmentIndex =
        configuredIpadProfile == GBIpadProfilePUBGView ? 1 : 0;
    self.ipadProfileHintLabel.text = configuredIpadProfile == GBIpadProfilePUBGView
        ? @"PUBG: giả iPad Pro + regular traits, render surface 4:3 và Aspect Fit khi compose. Có viền hai bên để giữ đúng tỉ lệ, không kéo giãn/zoom như bản cũ."
        : @"Roblox: giả iPad + regular traits và tăng logical viewport cùng tỉ lệ lên trên 1024×500. Mục tiêu là full hotbar và player list, không đổi aspect màn hình.";
    self.performanceSwitch.on = gPerformanceEnabled.load(std::memory_order_relaxed);
    self.lowLatencySwitch.on = gLowLatencyEnabled.load(std::memory_order_relaxed);
    self.keepAwakeSwitch.on = gKeepAwakeEnabled.load(std::memory_order_relaxed);
    self.landscapeSwitch.on = gLandscapeLockEnabled.load(std::memory_order_relaxed);
    self.landscapeHintLabel.text = GBAppIsLandscapeOnly()
        ? @"Game chỉ hỗ trợ ngang • tự giữ đúng hướng."
        : @"Vẫn nằm ngang khi khóa xoay hệ thống đang bật.";
    NSInteger frameRate = gFrameRate.load(std::memory_order_relaxed);
    self.fpsControl.selectedSegmentIndex = frameRate == 30 ? 1
        : frameRate == 60 ? 2
        : frameRate == 120 ? 3
        : 0;

    const double gameScale = gConfiguredResolutionScale.load(std::memory_order_relaxed);
    self.scaleSlider.value = (float)gameScale;
    const BOOL gameNeedsRelaunch = mode == GBModuleModeGameBoost &&
        (gLaunchedModuleMode != GBModuleModeGameBoost ||
         fabs(gResolutionScale.load(std::memory_order_relaxed) - gameScale) >= 0.001);
    self.scaleValueLabel.text = [NSString stringWithFormat:@"%.0f%%%@",
        gameScale * 100.0, gameNeedsRelaunch ? @"↻" : @""];
    if (gameNeedsRelaunch) {
        self.scaleHintLabel.text = @"Đã lưu • đóng/mở lại app để áp dụng an toàn.";
    } else if (gameScale <= 0.25) {
        self.scaleHintLabel.text = @"10–25% rất mờ • menu vẫn giữ độ nét gốc.";
    } else {
        self.scaleHintLabel.text = @"Giảm pixel thật, giữ nguyên khung hình • không zoom.";
    }

    const double graphicsScale = gConfiguredGraphicsScale.load(std::memory_order_relaxed);
    self.graphicsScaleSlider.value = (float)graphicsScale;
    const BOOL graphicsNeedsRelaunch = mode == GBModuleModeEnhanceGraphics &&
        (gLaunchedModuleMode != GBModuleModeEnhanceGraphics ||
         fabs(gResolutionScale.load(std::memory_order_relaxed) - graphicsScale) >= 0.001);
    self.graphicsScaleValueLabel.text = [NSString stringWithFormat:@"%.0f%%%@",
        graphicsScale * 100.0, graphicsNeedsRelaunch ? @"↻" : @""];
    self.graphicsScaleHintLabel.text = graphicsNeedsRelaunch
        ? @"Đã lưu • đóng/mở lại app để đổi framebuffer."
        : @"Render 100–150% rồi downsample; tốn GPU và RAM hơn.";
    self.linearFilteringSwitch.on = gLinearFilteringEnabled.load(std::memory_order_relaxed);
    self.trilinearFilteringSwitch.on = gTrilinearFilteringEnabled.load(std::memory_order_relaxed);
    const int anisotropy = gAnisotropyLevel.load(std::memory_order_relaxed);
    self.anisotropySlider.value = anisotropy == 16 ? 4.0f
        : anisotropy == 8 ? 3.0f
        : anisotropy == 4 ? 2.0f
        : anisotropy == 2 ? 1.0f
        : 0.0f;
    self.anisotropyValueLabel.text = [NSString stringWithFormat:@"%d×", anisotropy];
    self.wideColorSwitch.on = gWideColorEnabled.load(std::memory_order_relaxed);
    self.highQualityScalingSwitch.on =
        gHighQualityScalingEnabled.load(std::memory_order_relaxed);

    self.menuScaleSlider.value = (float)gMenuScale.load(std::memory_order_relaxed);
    self.menuScaleValueLabel.text = [NSString stringWithFormat:@"%.0f%%",
        gMenuScale.load(std::memory_order_relaxed) * 100.0];
    self.menuDragSwitch.on = gMenuDragEnabled.load(std::memory_order_relaxed);
    self.panelPanGesture.enabled = self.menuDragSwitch.isOn;
    self.hueSlider.value = (float)gMenuHue.load(std::memory_order_relaxed);
    self.opacitySlider.value = (float)gMenuOpacity.load(std::memory_order_relaxed);
    self.opacityValueLabel.text = [NSString stringWithFormat:@"%.0f%%",
        gMenuOpacity.load(std::memory_order_relaxed) * 100.0];
    self.liquidGlassSwitch.on = gLiquidGlassEnabled.load(std::memory_order_relaxed);

    self.gameScroll.hidden = self.selectedTab != 0;
    self.graphicsScroll.hidden = self.selectedTab != 1;
    self.ipadScroll.hidden = self.selectedTab != 2;
    self.settingsScroll.hidden = self.selectedTab != 3;
    [self.panel bringSubviewToFront:self.closeButton];
    [self applyVisualSettings];
    [self.view setNeedsLayout];
}

- (void)selectGameTab {
    self.selectedTab = 0;
    [self settingsDidChange];
}

- (void)selectGraphicsTab {
    self.selectedTab = 1;
    [self settingsDidChange];
}

- (void)selectSettingsTab {
    self.selectedTab = 3;
    [self settingsDidChange];
}

- (void)selectIpadTab {
    self.selectedTab = 2;
    [self settingsDidChange];
}

- (void)gameMasterChanged:(UISwitch *)sender {
    GBSetModuleMode(sender.isOn ? GBModuleModeGameBoost : GBModuleModeNone, YES);
}

- (void)graphicsMasterChanged:(UISwitch *)sender {
    GBSetModuleMode(sender.isOn ? GBModuleModeEnhanceGraphics : GBModuleModeNone, YES);
}

- (void)ipadMasterChanged:(UISwitch *)sender {
    GBSetIpadModeEnabled(sender.isOn, YES);
}

- (void)ipadProfileChanged:(UISegmentedControl *)sender {
    GBSetIpadProfile(sender.selectedSegmentIndex == 1
        ? GBIpadProfilePUBGView
        : GBIpadProfileRobloxTablet, YES);
}

- (void)resetIpadMode {
    GBSetIpadProfile(GBIpadProfileRobloxTablet, YES);
    GBSetIpadModeEnabled(NO, YES);
}

- (void)performanceSwitchChanged:(UISwitch *)sender {
    GBSetPerformanceEnabled(sender.isOn, YES);
}

- (void)lowLatencySwitchChanged:(UISwitch *)sender {
    GBSetLowLatencyEnabled(sender.isOn, YES);
}

- (void)keepAwakeSwitchChanged:(UISwitch *)sender {
    GBSetKeepAwakeEnabled(sender.isOn, YES);
}

- (void)landscapeSwitchChanged:(UISwitch *)sender {
    GBSetLandscapeLockEnabled(sender.isOn, YES);
}

- (void)fpsChanged:(UISegmentedControl *)sender {
    NSInteger values[] = {0, 30, 60, 120};
    NSInteger index = MIN(MAX(sender.selectedSegmentIndex, 0), 3);
    GBSetFrameRate(values[index], YES);
}

- (void)scaleSliderChanged:(UISlider *)sender {
    GBSetGameResolutionScale(round((double)sender.value * 20.0) / 20.0, YES);
}

- (void)resetGameScale {
    GBSetGameResolutionScale(1.0, YES);
}

- (void)graphicsScaleChanged:(UISlider *)sender {
    GBSetGraphicsResolutionScale(round((double)sender.value * 20.0) / 20.0, YES);
}

- (void)linearFilteringChanged:(UISwitch *)sender {
    GBSetGraphicsBoolean(gLinearFilteringEnabled, GBLinearFilteringKey, sender.isOn, NO);
}

- (void)trilinearFilteringChanged:(UISwitch *)sender {
    GBSetGraphicsBoolean(gTrilinearFilteringEnabled, GBTrilinearFilteringKey, sender.isOn, NO);
}

- (void)anisotropyChanged:(UISlider *)sender {
    const NSInteger index = (NSInteger)round(sender.value);
    const NSInteger values[] = {1, 2, 4, 8, 16};
    GBSetAnisotropy(values[MIN(MAX(index, 0), 4)]);
}

- (void)wideColorChanged:(UISwitch *)sender {
    GBSetGraphicsBoolean(gWideColorEnabled, GBWideColorKey, sender.isOn, YES);
}

- (void)highQualityScalingChanged:(UISwitch *)sender {
    GBSetGraphicsBoolean(gHighQualityScalingEnabled,
                         GBHighQualityScalingKey,
                         sender.isOn,
                         YES);
}

- (void)menuScaleChanged:(UISlider *)sender {
    const double value = GBClampMenuScale(round((double)sender.value * 20.0) / 20.0);
    gMenuScale.store(value, std::memory_order_relaxed);
    [NSUserDefaults.standardUserDefaults setDouble:value forKey:GBMenuScaleKey];
    GBPostSettingsChanged();
}

- (void)menuDragChanged:(UISwitch *)sender {
    gMenuDragEnabled.store(sender.isOn, std::memory_order_relaxed);
    [NSUserDefaults.standardUserDefaults setBool:sender.isOn forKey:GBMenuDragKey];
    if (!sender.isOn) {
        self.hasPanelPosition = NO;
    }
    GBPostSettingsChanged();
}

- (void)hueChanged:(UISlider *)sender {
    const double value = GBClampUnit(sender.value, 0.55);
    gMenuHue.store(value, std::memory_order_relaxed);
    [NSUserDefaults.standardUserDefaults setDouble:value forKey:GBMenuHueKey];
    GBPostSettingsChanged();
}

- (void)opacityChanged:(UISlider *)sender {
    const double value = fmin(1.0, fmax(0.45, (double)sender.value));
    gMenuOpacity.store(value, std::memory_order_relaxed);
    [NSUserDefaults.standardUserDefaults setDouble:value forKey:GBMenuOpacityKey];
    GBPostSettingsChanged();
}

- (void)liquidGlassChanged:(UISwitch *)sender {
    gLiquidGlassEnabled.store(sender.isOn, std::memory_order_relaxed);
    [NSUserDefaults.standardUserDefaults setBool:sender.isOn forKey:GBLiquidGlassKey];
    GBPostSettingsChanged();
}

- (void)togglePanel {
    if (!self.panel.hidden) {
        [self hidePanel];
        return;
    }

    [self.panel.layer removeAllAnimations];
    self.panel.hidden = NO;
    self.panel.alpha = 0.0;
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    [UIView animateWithDuration:0.22
                          delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState |
                                UIViewAnimationOptionAllowUserInteraction |
                                UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.panel.alpha = 1.0;
    } completion:nil];
}

- (void)hidePanel {
    if (self.panel.hidden) {
        return;
    }
    [UIView animateWithDuration:0.16
                          delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState |
                                UIViewAnimationOptionAllowUserInteraction |
                                UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self.panel.alpha = 0.0;
    } completion:^(__unused BOOL finished) {
        self.panel.hidden = YES;
        self.panel.alpha = 1.0;
    }];
}

- (void)dragMenuButton:(UIPanGestureRecognizer *)gesture {
    if (!gMenuDragEnabled.load(std::memory_order_relaxed)) {
        return;
    }
    CGPoint translation = [gesture translationInView:self.view];
    self.menuButton.center = CGPointMake(self.menuButton.center.x + translation.x,
                                         self.menuButton.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:self.view];
    [self clampMenuButton];
}

- (void)dragPanel:(UIPanGestureRecognizer *)gesture {
    if (!gMenuDragEnabled.load(std::memory_order_relaxed)) {
        return;
    }
    CGPoint translation = [gesture translationInView:self.view];
    self.panel.center = CGPointMake(self.panel.center.x + translation.x,
                                    self.panel.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:self.view];
    self.hasPanelPosition = YES;
    [self clampPanel];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
       shouldReceiveTouch:(UITouch *)touch {
    if (!gMenuDragEnabled.load(std::memory_order_relaxed)) {
        return NO;
    }
    if (gestureRecognizer == self.panelPanGesture) {
        UIView *view = touch.view;
        while (view != nil && view != self.panel) {
            if ([view isKindOfClass:UIControl.class] ||
                [view isKindOfClass:UIScrollView.class]) {
                return NO;
            }
            view = view.superview;
        }
    }
    return YES;
}

@end

@interface OAGameBoostOverlayManager : NSObject
@property(nonatomic, strong) OAGameBoostPassthroughWindow *overlayWindow;
+ (instancetype)sharedManager;
- (UIWindowScene *)activeWindowScene API_AVAILABLE(ios(13.0));
- (void)installIfPossible;
@end


@implementation OAGameBoostOverlayManager

+ (instancetype)sharedManager {
    static OAGameBoostOverlayManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [OAGameBoostOverlayManager new];
    });
    return manager;
}

- (UIWindowScene *)activeWindowScene {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class] &&
                scene.activationState == UISceneActivationStateForegroundActive) {
                return (UIWindowScene *)scene;
            }
        }
    }
    return nil;
}

- (void)installIfPossible {
    if (self.overlayWindow != nil) {
        return;
    }

    if (@available(iOS 13.0, *)) {
        UIWindowScene *windowScene = [self activeWindowScene];
        if (windowScene == nil) {
            return;
        }
        self.overlayWindow = [[OAGameBoostPassthroughWindow alloc] initWithWindowScene:windowScene];
        self.overlayWindow.frame = windowScene.coordinateSpace.bounds;
    } else {
        self.overlayWindow = [[OAGameBoostPassthroughWindow alloc]
            initWithFrame:gOriginalMainScreenBounds];
    }
    self.overlayWindow.backgroundColor = UIColor.clearColor;
    // Keep the tweak above the game but below system alert windows.
    self.overlayWindow.windowLevel = UIWindowLevelAlert - 1.0;
    objc_setAssociatedObject(self.overlayWindow,
                             GBOverlayWindowKey,
                             @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    self.overlayWindow.rootViewController = [OAGameBoostOverlayViewController new];
    self.overlayWindow.hidden = NO;

    // The control panel stays at the device's native backing scale. It is not
    // part of the app/game framebuffer being downscaled.
    GBApplyResolutionToViewTree(self.overlayWindow, gOriginalMainScreenScale);
    GBApplyResolutionToLayerTree(self.overlayWindow.layer, gOriginalMainScreenScale);
}

@end


%hook UIApplication

- (void)setIdleTimerDisabled:(BOOL)idleTimerDisabled {
    if (gIdleTimerOverrideActive && !gApplyingIdleTimerOverride) {
        gOriginalIdleTimerDisabled = idleTimerDisabled;
        %orig(YES);
        return;
    }
    %orig(idleTimerDisabled);
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    UIInterfaceOrientationMask originalMask = %orig(window);
    if (GBShouldKeepLandscape()) {
        UIWindow *hostWindow = GBHostApplicationWindow();
        UIViewController *topController =
            GBTopViewController(hostWindow.rootViewController);
        GBInstallControllerOrientationOverrides(hostWindow.rootViewController);
        GBInstallControllerOrientationOverrides(topController);
        return GBLandscapeMask();
    }
    if (GBIsOverlayWindow(window)) {
        UIInterfaceOrientationMask hostMask = GBHostOrientationMask();
        return hostMask != 0 ? hostMask : originalMask;
    }
    return originalMask;
}

%end


%hook UIDevice

- (UIUserInterfaceIdiom)userInterfaceIdiom {
    return GBIsIpadModeActive() ? UIUserInterfaceIdiomPad : %orig;
}

- (NSString *)model {
    return GBIsIpadModeActive() ? @"iPad" : %orig;
}

- (NSString *)localizedModel {
    return GBIsIpadModeActive() ? @"iPad" : %orig;
}

%end


%hook UITraitCollection

- (UIUserInterfaceIdiom)userInterfaceIdiom {
    return GBIsIpadModeActive() ? UIUserInterfaceIdiomPad : %orig;
}

- (UIUserInterfaceSizeClass)horizontalSizeClass {
    return GBIsIpadModeActive() ? UIUserInterfaceSizeClassRegular : %orig;
}

- (UIUserInterfaceSizeClass)verticalSizeClass {
    return GBIsIpadModeActive() ? UIUserInterfaceSizeClassRegular : %orig;
}

- (CGFloat)displayScale {
    return GBIsRobloxTabletActive() ? GBCurrentScreenScale() : %orig;
}

%end


%hook UITouch

- (CGPoint)locationInView:(UIView *)view {
    return GBRemapPUBGTouchPoint(%orig(view), view);
}

- (CGPoint)previousLocationInView:(UIView *)view {
    return GBRemapPUBGTouchPoint(%orig(view), view);
}

%end


%hook UIScreen

- (CGRect)bounds {
    CGRect bounds = self == gMainScreen ? gOriginalMainScreenBounds : %orig;
    if (self == gMainScreen && GBIsRobloxTabletActive()) {
        bounds.size = GBRobloxVirtualLogicalSize(bounds.size);
    }
    return bounds;
}

- (CGFloat)scale {
    if (self == gMainScreen) {
        return GBCurrentScreenScale();
    }
    return MAX(0.1, %orig *
        (CGFloat)gResolutionScale.load(std::memory_order_relaxed));
}

- (CGFloat)nativeScale {
    if (self == gMainScreen) {
        const CGFloat virtualFactor = GBRobloxLogicalScaleFactor(
            gOriginalMainScreenBounds.size);
        return MAX(0.1, (gOriginalMainNativeScale / virtualFactor) *
            (CGFloat)gResolutionScale.load(std::memory_order_relaxed));
    }
    return MAX(0.1, %orig *
        (CGFloat)gResolutionScale.load(std::memory_order_relaxed));
}

- (CGRect)nativeBounds {
    CGRect bounds = gOriginalMainNativeBounds;
    if (self != gMainScreen) {
        bounds = %orig;
    }
    const CGFloat factor =
        (CGFloat)gResolutionScale.load(std::memory_order_relaxed);
    bounds.size.width = MAX(1.0, round(bounds.size.width * factor));
    bounds.size.height = MAX(1.0, round(bounds.size.height * factor));
    return bounds;
}

%end


%hook UIScreenMode

- (CGSize)size {
    CGSize size = gOriginalMainScreenModeSize;
    if (self != gMainScreenMode) {
        size = %orig;
    }
    const CGFloat factor =
        (CGFloat)gResolutionScale.load(std::memory_order_relaxed);
    size.width = MAX(1.0, round(size.width * factor));
    size.height = MAX(1.0, round(size.height * factor));
    return size;
}

%end


%hook MTKView

- (void)setPreferredFramesPerSecond:(NSInteger)preferredFramesPerSecond {
    if (!gApplyingMTKViewFPS) {
        objc_setAssociatedObject(self,
                                 GBOriginalMTKViewFPSKey,
                                 @(preferredFramesPerSecond),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    %orig(gApplyingMTKViewFPS
        ? preferredFramesPerSecond
        : GBEffectiveFrameRate(preferredFramesPerSecond));
}

- (void)setDrawableSize:(CGSize)drawableSize {
    CAMetalLayer *metalLayer = (CAMetalLayer *)self.layer;
    objc_setAssociatedObject(metalLayer,
                             GBMetalKitManagedLayerKey,
                             @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (!GBIsUsableSize(drawableSize)) {
        %orig(drawableSize);
        return;
    }

    if (GBIsPUBGIpadViewActive()) {
        self.contentMode = UIViewContentModeScaleAspectFit;
        GBApplyMetalLayerOptions(metalLayer);
    }

    if (fabs(gResolutionScale.load(std::memory_order_relaxed) - 1.0) < 0.001 &&
        !GBIsPUBGIpadViewActive()) {
        %orig(drawableSize);
        return;
    }

    CGSize targetSize = GBPixelSizeForBounds(self.bounds.size);
    %orig(GBIsUsableSize(targetSize) ? targetSize : drawableSize);
}

%end


%hook CADisplayLink

+ (CADisplayLink *)displayLinkWithTarget:(id)target selector:(SEL)selector {
    CADisplayLink *displayLink = %orig(target, selector);
    GBRegisterDisplayLink(displayLink);
    return displayLink;
}

- (void)setPreferredFramesPerSecond:(NSInteger)preferredFramesPerSecond {
    if (!gApplyingDisplayLinkFPS) {
        objc_setAssociatedObject(self,
                                 GBOriginalDisplayLinkFPSKey,
                                 @(preferredFramesPerSecond),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    %orig(gApplyingDisplayLinkFPS
        ? preferredFramesPerSecond
        : GBEffectiveFrameRate(preferredFramesPerSecond));
}

%end


%hook CAMetalLayer

- (void)setDrawableSize:(CGSize)drawableSize {
    if (!GBIsUsableSize(drawableSize)) {
        %orig(drawableSize);
        return;
    }

    if (GBIsPUBGIpadViewActive()) {
        GBApplyMetalLayerOptions(self);
    }

    if (fabs(gResolutionScale.load(std::memory_order_relaxed) - 1.0) < 0.001 &&
        !GBIsPUBGIpadViewActive()) {
        %orig(drawableSize);
        return;
    }

    CGSize targetSize = GBPixelSizeForBounds(self.bounds.size);
    %orig(GBIsUsableSize(targetSize) ? targetSize : drawableSize);
}

- (id)nextDrawable {
    GBApplyMetalLayerOptions(self);
    GBApplyQoSToCurrentRenderThread();
    return %orig;
}

%end


%hook MTLSamplerDescriptor

- (instancetype)init {
    MTLSamplerDescriptor *descriptor = %orig;
    if (descriptor != nil && GBIsEnhanceGraphicsActive()) {
        if (gLinearFilteringEnabled.load(std::memory_order_relaxed)) {
            descriptor.minFilter = MTLSamplerMinMagFilterLinear;
            descriptor.magFilter = MTLSamplerMinMagFilterLinear;
        }
        if (gTrilinearFilteringEnabled.load(std::memory_order_relaxed)) {
            descriptor.mipFilter = MTLSamplerMipFilterLinear;
        }
        descriptor.maxAnisotropy =
            (NSUInteger)gAnisotropyLevel.load(std::memory_order_relaxed);
    }
    return descriptor;
}

- (void)setMinFilter:(MTLSamplerMinMagFilter)minFilter {
    if (!gApplyingSamplerSettings) {
        objc_setAssociatedObject(self,
                                 GBRequestedSamplerMinKey,
                                 @(minFilter),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!self.normalizedCoordinates) {
        %orig(minFilter);
        if (!gApplyingSamplerSettings) {
            gApplyingSamplerSettings = YES;
            self.magFilter = minFilter;
            self.mipFilter = MTLSamplerMipFilterNotMipmapped;
            self.maxAnisotropy = 1;
            gApplyingSamplerSettings = NO;
        }
        return;
    }
    if (!gApplyingSamplerSettings && GBIsEnhanceGraphicsActive() &&
        gLinearFilteringEnabled.load(std::memory_order_relaxed) &&
        self.normalizedCoordinates) {
        minFilter = MTLSamplerMinMagFilterLinear;
    }
    %orig(minFilter);
}

- (void)setMagFilter:(MTLSamplerMinMagFilter)magFilter {
    if (!gApplyingSamplerSettings) {
        objc_setAssociatedObject(self,
                                 GBRequestedSamplerMagKey,
                                 @(magFilter),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!self.normalizedCoordinates) {
        %orig(magFilter);
        if (!gApplyingSamplerSettings) {
            gApplyingSamplerSettings = YES;
            self.minFilter = magFilter;
            self.mipFilter = MTLSamplerMipFilterNotMipmapped;
            self.maxAnisotropy = 1;
            gApplyingSamplerSettings = NO;
        }
        return;
    }
    if (!gApplyingSamplerSettings && GBIsEnhanceGraphicsActive() &&
        gLinearFilteringEnabled.load(std::memory_order_relaxed) &&
        self.normalizedCoordinates) {
        magFilter = MTLSamplerMinMagFilterLinear;
    }
    %orig(magFilter);
}

- (void)setMipFilter:(MTLSamplerMipFilter)mipFilter {
    if (!gApplyingSamplerSettings) {
        objc_setAssociatedObject(self,
                                 GBRequestedSamplerMipKey,
                                 @(mipFilter),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!self.normalizedCoordinates) {
        mipFilter = MTLSamplerMipFilterNotMipmapped;
    } else if (!gApplyingSamplerSettings && GBIsEnhanceGraphicsActive() &&
        gTrilinearFilteringEnabled.load(std::memory_order_relaxed) &&
        self.normalizedCoordinates) {
        mipFilter = MTLSamplerMipFilterLinear;
    }
    %orig(mipFilter);
}

- (void)setMaxAnisotropy:(NSUInteger)maxAnisotropy {
    if (!gApplyingSamplerSettings) {
        objc_setAssociatedObject(self,
                                 GBRequestedSamplerAnisotropyKey,
                                 @(maxAnisotropy),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!self.normalizedCoordinates) {
        maxAnisotropy = 1;
    } else if (!gApplyingSamplerSettings && GBIsEnhanceGraphicsActive() &&
        self.normalizedCoordinates) {
        maxAnisotropy = MAX(maxAnisotropy,
            (NSUInteger)gAnisotropyLevel.load(std::memory_order_relaxed));
    }
    %orig(maxAnisotropy);
}

- (void)setNormalizedCoordinates:(BOOL)normalizedCoordinates {
    %orig(normalizedCoordinates);
    if (normalizedCoordinates) {
        return;
    }

    // Metal requires non-normalized samplers to use matching min/mag filters,
    // no mip filtering and anisotropy 1. Restore a safe form of the game's
    // requested descriptor instead of leaving the graphics override invalid.
    NSNumber *requestedMin = objc_getAssociatedObject(self, GBRequestedSamplerMinKey);
    NSNumber *requestedMag = objc_getAssociatedObject(self, GBRequestedSamplerMagKey);
    MTLSamplerMinMagFilter safeFilter = requestedMin != nil
        ? (MTLSamplerMinMagFilter)requestedMin.unsignedIntegerValue
        : requestedMag != nil
            ? (MTLSamplerMinMagFilter)requestedMag.unsignedIntegerValue
            : MTLSamplerMinMagFilterNearest;
    gApplyingSamplerSettings = YES;
    self.minFilter = safeFilter;
    self.magFilter = safeFilter;
    self.mipFilter = MTLSamplerMipFilterNotMipmapped;
    self.maxAnisotropy = 1;
    gApplyingSamplerSettings = NO;
}

%end


%hookf(int, sysctlbyname, const char *name, void *oldValue, size_t *oldLength, void *newValue, size_t newLength) {
    if (GBIsIpadModeActive() && newValue == nullptr && name != nullptr &&
        std::strcmp(name, "hw.machine") == 0) {
        return GBWriteSpoofedCString(GBIpadMachineIdentifier(),
                                     oldValue,
                                     oldLength);
    }
    return %orig;
}


%hookf(int, uname, struct utsname *systemInfo) {
    int result = %orig;
    if (result == 0 && GBIsIpadModeActive() && systemInfo != nullptr) {
        const char *identifier = GBIpadMachineIdentifier();
        std::memset(systemInfo->machine, 0, sizeof(systemInfo->machine));
        std::strncpy(systemInfo->machine,
                     identifier,
                     sizeof(systemInfo->machine) - 1);
    }
    return result;
}


%ctor {
    @autoreleasepool {
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

        %init;

        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(__unused NSNotification *notification) {
            [[OAGameBoostOverlayManager sharedManager] installIfPossible];
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
            [[OAGameBoostOverlayManager sharedManager] installIfPossible];
            GBRefreshApplicationResolution();
            GBRefreshFrameRateTargets();
            GBRefreshMetalOptions();
            if (GBShouldKeepLandscape()) {
                GBRequestOrientationUpdate();
            }
        });
    }
}
