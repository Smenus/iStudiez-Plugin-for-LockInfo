THEOS_DEVICE_IP = 192.168.0.11
SDKVERSION = 5.0
GO_EASY_ON_ME = 1
ADDITIONAL_LDFLAGS = -framework UIKit \
						-framework CoreFoundation \
						-framework CoreGraphics \
						-framework CoreLocation \
						-framework Preferences \
						-framework GraphicsServices \
						-F$(SYSROOT)/System/Library/Frameworks \
						-F$(SYSROOT)/System/Library/PrivateFrameworks \
						-lsqlite3
#ADDITIONAL_CFLAGS = -DDEBUG

ifeq ($(shell [ -f ./framework/makefiles/common.mk ] && echo 1 || echo 0),0)
all clean package install::
	git submodule update --init
	./framework/git-submodule-recur.sh init
	$(MAKE) $(MAKEFLAGS) MAKELEVEL=0 $@
else

BUNDLE_NAME = org.smenus.lockinfo.iStudiezPlugin
org.smenus.lockinfo.iStudiezPlugin_OBJC_FILES = iStudiezPlugin.mm
org.smenus.lockinfo.iStudiezPlugin_RESOURCE_DIRS = Bundle
org.smenus.lockinfo.iStudiezPlugin_INSTALL_PATH = /Library/LockInfo/Plugins

include framework/makefiles/common.mk
include framework/makefiles/bundle.mk

endif
