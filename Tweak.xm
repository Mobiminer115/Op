#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/CAMetalLayer.h>
#import <MetalKit/MTKView.h>
#import <pthread/qos.h>
#import <objc/runtime.h>

#include <atomic>
#include <cmath>

static NSString * const GBPerformanceKey = @"com.gameboost.universal.performance-enabled";
static NSString * const GBResolutionScaleKey = @"com.gameboost.universal.resolution-scale";
static NSString * const GBLandscapeLockKey = @"com.gameboost.universal.landscape-lock-enabled";
static NSString * const GBSettingsDidChangeNotification = @"com.gameboost.universal.settings-changed";

static std::atomic_bool gPerformanceEnabled(false);
static std::atomic_bool gLandscapeLockEnabled(false);
// gResolutionScale is the scale currently active in the renderer. The menu
// writes gConfiguredResolutionScale; it becomes active on the next app launch
// so engines that cache their viewport never see a half-updated frame.
static std::atomic<double> gResolutionScale(1.0);
static std::atomic<double> gConfiguredResolutionScale(1.0);
static id gProcessActivity = nil;
static UIScreen *gMainScreen = nil;
static UIScreenMode *gMainScreenMode = nil;
static CGFloat gOriginalMainScreenScale = 1.0;
static CGFloat gOriginalMainNativeScale = 1.0;
static CGRect gOriginalMainNativeBounds = CGRectZero;
static CGSize gOriginalMainScreenModeSize = CGSizeZero;

static const void *GBMetalKitManagedLayerKey = &GBMetalKitManagedLayerKey;
static const void *GBOverlayWindowKey = &GBOverlayWindowKey;
static const void *GBOrientationMaskOverrideKey = &GBOrientationMaskOverrideKey;
static const void *GBAutorotateOverrideKey = &GBAutorotateOverrideKey;
static const void *GBPreferredOrientationOverrideKey = &GBPreferredOrientationOverrideKey;

static double GBClampScale(double scale) {
    if (!std::isfinite(scale)) {
        return 1.0;
    }
    // This control is a performance/downscale control. Values above 1.0 are
    // deliberately rejected so it cannot turn into display zoom or expensive
    // supersampling.
    return fmin(1.0, fmax(0.1, scale));
}

static BOOL GBIsUsableSize(CGSize size) {
    return size.width > 0.0 && size.height > 0.0 &&
           std::isfinite(size.width) && std::isfinite(size.height);
}

static CGFloat GBCurrentScreenScale(void) {
    return MAX(0.1, gOriginalMainScreenScale *
        (CGFloat)gResolutionScale.load(std::memory_order_relaxed));
}

static CGSize GBPixelSizeForBounds(CGSize boundsSize) {
    if (!GBIsUsableSize(boundsSize)) {
        return CGSizeZero;
    }

    const CGFloat screenScale = GBCurrentScreenScale();
    return CGSizeMake(MAX(1.0, round(boundsSize.width * screenScale)),
                      MAX(1.0, round(boundsSize.height * screenScale)));
}

