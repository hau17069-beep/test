ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = SpringBoard
TWEAK_FILTER = vn.foody.nowpartner

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AutoPickFoody
AutoPickFoody_FILES = Tweak.xm APFPrefs.m APFFilter.m APFMenu.m
AutoPickFoody_CFLAGS = -fobjc-arc -Wno-unused-variable -Wno-unused-function -Wno-deprecated-declarations
AutoPickFoody_FRAMEWORKS = UIKit Foundation AudioToolbox UserNotifications
AutoPickFoody_LDFLAGS = -lz

include $(THEOS_MAKE_PATH)/tweak.mk