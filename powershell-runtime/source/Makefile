# PWSH_VERSION is version of PowerShell to download
PWSH_VERSION ?= 7.2.13
# PWSH_ARCHITECTURE can be 'x64' or 'arm64'
PWSH_ARCHITECTURE ?= x64
build-PwshRuntimeLayer:
# Download and extract PowerShell binaries. Remove downloaded file
	curl -L -o $(ARTIFACTS_DIR)/powershell-$(PWSH_VERSION)-$(PWSH_ARCHITECTURE).tar.gz https://github.com/PowerShell/PowerShell/releases/download/v$(PWSH_VERSION)/powershell-$(PWSH_VERSION)-linux-$(PWSH_ARCHITECTURE).tar.gz
	mkdir -p $(ARTIFACTS_DIR)/powershell
	tar zxf $(ARTIFACTS_DIR)/powershell-$(PWSH_VERSION)-$(PWSH_ARCHITECTURE).tar.gz -C $(ARTIFACTS_DIR)/powershell/
	rm $(ARTIFACTS_DIR)/powershell-$(PWSH_VERSION)-$(PWSH_ARCHITECTURE).tar.gz
# Make PowerShell binary executable
	chmod +x $(ARTIFACTS_DIR)/powershell/pwsh

# Copy additional runtime files, including bootstrap. Remove Makefile from destination
	cp bootstrap $(ARTIFACTS_DIR)
	cp PowerShellLambdaContext.cs $(ARTIFACTS_DIR)
	mkdir $(ARTIFACTS_DIR)/modules
	cp -R ./modules/* $(ARTIFACTS_DIR)/modules/

# Merge all Private module content into a single .psm1 file to speed up module loading
	cd $(ARTIFACTS_DIR)/modules/Private
	tail -n +3 -q $(ARTIFACTS_DIR)/modules/Private/*.ps1 >> $(ARTIFACTS_DIR)/modules/pwsh-runtime.psm1
	rm -Rf $(ARTIFACTS_DIR)/modules/Private

# Make bootstrap script executable
	chmod +x $(ARTIFACTS_DIR)/bootstrap