static BOOL GBShouldLoadInCurrentProcess(void) {
    NSBundle *mainBundle = NSBundle.mainBundle;
    NSString *bundlePath = mainBundle.bundlePath ?: @"";
    NSString *bundleIdentifier = mainBundle.bundleIdentifier ?: @"";

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

static BOOL GBThermalStateAllowsBoost(void) {
    NSProcessInfoThermalState state = NSProcessInfo.processInfo.thermalState;
    return state < NSProcessInfoThermalStateSerious;
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
    if (enabled && !GBThermalStateAllowsBoost()) {
        enabled = NO;
    }

    gPerformanceEnabled.store(enabled, std::memory_order_relaxed);
    GBUpdateProcessActivity(enabled);

    if (persist) {
        [NSUserDefaults.standardUserDefaults setBool:enabled forKey:GBPerformanceKey];
    }
    GBPostSettingsChanged();
}

static void GBApplyQoSToCurrentRenderThread(void) {
    static thread_local BOOL promoted = NO;
    static thread_local qos_class_t previousClass = QOS_CLASS_UNSPECIFIED;
    static thread_local int previousRelativePriority = 0;

    const BOOL shouldPromote = gPerformanceEnabled.load(std::memory_order_relaxed);
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
    return legacyWindows ?: @[];
}

static BOOL GBIsOverlayWindow(UIWindow *window) {
    return [objc_getAssociatedObject(window, GBOverlayWindowKey) boolValue];
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
    return gLandscapeLockEnabled.load(std::memory_order_relaxed) ||
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

static void GBSetResolutionScale(double scale, BOOL persist) {
    scale = GBClampScale(scale);
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

@interface OAGameBoostOverlayViewController : UIViewController
@property(nonatomic, strong) UIButton *menuButton;
@property(nonatomic, strong) UIView *panel;
@property(nonatomic, strong) UISwitch *performanceSwitch;
@property(nonatomic, strong) UISwitch *landscapeSwitch;
@property(nonatomic, strong) UILabel *landscapeHintLabel;
@property(nonatomic, strong) UISlider *scaleSlider;
@property(nonatomic, strong) UILabel *scaleValueLabel;
@property(nonatomic, strong) UILabel *scaleHintLabel;
@property(nonatomic, assign) BOOL hasInitialButtonPosition;
@end

@implementation OAGameBoostOverlayViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    self.menuButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.menuButton.frame = CGRectMake(16.0, 96.0, 52.0, 52.0);
    self.menuButton.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.88];
    self.menuButton.layer.cornerRadius = 26.0;
    self.menuButton.layer.borderWidth = 1.0;
    self.menuButton.layer.borderColor = [UIColor colorWithRed:0.25 green:0.76 blue:1.0 alpha:0.9].CGColor;
    self.menuButton.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
    self.menuButton.accessibilityLabel = @"Open GameBoost menu";
    [self.menuButton setTitle:@"GB" forState:UIControlStateNormal];
    [self.menuButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.menuButton addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.menuButton addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                                 action:@selector(dragMenuButton:)]];
    [self.view addSubview:self.menuButton];

    self.panel = [[UIView alloc] initWithFrame:CGRectMake(78.0, 96.0, 300.0, 294.0)];
    self.panel.backgroundColor = [UIColor colorWithWhite:0.055 alpha:0.94];
    self.panel.layer.cornerRadius = 16.0;
    self.panel.layer.borderWidth = 1.0;
    self.panel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.14].CGColor;
    self.panel.hidden = YES;
    [self.view addSubview:self.panel];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(18.0, 12.0, 200.0, 28.0)];
    titleLabel.text = @"GameBoost";
    titleLabel.textColor = UIColor.whiteColor;
    titleLabel.font = [UIFont systemFontOfSize:19.0 weight:UIFontWeightSemibold];
    [self.panel addSubview:titleLabel];

    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.frame = CGRectMake(252.0, 7.0, 40.0, 40.0);
    closeButton.titleLabel.font = [UIFont systemFontOfSize:23.0 weight:UIFontWeightRegular];
    closeButton.accessibilityLabel = @"Close GameBoost menu";
    [closeButton setTitle:@"×" forState:UIControlStateNormal];
    [closeButton setTitleColor:[UIColor colorWithWhite:0.82 alpha:1.0] forState:UIControlStateNormal];
    [closeButton addTarget:self action:@selector(hidePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:closeButton];

    UILabel *performanceLabel = [[UILabel alloc] initWithFrame:CGRectMake(18.0, 52.0, 190.0, 25.0)];
    performanceLabel.text = @"Performance QoS";
    performanceLabel.textColor = UIColor.whiteColor;
    performanceLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightMedium];
    [self.panel addSubview:performanceLabel];

    self.performanceSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(228.0, 48.0, 51.0, 31.0)];
    self.performanceSwitch.onTintColor = [UIColor colorWithRed:0.18 green:0.70 blue:1.0 alpha:1.0];
    [self.performanceSwitch addTarget:self
                               action:@selector(performanceSwitchChanged:)
                     forControlEvents:UIControlEventValueChanged];
    [self.panel addSubview:self.performanceSwitch];

    UILabel *performanceHint = [[UILabel alloc] initWithFrame:CGRectMake(18.0, 79.0, 264.0, 19.0)];
    performanceHint.text = @"Ưu tiên render; tự tắt khi máy quá nóng";
    performanceHint.textColor = [UIColor colorWithWhite:0.67 alpha:1.0];
    performanceHint.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightRegular];
    [self.panel addSubview:performanceHint];

    UILabel *landscapeLabel = [[UILabel alloc] initWithFrame:CGRectMake(18.0, 108.0, 190.0, 25.0)];
    landscapeLabel.text = @"Khóa ngang game";
    landscapeLabel.textColor = UIColor.whiteColor;
    landscapeLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightMedium];
    [self.panel addSubview:landscapeLabel];

    self.landscapeSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(228.0, 104.0, 51.0, 31.0)];
    self.landscapeSwitch.onTintColor = [UIColor colorWithRed:0.18 green:0.70 blue:1.0 alpha:1.0];
    [self.landscapeSwitch addTarget:self
                             action:@selector(landscapeSwitchChanged:)
                   forControlEvents:UIControlEventValueChanged];
    [self.panel addSubview:self.landscapeSwitch];

    self.landscapeHintLabel = [[UILabel alloc] initWithFrame:CGRectMake(18.0, 135.0, 264.0, 19.0)];
    self.landscapeHintLabel.textColor = [UIColor colorWithWhite:0.67 alpha:1.0];
    self.landscapeHintLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightRegular];
    [self.panel addSubview:self.landscapeHintLabel];

    UILabel *scaleLabel = [[UILabel alloc] initWithFrame:CGRectMake(18.0, 164.0, 180.0, 25.0)];
    scaleLabel.text = @"Độ phân giải app";
    scaleLabel.textColor = UIColor.whiteColor;
    scaleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightMedium];
    [self.panel addSubview:scaleLabel];

    self.scaleValueLabel = [[UILabel alloc] initWithFrame:CGRectMake(218.0, 164.0, 64.0, 25.0)];
    self.scaleValueLabel.textColor = [UIColor colorWithRed:0.25 green:0.76 blue:1.0 alpha:1.0];
    self.scaleValueLabel.textAlignment = NSTextAlignmentRight;
    self.scaleValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:15.0 weight:UIFontWeightSemibold];
    [self.panel addSubview:self.scaleValueLabel];

    self.scaleSlider = [[UISlider alloc] initWithFrame:CGRectMake(18.0, 193.0, 264.0, 30.0)];
    self.scaleSlider.minimumValue = 0.1f;
    self.scaleSlider.maximumValue = 1.0f;
    self.scaleSlider.minimumTrackTintColor = [UIColor colorWithRed:0.18 green:0.70 blue:1.0 alpha:1.0];
    [self.scaleSlider addTarget:self action:@selector(scaleSliderChanged:)
               forControlEvents:UIControlEventValueChanged];
    [self.panel addSubview:self.scaleSlider];

    self.scaleHintLabel = [[UILabel alloc] initWithFrame:CGRectMake(18.0, 225.0, 264.0, 18.0)];
    self.scaleHintLabel.textColor = [UIColor colorWithWhite:0.67 alpha:1.0];
    self.scaleHintLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightRegular];
    [self.panel addSubview:self.scaleHintLabel];

    UIButton *resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    resetButton.frame = CGRectMake(18.0, 252.0, 264.0, 32.0);
    resetButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.09];
    resetButton.layer.cornerRadius = 8.0;
    resetButton.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    [resetButton setTitle:@"Đặt lại 100%" forState:UIControlStateNormal];
    [resetButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [resetButton addTarget:self action:@selector(resetScale) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:resetButton];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(settingsDidChange)
                                               name:GBSettingsDidChangeNotification
                                             object:nil];
    [self settingsDidChange];
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
    UIViewController *hostController =
        GBTopViewController(hostWindow.rootViewController);
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
        self.menuButton.center = CGPointMake(42.0, MAX(110.0, self.view.safeAreaInsets.top + 42.0));
        self.hasInitialButtonPosition = YES;
    }
    [self clampMenuButton];
    [self layoutPanelNearButton];
}

