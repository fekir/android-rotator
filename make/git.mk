
git-install-hooks:
	@if command -v git >/dev/null 2>&1; then :; \
		repo_root=$$(git rev-parse --show-toplevel); \
		hooks_dir=$$(git rev-parse --git-path hooks); \
		mkdir -p "$$hooks_dir"; \
		cp "$$repo_root/git/pre-commit" "$$hooks_dir/pre-commit"; \
		chmod +x "$$hooks_dir/pre-commit"; \
		printf 'Installed hook to %s\n' "$$hooks_dir/pre-commit"; \
	else :; \
		printf "git is not available"; \
	fi
.PHONY: git-install-hooks
