
ifndef RUN_SILENT_PATTERN
  $(error RUN_SILENT_PATTERN must be defined before including run-silent.mk)
endif

RED    := \033[31m
YELLOW := \033[33m
RESET  := \033[0m
define run_silent
    @\
    output=$$( ( $(1) ) 2>&1 ); \
    code=$$?; \
    if [ -n "$$output" ]; then :; output=$$( printf "%s\nX" "$$output" ); output=$${output%X}; fi; \
    if [ $$code -ne 0 ]; then :; \
        printf    "$(RED)%s\n%s$(RESET)" "$(1)" "$$output"; \
    elif printf '%s' "$$output" | grep -Eiq -- '$(RUN_SILENT_PATTERN)'; then \
        printf "$(YELLOW)%s\n%s$(RESET)" "$(1)" "$$output"; \
    elif [ "$(VERBOSE)" != "0" ]; then :; \
        printf '%s\n%s' "$(1)" "$$output"; \
    fi; \
    exit $$code;
endef

# make debug and make verbose targets
DEBUG ?= 0
ifneq ($(filter debug,$(MAKECMDGOALS)),)
override DEBUG := 1
endif
debug:
	@echo debug
.PHONY: debug

VERBOSE ?= 0
ifneq ($(filter verbose,$(MAKECMDGOALS)),)
override VERBOSE := 1
endif
verbose:
	@:
.PHONY: verbose
