# -----------------------------------------------------------------------------
# Android toolchain

ifneq ($(filter undefined default,$(origin LINT)),)
  # GNU make automatically defines LINT
  undefine LINT
endif

ANDROID_SDK_ROOT_ := /usr/lib/android-sdk
ifdef ANDROID_SDK_ROOT
  ANDROID_SDK_ROOT_ := $(ANDROID_SDK_ROOT)
  PLATFORMT_TOOLS_ROOT_ := $(ANDROID_SDK_ROOT)/platform-tools
else
  PLATFORMT_TOOLS_ROOT_ := /usr/bin
endif
find-build-tool      = $(shell find "$(ANDROID_SDK_ROOT_)/build-tools" -maxdepth 2 -type f -name "$(1)" -print 2>/dev/null | sort -V | tail -n1)
find-cmdline-tool    = $(shell find "$(ANDROID_SDK_ROOT_)/cmdline-tools" -maxdepth 3 -type f -name "$(1)" -print 2>/dev/null | sort -V | tail -n1)

# NOTE: dx searched separately, it is part of debian sdk, not of newer official sdk, and is not in PATH
ifdef BUILD_TOOLS_ROOT
  BUILD_TOOLS_ROOT_   := $(BUILD_TOOLS_ROOT)
  CMDLINE_TOOLS_      := $(shell find "$(BUILD_TOOLS_ROOT_)/../../cmdline-tools" -maxdepth 1 -type d -print 2>/dev/null | grep -v debian | sort -V | tail -n1)/bin
  DX                  ?= $(BUILD_TOOLS_ROOT)/dx
else ifdef ANDROID_SDK_ROOT
  # filter /usr/lib/android-sdk/debian, since it is mostly empty
  BUILD_TOOLS_ROOT_   := $(shell find "$(ANDROID_SDK_ROOT)/build-tools"   -maxdepth 1 -type d -print 2>/dev/null | grep -v debian | sort -V | tail -n1)
  CMDLINE_TOOLS_      := $(shell find "$(ANDROID_SDK_ROOT)/cmdline-tools" -maxdepth 1 -type d -print 2>/dev/null | grep -v debian | sort -V | tail -n1)/bin
else
  BUILD_TOOLS_ROOT_   := /usr/bin
  CMDLINE_TOOLS_      := /usr/bin
endif

ANDROID_SDK_ROOT := $(ANDROID_SDK_ROOT_)
AAPT        ?= $(BUILD_TOOLS_ROOT_)/aapt
AAPT2       ?= $(BUILD_TOOLS_ROOT_)/aapt2
ADB         ?= $(PLATFORMT_TOOLS_ROOT_)/adb
ANDROID_JAR ?= $(shell find "$(ANDROID_SDK_ROOT_)/platforms" -name android.jar 2>/dev/null | sort -V | tail -n 1 )
APKSIGNER   ?= $(BUILD_TOOLS_ROOT_)/apksigner
D8          ?= $(BUILD_TOOLS_ROOT_)/d8
DX          ?= $(call find-build-tool,dx)
LINT        ?= $(CMDLINE_TOOLS_)/lint
R8          ?= $(call find-cmdline-tool,r8)
ZIPALIGN    ?= $(BUILD_TOOLS_ROOT_)/zipalign


BUNDLETOOL    ?= $(CURDIR)/bundletool-all-1.18.3.jar
JAVA          ?= /usr/bin/java
JAVAC         ?= /usr/bin/javac
KEYTOOL       ?= /usr/bin/keytool
KOTLINC       ?= /usr/bin/kotlinc
KOTLIN_ANNOT  ?= $(shell find "/usr/share/kotlin/kotlinc/lib/" -name 'annotations-*.jar' 2>/dev/null | sort -V | tail -n1;)
KOTLIN_STDLIB ?= /usr/share/kotlin/kotlinc/lib/kotlin-stdlib.jar
PROGUARD      ?= /usr/bin/proguard

SOURCE_DATE_EPOCH ?= 315532800

BUILD_TYPE              := debug
AAPT_DEBUG_FLAGS        := --debug-mode
D8_DEBUG_FLAGS          := --debug
JAVAC_DEBUG_FLAGS       := -g
MANIFEST_DEBUGGABLE     := true
ZIPALIGN_ALIGNMENT_ARGS := -p
ifneq ($(DEBUG),1)
  BUILD_TYPE            := release
  AAPT_DEBUG_FLAGS      :=
  D8_DEBUG_FLAGS        :=
  JAVAC_DEBUG_FLAGS     :=
  MANIFEST_DEBUGGABLE   := false
endif
ifneq ($(findstring -P,$(shell "$(ZIPALIGN)" 2>&1)),)
  ZIPALIGN_ALIGNMENT_ARGS := -P 16
endif

var_status = $(if $(filter undefined,$(origin $(1))),$(YELLOW)<unset>$(RESET),$(if $($(1)),$($(1)),$(YELLOW)<unset>$(RESET)))
path_status = $($(1))$(if $(wildcard $($(1))),,$(RED) <missing>$(RESET))

.PHONY: test-env
test-env:
	@\
	printf 'Build Environment:\n'; \
	printf ' %-28s: %s\n' \
		'ANDROID_SDK_ROOT'          '$(call var_status,ANDROID_SDK_ROOT)' \
		'BUILD_TOOLS_ROOT'          '$(call var_status,BUILD_TOOLS_ROOT)' \
	; printf '\n'; \
	printf ' %-28s: %s\n' \
		'aapt'                      '$(call path_status,AAPT)' \
		'aapt2'                     '$(call path_status,AAPT2)' \
		'  AAPT2_FLAGS'             '$(AAPT_DEBUG_FLAGS)' \
		'  AAPT_FLAGS'              '$(AAPT_DEBUG_FLAGS)' \
		'ANDROID_JAR'               '$(call path_status,ANDROID_JAR)' \
		'apksigner'                 '$(call path_status,APKSIGNER)' \
		'd8'                        '$(call path_status,D8)' \
		'  D8_FLAGS'                '$(D8_DEBUG_FLAGS)' \
		'dx'                        '$(call path_status,DX)' \
		'javac'                     '$(call path_status,JAVAC)' \
		'kotlinc'                   '$(call path_status,KOTLINC)' \
		'lint'                      '$(call path_status,LINT)' \
		'proguard'                  '$(call path_status,PROGUARD)' \
		'r8'                        '$(call path_status,R8)' \
		'zipalign'                  '$(call path_status,ZIPALIGN)' \
		'  ZIPALIGN_ALIGNMENT_ARGS' '$(ZIPALIGN_ALIGNMENT_ARGS)' \
