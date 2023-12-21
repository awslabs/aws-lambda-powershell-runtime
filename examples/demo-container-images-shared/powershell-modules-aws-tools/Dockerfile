## INSTALL AWS SDK
FROM public.ecr.aws/lambda/provided:al2023 as module-files
ARG ARTIFACTS_DIR=/opt
RUN dnf install unzip -y
RUN curl -L -o $ARTIFACTS_DIR/AWS.Tools.zip https://sdk-for-net.amazonwebservices.com/ps/v4/latest/AWS.Tools.zip
RUN mkdir -p $ARTIFACTS_DIR/modules

# Extract Entire AWS.Tools modules
RUN unzip $ARTIFACTS_DIR/AWS.Tools.zip -d $ARTIFACTS_DIR/modules
# Extract select AWS.Tools modules (AWS.Tools.Common required)
#RUN unzip $ARTIFACTS_DIR/AWS.Tools.zip 'AWS.Tools.Common/**/*' -d $ARTIFACTS_DIR/modules/
#RUN unzip $ARTIFACTS_DIR/AWS.Tools.zip 'AWS.Tools.S3/**/*' -d $ARTIFACTS_DIR/modules/
#RUN unzip $ARTIFACTS_DIR/AWS.Tools.zip 'AWS.Tools.EventBridge/**/*' -d $ARTIFACTS_DIR/modules/
RUN rm $ARTIFACTS_DIR/AWS.Tools.zip
