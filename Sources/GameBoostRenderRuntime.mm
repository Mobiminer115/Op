#import "GameBoostShared.h"

void GBApplyResolutionToViewTree(UIView *view, CGFloat screenScale) {
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

void GBApplyResolutionToLayerTree(CALayer *layer, CGFloat screenScale) {
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

void GBRefreshApplicationResolution(void) {
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

void GBSetGameResolutionScale(double scale, BOOL persist) {
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

void GBSetGraphicsResolutionScale(double scale, BOOL persist) {
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

NSInteger GBEffectiveFrameRate(NSInteger requestedFrameRate) {
    if (!GBIsGameBoostActive()) {
        return requestedFrameRate;
    }
    NSInteger selected = gFrameRate.load(std::memory_order_relaxed);
    if (selected <= 0) {
        return requestedFrameRate;
    }
    return MIN(selected, gMaximumFramesPerSecond);
}

void GBApplyFrameRateToViewTree(UIView *view) {
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

void GBRegisterDisplayLink(CADisplayLink *displayLink) {
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

void GBRefreshFrameRateTargets(void) {
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

CGColorSpaceRef GBDisplayP3ColorSpace(void) {
    static CGColorSpaceRef colorSpace = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
    });
    return colorSpace;
}

void GBApplyMetalLayerOptions(CAMetalLayer *layer) {
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

void GBApplyMetalOptionsToLayerTree(CALayer *layer) {
    if ([layer isKindOfClass:CAMetalLayer.class]) {
        GBApplyMetalLayerOptions((CAMetalLayer *)layer);
    }
    for (CALayer *sublayer in layer.sublayers.copy) {
        GBApplyMetalOptionsToLayerTree(sublayer);
    }
}

void GBRefreshMetalOptions(void) {
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

void GBUpdateIdleTimerOverride(void) {
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
