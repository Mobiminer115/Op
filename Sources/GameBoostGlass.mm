#import "GameBoostGlass.h"
#import <QuartzCore/QuartzCore.h>

@interface GBGlassSurfaceView ()
@property(nonatomic, strong) UIVisualEffectView *effectView;
@property(nonatomic, strong) UIView *fallbackFillView;
@property(nonatomic, strong) UIView *tintView;
@property(nonatomic, strong) UIView *specularView;
@property(nonatomic, strong) CAGradientLayer *specularGradient;
@property(nonatomic, strong) CAGradientLayer *rimGradient;
@property(nonatomic, strong) CAShapeLayer *rimMask;
@property(nonatomic, strong) UIViewPropertyAnimator *blurAnimator;
@property(nonatomic, assign) BOOL interactive;
@property(nonatomic, assign, getter=isUsingNativeGlass) BOOL usingNativeGlass;
@property(nonatomic, assign) CGFloat glassCornerRadius;
@property(nonatomic, strong) UIColor *currentTintColor;
@property(nonatomic, assign) CGFloat currentDensity;
@property(nonatomic, assign, getter=isGlassEnabled) BOOL glassEnabled;
@end

@implementation GBGlassSurfaceView

- (instancetype)initWithFrame:(CGRect)frame {
    return [self initWithFrame:frame interactive:NO];
}

- (instancetype)initWithFrame:(CGRect)frame interactive:(BOOL)interactive {
    self = [super initWithFrame:frame];
    if (self == nil) {
        return nil;
    }

    _interactive = interactive;
    _glassCornerRadius = 26.0;
    _currentTintColor = UIColor.systemBlueColor;
    _currentDensity = 0.82;
    _glassEnabled = YES;
    self.userInteractionEnabled = NO;
    self.backgroundColor = UIColor.clearColor;

    _effectView = [[UIVisualEffectView alloc] initWithEffect:nil];
    _effectView.userInteractionEnabled = NO;
    _effectView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;
    [self addSubview:_effectView];

    _fallbackFillView = [UIView new];
    _fallbackFillView.userInteractionEnabled = NO;
    _fallbackFillView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;
    [self addSubview:_fallbackFillView];

    _tintView = [UIView new];
    _tintView.userInteractionEnabled = NO;
    _tintView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;
    [self addSubview:_tintView];

    _specularView = [UIView new];
    _specularView.userInteractionEnabled = NO;
    _specularView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;
    [self addSubview:_specularView];

    _specularGradient = [CAGradientLayer layer];
    _specularGradient.startPoint = CGPointMake(0.08, 0.0);
    _specularGradient.endPoint = CGPointMake(0.86, 1.0);
    [_specularView.layer addSublayer:_specularGradient];

    _rimGradient = [CAGradientLayer layer];
    _rimGradient.startPoint = CGPointMake(0.0, 0.0);
    _rimGradient.endPoint = CGPointMake(1.0, 1.0);
    _rimMask = [CAShapeLayer layer];
    _rimMask.fillColor = UIColor.clearColor.CGColor;
    _rimMask.strokeColor = UIColor.whiteColor.CGColor;
    _rimMask.lineWidth = 1.0;
    _rimGradient.mask = _rimMask;
    [_specularView.layer addSublayer:_rimGradient];

    [self setCornerRadius:_glassCornerRadius];
    [self updateWithTintColor:_currentTintColor
                      density:_currentDensity
                      enabled:YES
                     animated:NO];
    return self;
}

- (void)dealloc {
    [self.blurAnimator stopAnimation:YES];
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _glassCornerRadius = MAX(0.0, cornerRadius);
    for (UIView *view in @[self,
                           self.effectView,
                           self.fallbackFillView,
                           self.tintView,
                           self.specularView]) {
        view.layer.cornerRadius = _glassCornerRadius;
        view.layer.masksToBounds = YES;
        if (@available(iOS 13.0, *)) {
            view.layer.cornerCurve = kCACornerCurveContinuous;
        }
    }
    [self setNeedsLayout];
}

- (UIVisualEffect *)newNativeGlassEffectWithTint:(UIColor *)tintColor {
    Class glassClass = NSClassFromString(@"UIGlassEffect");
    if (glassClass == Nil) {
        return nil;
    }

    id effect = [[glassClass alloc] init];
    @try {
        if ([effect respondsToSelector:NSSelectorFromString(@"setTintColor:")]) {
            [effect setValue:tintColor forKey:@"tintColor"];
        }
        if ([effect respondsToSelector:NSSelectorFromString(@"setInteractive:")]) {
            [effect setValue:@(self.interactive) forKey:@"interactive"];
        }
    } @catch (__unused NSException *exception) {
        return nil;
    }
    return [effect isKindOfClass:UIVisualEffect.class]
        ? (UIVisualEffect *)effect
        : nil;
}