- (void)settingsDidChange {
    self.performanceSwitch.on = gPerformanceEnabled.load(std::memory_order_relaxed);
    self.landscapeSwitch.on =
        gLandscapeLockEnabled.load(std::memory_order_relaxed);
    self.landscapeHintLabel.text = GBAppIsLandscapeOnly()
        ? @"Game chỉ hỗ trợ ngang • GameBoost tự giữ đúng hướng"
        : @"Vẫn nằm ngang khi bật khóa xoay của hệ thống";
    const double activeScale = gResolutionScale.load(std::memory_order_relaxed);
    const double configuredScale =
        gConfiguredResolutionScale.load(std::memory_order_relaxed);
    const BOOL needsRelaunch = fabs(activeScale - configuredScale) >= 0.001;

    self.scaleSlider.value = (float)configuredScale;
    if (needsRelaunch) {
        self.scaleValueLabel.text =
            [NSString stringWithFormat:@"%.0f%%↻", configuredScale * 100.0];
    } else {
        self.scaleValueLabel.text =
            [NSString stringWithFormat:@"%.0f%%", configuredScale * 100.0];
    }
    if (needsRelaunch) {
        self.scaleHintLabel.text = @"Đã lưu • đóng/mở lại app để áp dụng an toàn";
    } else if (configuredScale <= 0.25) {
        self.scaleHintLabel.text = @"10–25% rất mờ • menu vẫn giữ độ nét gốc";
    } else {
        self.scaleHintLabel.text = @"Giảm pixel thật • giữ nguyên khung hình, không zoom";
    }
}

