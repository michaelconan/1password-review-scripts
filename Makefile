.PHONY: lint test coverage ci

PS ?= pwsh
PSFLAGS := -NoProfile -File

lint:
	$(PS) $(PSFLAGS) scripts/Lint.ps1

test:
	$(PS) $(PSFLAGS) scripts/Test.ps1

coverage:
	$(PS) $(PSFLAGS) scripts/Test.ps1 -IncludeCoverage

ci: lint coverage
