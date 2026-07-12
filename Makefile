ARCHS = arm64 arm64e

ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
TARGET = iphone:clang:latest:15.0
else
TARGET = iphone:clang:latest:14.0
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = GameBoost

GameBoost_FILES = Tweak.xm
GameBoost_CFLAGS = -fobjc-arc
GameBoost_CCFLAGS = -std=c++17
GameBoost_FRAMEWORKS = Foundation UIKit QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