- (void)togglePanel {
    self.panel.hidden = !self.panel.hidden;
    if (!self.panel.hidden) {
        [self layoutPanelNearButton];
    }
}

- (void)hidePanel {
    self.panel.hidden = YES;
}

- (void)performanceSwitchChanged:(UISwitch *)sender {
    GBSetPerformanceEnabled(sender.isOn, YES);
}

- (void)landscapeSwitchChanged:(UISwitch *)sender {
    GBSetLandscapeLockEnabled(sender.isOn, YES);
}

- (void)scaleSliderChanged:(UISlider *)sender {
    const double quantized = round((double)sender.value * 20.0) / 20.0;
    GBSetResolutionScale(quantized, YES);
}

- (void)resetScale {
    GBSetResolutionScale(1.0, YES);
}

- (void)dragMenuButton:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.view];
    self.menuButton.center = CGPointMake(self.menuButton.center.x + translation.x,
                                         self.menuButton.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:self.view];
    [self clampMenuButton];
    [self layoutPanelNearButton];
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

- (void)layoutPanelNearButton {
    CGRect safeBounds = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    const CGFloat margin = 12.0;
    const CGFloat panelWidth = MIN(300.0, MAX(260.0, CGRectGetWidth(safeBounds) - margin * 2.0));
    const CGFloat panelHeight = 294.0;
    CGFloat x = CGRectGetMaxX(self.menuButton.frame) + 10.0;
    if (x + panelWidth > CGRectGetMaxX(safeBounds) - margin) {
        x = CGRectGetMinX(self.menuButton.frame) - panelWidth - 10.0;
    }
    x = MIN(MAX(x, CGRectGetMinX(safeBounds) + margin), CGRectGetMaxX(safeBounds) - panelWidth - margin);

    CGFloat y = CGRectGetMinY(self.menuButton.frame);
    if (y + panelHeight > CGRectGetMaxY(safeBounds) - margin) {
        y = CGRectGetMaxY(safeBounds) - panelHeight - margin;
    }
    y = MAX(y, CGRectGetMinY(safeBounds) + margin);
    self.panel.frame = CGRectMake(x, y, panelWidth, panelHeight);
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
        self.overlayWindow = [[OAGameBoostPassthroughWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
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


%hook UIScreen

- (CGFloat)scale {
    CGFloat originalScale = gOriginalMainScreenScale;
    if (self != gMainScreen) {
        originalScale = %orig;
    }
    return MAX(0.1, originalScale *
        (CGFloat)gResolutionScale.load(std::memory_order_relaxed));
}

- (CGFloat)nativeScale {
    CGFloat originalScale = gOriginalMainNativeScale;
    if (self != gMainScreen) {
        originalScale = %orig;
    }
    return MAX(0.1, originalScale *
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

    if (gResolutionScale.load(std::memory_order_relaxed) >= 0.999) {
        %orig(drawableSize);
        return;
    }

    CGSize targetSize = GBPixelSizeForBounds(self.bounds.size);
    %orig(GBIsUsableSize(targetSize) ? targetSize : drawableSize);
}

%end


%hook CAMetalLayer

- (void)setDrawableSize:(CGSize)drawableSize {
    if (!GBIsUsableSize(drawableSize)) {
        %orig(drawableSize);
        return;
    }

    if (gResolutionScale.load(std::memory_order_relaxed) >= 0.999) {
        %orig(drawableSize);
        return;
    }

    CGSize targetSize = GBPixelSizeForBounds(self.bounds.size);
    %orig(GBIsUsableSize(targetSize) ? targetSize : drawableSize);
}

- (id)nextDrawable {
    GBApplyQoSToCurrentRenderThread();
    return %orig;
}

%end


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
        gOriginalMainNativeBounds = gMainScreen.nativeBounds;
        gOriginalMainScreenModeSize = gMainScreenMode != nil
            ? gMainScreenMode.size
            : gOriginalMainNativeBounds.size;
        double savedScale = [defaults objectForKey:GBResolutionScaleKey] == nil
            ? 1.0
            : [defaults doubleForKey:GBResolutionScaleKey];
        BOOL savedPerformance = [defaults boolForKey:GBPerformanceKey];
        BOOL savedLandscapeLock = [defaults boolForKey:GBLandscapeLockKey];

        const double initialScale = GBClampScale(savedScale);
        gResolutionScale.store(initialScale, std::memory_order_relaxed);
        gConfiguredResolutionScale.store(initialScale, std::memory_order_relaxed);
        gPerformanceEnabled.store(savedPerformance && GBThermalStateAllowsBoost(),
                                  std::memory_order_relaxed);
        gLandscapeLockEnabled.store(savedLandscapeLock, std::memory_order_relaxed);

        %init;

        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(__unused NSNotification *notification) {
            [[OAGameBoostOverlayManager sharedManager] installIfPossible];
            GBRefreshApplicationResolution();
            if (GBShouldKeepLandscape()) {
                GBRequestOrientationUpdate();
            }
        }];

        [NSNotificationCenter.defaultCenter addObserverForName:NSProcessInfoThermalStateDidChangeNotification
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(__unused NSNotification *notification) {
            if (!GBThermalStateAllowsBoost() &&
                gPerformanceEnabled.load(std::memory_order_relaxed)) {
                GBSetPerformanceEnabled(NO, YES);
            }
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            GBUpdateProcessActivity(gPerformanceEnabled.load(std::memory_order_relaxed));
            [[OAGameBoostOverlayManager sharedManager] installIfPossible];
            GBRefreshApplicationResolution();
            if (GBShouldKeepLandscape()) {
                GBRequestOrientationUpdate();
            }
        });
    }
}
