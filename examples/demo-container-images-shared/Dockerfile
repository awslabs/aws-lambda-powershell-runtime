#FROM public.ecr.aws/lambda/provided:al2023
## INSTALL POWERSHELL RUNTIME
FROM 978558897928.dkr.ecr.us-east-1.amazonaws.com/powershell-runtime:latest as runtime-files
## Install gss-ntlmssp and related packages for NTLM authentication
# FROM 978558897928.dkr.ecr.us-east-1.amazonaws.com/powershell-remoting-ntlm:latest as remoting-files
## INSTALL AWS SDK
FROM 978558897928.dkr.ecr.us-east-1.amazonaws.com/powershell-modules-aws-tools:latest as module-files

## Build final image
FROM public.ecr.aws/lambda/provided:al2023
## Copy PowerShell runtime files
COPY --from=runtime-files . /
## Copy NTLM auth files
# COPY --from=remoting-files . /
## Copy Module files
COPY --from=module-files . /
## Function files
COPY /function/ /var/task
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
WORKDIR /var/task
ENTRYPOINT  [ "/var/runtime/bootstrap" ]
CMD [ "examplehandler.ps1::handler" ]
