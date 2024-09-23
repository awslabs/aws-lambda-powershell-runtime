build-PSFalconLayer:
	# Download AWSToolsLayer module binaries
	curl -L -o $(ARTIFACTS_DIR)/psfalcon.zip https://psg-prod-eastus.azureedge.net/packages/psfalcon.2.2.4.nupkg
	mkdir -p $(ARTIFACTS_DIR)/modules
	mkdir -p $(ARTIFACTS_DIR)/modules/PSFalcon
	mkdir -p $(ARTIFACTS_DIR)/modules/PSFalcon/2.2.4

	unzip $(ARTIFACTS_DIR)/psfalcon.zip -d $(ARTIFACTS_DIR)/modules/PSFalcon/2.2.4/
	
	#rm $(ARTIFACTS_DIR)/PSFalcon.2.2.5.zip
	rm $(ARTIFACTS_DIR)/psfalcon.zip
	#rm -rf $(ARTIFACTS_DIR)/folder/psfalcon-master 
	