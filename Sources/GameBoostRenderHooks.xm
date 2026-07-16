#import "GameBoostShared.h"

%group GameBoostRenderHooks

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

%end

%ctor {
    @autoreleasepool {
        if (GBShouldLoadInCurrentProcess()) {
            GBInitializeRuntimeState();
            %init(GameBoostRenderHooks);
        }
    }
}
