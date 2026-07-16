#import "GameBoostShared.h"

void GBPostSettingsChanged(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:GBSettingsDidChangeNotification
                                                          object:nil];
    });
}

void GBUpdateProcessActivity(BOOL enabled) {
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

void GBSetPerformanceEnabled(BOOL enabled, BOOL persist) {
    gPerformanceEnabled.store(enabled, std::memory_order_relaxed);
    GBUpdateProcessActivity(enabled && GBIsGameBoostActive());

    if (persist) {
        [NSUserDefaults.standardUserDefaults setBool:enabled forKey:GBPerformanceKey];
    }
    GBPostSettingsChanged();
}

void GBApplyQoSToCurrentRenderThread(void) {
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

NSArray<UIWindow *> *GBApplicationWindows(void) {
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

BOOL GBIsOverlayWindow(UIWindow *window) {
    return [objc_getAssociatedObject(window, GBOverlayWindowKey) boolValue];
}

CGPoint GBRemapPUBGTouchPoint(CGPoint point, UIView *view) {
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

UIInterfaceOrientationMask GBDeclaredOrientationMask(void) {
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

UIWindow *GBHostApplicationWindow(void) {
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

UIViewController *GBTopViewController(UIViewController *controller) {
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

UIInterfaceOrientationMask GBHostOrientationMask(void) {
    UIWindow *hostWindow = GBHostApplicationWindow();
    UIViewController *controller =
        GBTopViewController(hostWindow.rootViewController);
    UIInterfaceOrientationMask mask = controller != nil
        ? controller.supportedInterfaceOrientations
        : 0;
    return mask != 0 ? mask : GBDeclaredOrientationMask();
}

BOOL GBAppIsLandscapeOnly(void) {
    const UIInterfaceOrientationMask mask = GBDeclaredOrientationMask();
    const BOOL supportsLandscape = (mask & UIInterfaceOrientationMaskLandscape) != 0;
    const UIInterfaceOrientationMask portraitMask =
        UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskPortraitUpsideDown;
    return supportsLandscape && (mask & portraitMask) == 0;
}

BOOL GBShouldKeepLandscape(void) {
    return (GBIsGameBoostActive() &&
            gLandscapeLockEnabled.load(std::memory_order_relaxed)) ||
           GBAppIsLandscapeOnly();
}

UIInterfaceOrientationMask GBLandscapeMask(void) {
    UIInterfaceOrientationMask landscapeMask =
        GBHostOrientationMask() & UIInterfaceOrientationMaskLandscape;
    return landscapeMask != 0 ? landscapeMask : UIInterfaceOrientationMaskLandscape;
}

BOOL GBMaskContainsOrientation(UIInterfaceOrientationMask mask,
                                      UIInterfaceOrientation orientation) {
    return orientation != UIInterfaceOrientationUnknown &&
           (mask & (1UL << orientation)) != 0;
}

UIInterfaceOrientation GBPreferredLandscapeOrientation(void) {
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

void GBInstallControllerOrientationOverrides(UIViewController *controller) {
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

void GBRequestOrientationUpdate(void) {
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

void GBSetLandscapeLockEnabled(BOOL enabled, BOOL persist) {
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

