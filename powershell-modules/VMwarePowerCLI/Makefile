build-PowerCLILayer:
	# Copy and extract PowerShell binaries
	curl -L -o $(ARTIFACTS_DIR)/PowerCLI.zip https://vdc-download.vmware.com/vmwb-repository/dcr-public/fdf729aa-01f9-4129-87c7-1e7ce17c5e7b/1c6d21ef-d60e-472a-b2c2-ce8b83abe095/VMware-PowerCLI-12.5.0-19195797.zip
	mkdir -p $(ARTIFACTS_DIR)/modules

	rm $(ARTIFACTS_DIR)/PowerCLI.zip