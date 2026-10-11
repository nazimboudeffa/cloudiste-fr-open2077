# syntax=docker/dockerfile:1

# OPEN//77 dedicated server — ready-to-configure Freeroam distribution.
#
# This archive is a self-contained linux-x64 build: it already bundles the
# .NET 10 and ASP.NET Core runtimes (see Open77.Server.runtimeconfig.json and
# libcoreclr.so). The only things it still needs from the OS are the native
# dependencies the README lists (ICU, OpenSSL 3, libstdc++, zlib). The official
# runtime-deps image provides exactly those, and nothing else.
#
# Do NOT switch to an Alpine/musl base: the bundled libcoreclr.so is a glibc build.
FROM mcr.microsoft.com/dotnet/runtime-deps:10.0

# Network map:
#   11778/udp  game traffic
#   11779/tcp  resource downloads (game port + 1)
#   11780/tcp  Warden onboarding / admin panel
#   11781/tcp  in-resource HTTP handler (loopback-only by default)
#   11782/tcp  RCON
EXPOSE 11778/udp 11779/tcp 11780/tcp 11781/tcp 11782/tcp

# Container-friendly runtime tuning. Server GC is opt-in and explicitly
# recommended by docs/server-configuration.md for container deployments.
ENV DOTNET_gcServer=1 \
    DOTNET_EnableDiagnostics=0 \
    DOTNET_NOLOGO=1

# Run unprivileged. UID/GID default to 1000 so a bind-mounted host directory is
# easy to own (chown -R 1000:1000 ./data). The base image is Ubuntu-based and
# already ships a UID/GID 1000, hence --non-unique (-o): it keeps the process on
# 1000 instead of silently falling back to another id.
ARG PUID=1000
ARG PGID=1000
RUN groupadd --non-unique --gid "${PGID}" open77 \
    && useradd --non-unique --uid "${PUID}" --gid "${PGID}" --create-home --shell /usr/sbin/nologin open77

WORKDIR /app

# Ship the whole distribution: Open77.Server, config/, resources/, templates/,
# docs/ and tools/.
COPY --chown=open77:open77 . .

# Unpacking the archive on Windows loses the executable bit; restore it on the
# server binary and the launcher. Also own the whole tree: WORKDIR created /app
# as root and COPY --chown does not change the owner of a directory that already
# exists, which would prevent the unprivileged user from writing server state
# (.open77/, server.jsonc) at runtime.
RUN chown -R open77:open77 /app \
    && chmod +x ./Open77.Server ./start.sh

USER open77

# start.sh cd's to its own directory and execs ./Open77.Server "$@", so every
# argument is forwarded verbatim. Examples:
#
#   First run (Warden onboarding on :11780, prints the setup PIN):
#     docker run --rm -p 11778:11778/udp -p 11779:11779/tcp -p 11780:11780/tcp open77-server:local
#
#   Automated run with a provisioned server.jsonc:
#     docker run --rm -p 11778:11778/udp open77-server:local \
#       --no-setup --config server.jsonc --public-ip 203.0.113.10 --port 11778
ENTRYPOINT ["/app/start.sh"]
