#pragma once

#import <UIKit/UIKit.h>

@interface GBGlassSurfaceView : UIView

@property(nonatomic, readonly, getter=isUsingNativeGlass) BOOL usingNativeGlass;

- (instancetype)initWithFrame:(CGRect)frame
                   interactive:(BOOL)interactive NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(CGRect)frame;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

- (void)setCornerRadius:(CGFloat)cornerRadius;
- (void)updateWithTintColor:(UIColor *)tintColor
                    density:(CGFloat)density
                    enabled:(BOOL)enabled
                   animated:(BOOL)animated;

@end
