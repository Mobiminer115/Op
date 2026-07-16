ARCHS = arm64 arm64e

ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
TARGET = iphone:clang:latest:15.0
else
TARGET = iphone:clang:latest:14.0
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = GameBoost

GameBoost_FILES = \
	Tweak.xm \
	Sources/GameBoostState.mm \
	Sources/GameBoostDeviceProfiles.mm \
	Sources/GameBoostRuntime.mm \
	Sources/GameBoostRenderRuntime.mm \
	Sources/GameBoostSettings.mm \
	Sources/GameBoostGlass.mm \
	Sources/GameBoostOverlay.mm \
	Sources/GameBoostUIKitHooks.xm \
	Sources/GameBoostRenderHooks.xm \
	Sources/GameBoostIdentityHooks.xm
GameBoost_CFLAGS = -fobjc-arc
GameBoost_CCFLAGS = -std=c++17
GameBoost_FRAMEWORKS = Foundation UIKit QuartzCore Metal MetalKit

include $(THEOS_MAKE_PATH)/tweak.mk
