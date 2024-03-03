## INSTALL POWERSHELL RUNTIME
FROM public.ecr.aws/lambda/provided:al2023 as runtime-files
# PWSH_VERSION is version of PowerShell to download
ARG PWSH_VERSION=7.4.0
# PWSH_ARCHITECTURE can be 'x64' or 'arm64'
ARG PWSH_ARCHITECTURE=x64
ARG ARTIFACTS_DIR=/opt
# Download and extract PowerShell binaries. Remove downloaded file
RUN dnf install tar gzip -y
RUN curl -L -o $ARTIFACTS_DIR/powershell-$PWSH_VERSION-$PWSH_ARCHITECTURE.tar.gz https://github.com/PowerShell/PowerShell/releases/download/v$PWSH_VERSION/powershell-$PWSH_VERSION-linux-$PWSH_ARCHITECTURE.tar.gz
RUN mkdir -p $ARTIFACTS_DIR/powershell
RUN tar zxf $ARTIFACTS_DIR/powershell-$PWSH_VERSION-$PWSH_ARCHITECTURE.tar.gz -C $ARTIFACTS_DIR/powershell/
RUN rm $ARTIFACTS_DIR/powershell-$PWSH_VERSION-$PWSH_ARCHITECTURE.tar.gz
# Make PowerShell binary executable
RUN chmod +x $ARTIFACTS_DIR/powershell/pwsh
# Copy additional runtime files from GitHub repo, including bootstrap.
WORKDIR /tmp
RUN dnf install git-core -y
RUN git clone https://github.com/awslabs/aws-lambda-powershell-runtime
ARG RUNTIME_DIR=/tmp/aws-lambda-powershell-runtime/powershell-runtime/source
RUN cp $RUNTIME_DIR/bootstrap /var/runtime
RUN cp $RUNTIME_DIR/PowerShellLambdaContext.cs $ARTIFACTS_DIR
RUN mkdir $ARTIFACTS_DIR/modules
RUN cp -r $RUNTIME_DIR/modules/ $ARTIFACTS_DIR/
RUN rm -Rf /tmp/aws-lambda-powershell-runtime
# Merge all Private module content into a single .psm1 file to speed up module loading
WORKDIR $ARTIFACTS_DIR/modules/Private
RUN tail -n +3 -q $ARTIFACTS_DIR/modules/Private/*.ps1 >> $ARTIFACTS_DIR/modules/pwsh-runtime.psm1
RUN rm -Rf $ARTIFACTS_DIR/modules/Private

# Make bootstrap script executable
RUN chmod +x /var/runtime/bootstrap

# https://github.com/jborean93/PSWSMan
# This fixes WSMan/OMI so that PowerShell remoting is possible to Windows hosts.
RUN DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 /opt/powershell/pwsh -C '\
    Install-PSResource -Name PSWSMAN -Version "[2.3.1,3.0.0]" -Scope AllUsers -TrustRepository ; \
    Install-WSMan -Verbose ; \
    Get-WSManVersion | Format-List \
    '

## Build final image
FROM public.ecr.aws/lambda/provided:al2023
## Copy PowerShell runtime files
COPY --from=runtime-files . /
