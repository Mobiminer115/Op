#import "GameBoostShared.h"

%group GameBoostUIKitHooks

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
    const CGFloat originalScale = %orig;
    return MAX(0.1, originalScale *
        (CGFloat)gResolutionScale.load(std::memory_order_relaxed));
}

- (CGFloat)nativeScale {
    if (self == gMainScreen) {
        const CGFloat virtualFactor = GBRobloxLogicalScaleFactor(
            gOriginalMainScreenBounds.size);
        return MAX(0.1, (gOriginalMainNativeScale / virtualFactor) *
            (CGFloat)gResolutionScale.load(std::memory_order_relaxed));
    }
    const CGFloat originalScale = %orig;
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

%end

%ctor {
    @autoreleasepool {
        if (GBShouldLoadInCurrentProcess()) {
            GBInitializeRuntimeState();
            %init(GameBoostUIKitHooks);
        }
    }
}