- (UIBlurEffect *)fallbackBlurEffect {
    if (@available(iOS 13.0, *)) {
        return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
}

- (void)applyFallbackBlurWithDensity:(CGFloat)density {
    [self.blurAnimator stopAnimation:YES];
    self.blurAnimator = nil;
    self.effectView.effect = nil;

    UIBlurEffect *blurEffect = [self fallbackBlurEffect];
    UIVisualEffectView *effectView = self.effectView;
    UIViewPropertyAnimator *animator = [[UIViewPropertyAnimator alloc]
        initWithDuration:1.0
                  curve:UIViewAnimationCurveLinear
             animations:^{
        effectView.effect = blurEffect;
    }];
    [animator startAnimation];
    [animator pauseAnimation];
    animator.fractionComplete = 0.35 + density * 0.65;
    self.blurAnimator = animator;
}

- (void)updateWithTintColor:(UIColor *)tintColor
                    density:(CGFloat)density
                    enabled:(BOOL)enabled
                   animated:(BOOL)animated {
    density = MIN(1.0, MAX(0.0, density));
    self.currentTintColor = tintColor ?: UIColor.systemBlueColor;
    self.currentDensity = density;
    self.glassEnabled = enabled;

    UIColor *nativeTint = [self.currentTintColor
        colorWithAlphaComponent:0.20 + density * 0.48];
    UIVisualEffect *nativeEffect = enabled
        ? [self newNativeGlassEffectWithTint:nativeTint]
        : nil;
    self.usingNativeGlass = nativeEffect != nil;

    void (^changes)(void) = ^{
        if (nativeEffect != nil) {
            [self.blurAnimator stopAnimation:YES];
            self.blurAnimator = nil;
            self.effectView.effect = nativeEffect;
        } else if (!enabled) {
            [self.blurAnimator stopAnimation:YES];
            self.blurAnimator = nil;
            self.effectView.effect = nil;
        }

        self.fallbackFillView.backgroundColor = nativeEffect != nil
            ? UIColor.clearColor
            : enabled
                ? [UIColor colorWithWhite:0.018 alpha:0.10 + density * 0.10]
                : [UIColor colorWithWhite:0.025 alpha:0.88 + density * 0.10];
        self.tintView.backgroundColor = nativeEffect != nil
            ? UIColor.clearColor
            : enabled
                ? [self.currentTintColor colorWithAlphaComponent:0.030 + density * 0.090]
                : [self.currentTintColor colorWithAlphaComponent:0.012 + density * 0.025];
        // Native Liquid Glass already supplies refraction and highlights. The
        // custom rim only exists to keep the pre-iOS 26 fallback visually close.
        self.specularView.alpha = nativeEffect != nil
            ? 0.0
            : enabled ? 0.64 + density * 0.28 : 0.0;
    };

    if (nativeEffect == nil && enabled) {
        [self applyFallbackBlurWithDensity:density];
    }

    if (animated) {
        [UIView animateWithDuration:0.28
                              delay:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState |
                                    UIViewAnimationOptionCurveEaseInOut
                         animations:changes
                         completion:nil];
    } else {
        [UIView performWithoutAnimation:changes];
    }

    self.specularGradient.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:0.24].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.055].CGColor,
        (id)UIColor.clearColor.CGColor,
        (id)[UIColor colorWithWhite:0.0 alpha:0.08].CGColor
    ];
    self.specularGradient.locations = @[@0.0, @0.20, @0.54, @1.0];
    self.rimGradient.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:0.52].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.07].CGColor,
        (id)[UIColor colorWithWhite:0.0 alpha:0.10].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.26].CGColor
    ];
    self.rimGradient.locations = @[@0.0, @0.30, @0.72, @1.0];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.effectView.frame = self.bounds;
    self.fallbackFillView.frame = self.bounds;
    self.tintView.frame = self.bounds;
    self.specularView.frame = self.bounds;
    self.specularGradient.frame = self.bounds;
    self.rimGradient.frame = self.bounds;
    self.rimMask.frame = self.bounds;
    CGRect rimRect = CGRectInset(self.bounds, 0.55, 0.55);
    self.rimMask.path = [UIBezierPath bezierPathWithRoundedRect:rimRect
                                                  cornerRadius:MAX(0.0,
                                                      self.glassCornerRadius - 0.55)].CGPath;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (@available(iOS 13.0, *)) {
        if (previousTraitCollection != nil &&
            previousTraitCollection.userInterfaceStyle != self.traitCollection.userInterfaceStyle) {
            [self updateWithTintColor:self.currentTintColor
                              density:self.currentDensity
                              enabled:self.isGlassEnabled
                             animated:NO];
        }
    }
}

@end
