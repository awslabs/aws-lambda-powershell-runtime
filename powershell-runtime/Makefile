PWSH_VERSION ?= 7.2.7

# Targets for x64 & arm64 
build-Pwshx64RuntimeLayer: PWSH_ARCHITECTURE = x64
build-Pwshx64RuntimeLayer: build-PwshRuntimeLayer

build-PwshArm64RuntimeLayer: PWSH_ARCHITECTURE = arm64
build-PwshArm64RuntimeLayer: build-PwshRuntimeLayer

build-PwshRuntimeLayer:
# Download and extract PowerShell binaries. Remove downloaded file
	curl -L -o $(ARTIFACTS_DIR)/powershell-$(PWSH_VERSION)-$(PWSH_ARCHITECTURE).tar.gz https://github.com/PowerShell/PowerShell/releases/download/v$(PWSH_VERSION)/powershell-$(PWSH_VERSION)-linux-$(PWSH_ARCHITECTURE).tar.gz
	mkdir -p $(ARTIFACTS_DIR)/powershell
	tar zxf $(ARTIFACTS_DIR)/powershell-$(PWSH_VERSION)-$(PWSH_ARCHITECTURE).tar.gz -C $(ARTIFACTS_DIR)/powershell/
	rm $(ARTIFACTS_DIR)/powershell-$(PWSH_VERSION)-$(PWSH_ARCHITECTURE).tar.gz
# Make PowerShell binary executable
	chmod +x $(ARTIFACTS_DIR)/powershell/pwsh
# Copy additional runtime files, including bootstrap. Remove Makefile from destination
	cp -R ./pwsh-runtime/* $(ARTIFACTS_DIR)
# Make bootstrap script executable
	chmod +x $(ARTIFACTS_DIR)/bootstrap
