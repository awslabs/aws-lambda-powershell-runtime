# syntax=docker/dockerfile:1

# This image is based on the existing powershell-runtime image.
# Set any of the arguments as needed in case you customized the image details.
ARG REGISTRY=<account>.dkr.ecr.<region>.amazonaws.com
ARG RUNTIME_IMAGE=${REGISTRY}/powershell-remoting
ARG RUNTIME_TAG=latest
ARG RUNTIME=${RUNTIME_IMAGE}:${RUNTIME_TAG}

FROM ${RUNTIME} as build

WORKDIR /tmp

# These build dependencies are documented here:
# https://github.com/gssapi/gss-ntlmssp/blob/main/contrib/gssntlmssp.spec.in#L13
RUN dnf install -y \
    autoconf automake docbook-style-xsl doxygen findutils krb5-devel \
    libtool libxml2 libxslt libunistring-devel m4 pkgconfig openssl-devel

# These build dependencies are also needed but not in the spec file.
# It's easier to iterate on these packages when they are in their own RUN step.
RUN dnf install -y rpm-build gettext-devel libwbclient-devel zlib-devel

# Build gssntlmssp
RUN <<EOF
    git clone https://github.com/gssapi/gss-ntlmssp
    cd /tmp/gss-ntlmssp
    autoreconf -f -i
    ./configure
    make rpms
    mkdir -p /tmp/gssntlmssp
    mv /tmp/gss-ntlmssp/rpmbuild/RPMS/x86_64/gssntlmssp-[0-9]*.x86_64.rpm /tmp/gssntlmssp/gssntlmssp.rpm
    rm -rf /tmp/gss-ntlmssp
EOF

# Start a new build stage since we don't need all the build dependencies and intermediate build output.
FROM ${RUNTIME} as target

# Get the final RPM we built out of the build stage.
COPY --from=build /tmp/gssntlmssp /tmp/

# libwbclient is required to install the RPM, but it does not seem to declare it as a runtime dependency
# so it won't be installed automatically.
RUN dnf install -y libwbclient

# This RPM is quite small but it brings in around 45 other packages.
RUN rpm --install /tmp/gssntlmssp.rpm
