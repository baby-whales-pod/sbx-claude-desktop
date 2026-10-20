# syntax=docker/dockerfile:1
# My Secure Claude Desktop: the Claude desktop app (Linux beta) on the
# sandbox's Wayland display, with an in-sandbox Chromium for the sign-in.
# Built on the shell template; Claude Desktop replaces the template's bash as
# the entrypoint, and tini stays in front of it to reap Electron's child
# processes.
FROM docker/sandbox-templates:shell

ARG CLAUDE_DESKTOP_VERSION
ARG PLAYWRIGHT_VERSION

USER root

# Claude Desktop from Anthropic's apt repository (Ubuntu/Debian, amd64 and
# arm64), plus the libraries Electron needs to draw on Wayland without a GPU
# (software rendering through Mesa). No recommends: they pull QEMU for Cowork,
# which can't run in the sandbox (no /dev/kvm). dbus and gnome-keyring are
# picked by hand so the sign-in is kept between launches. libglib2.0-bin
# satisfies claude-desktop's "kde-cli-tools | ... | libglib2.0-bin" dependency;
# without it apt picks the first alternative and pulls in KDE.
RUN set -eux; \
    install -m 0755 -d /usr/share/keyrings; \
    curl -fsSLo /usr/share/keyrings/claude-desktop-archive-keyring.asc \
      https://downloads.claude.ai/claude-desktop/key.asc; \
    gpg --show-keys --with-colons /usr/share/keyrings/claude-desktop-archive-keyring.asc \
      | grep -q '^fpr:::::::::31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE:'; \
    echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main" \
      > /etc/apt/sources.list.d/claude-desktop.list; \
    # The package's postinst would write the same repository entry again.
    echo 'CLAUDE_DESKTOP_ADD_REPO="false"' > /etc/default/claude-desktop; \
    apt-get update; \
    if [ "${CLAUDE_DESKTOP_VERSION}" = "latest" ]; then pkg=claude-desktop; \
    else pkg="claude-desktop=${CLAUDE_DESKTOP_VERSION}"; fi; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      "$pkg" libglib2.0-bin \
      libgl1-mesa-dri libegl1 libgbm1 libwayland-client0 libwayland-egl1 libwayland-cursor0 \
      libxkbcommon0 libdecor-0-0 libdecor-0-plugin-1-gtk libasound2t64 \
      dbus gnome-keyring desktop-file-utils \
      ca-certificates fonts-dejavu-core fonts-noto-color-emoji adwaita-icon-theme; \
    rm -rf /var/lib/apt/lists/*; \
    # The pin is a claim about content: make the build enforce it.
    if [ "${CLAUDE_DESKTOP_VERSION}" != "latest" ]; then \
      test "$(dpkg-query -W -f='${Version}' claude-desktop)" = "${CLAUDE_DESKTOP_VERSION}"; \
    fi; \
    ! ldd /usr/lib/claude-desktop/claude-desktop | grep -q "not found"

# Playwright's standalone Chromium, for the sign-in: Claude Desktop ends it
# with a claude:// link, which must open in the sandbox, so the browser has to
# run here too. Ubuntu's chromium package is a snap shim, and snapd doesn't run
# in a sandbox. Installed outside the agent's home so a mount can't hide it.
# The template's NPM_CONFIG_PREFIX names a directory that doesn't exist yet,
# which makes npx fail, so point it at a throwaway prefix for this one install.
RUN set -eux; \
    mkdir -p /tmp/npm-prefix/lib; \
    NPM_CONFIG_PREFIX=/tmp/npm-prefix PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright \
      npx -y "playwright@${PLAYWRIGHT_VERSION}" install --no-shell chromium; \
    rm -rf /root/.npm /tmp/npm-prefix; \
    chown -R 0:0 /opt/ms-playwright; \
    chmod -R a+rX /opt/ms-playwright; \
    chrome=$(ls -d /opt/ms-playwright/chromium-*/chrome-linux*/chrome); \
    test -x "$chrome"; \
    ! ldd "$chrome" | grep -q "not found"

# labwc + foot for sandbox-desktop: a nested desktop that applies its own
# keyboard layout, since windows drawn straight on the sandbox display don't
# follow the host's.
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y labwc foot locales; \
    rm -rf /var/lib/apt/lists/*; \
    locale-gen fr_FR.UTF-8

# Launchers, the session entrypoint, the xdg-open override, desktop entries,
# default apps (Chromium for http(s), Claude Desktop for claude://), and the
# Chromium policy that lets claude.ai and claude.com open claude:// links
# without the "Open Claude?" prompt, which never renders on the sandbox's
# compositor and silently blocks the tab while pending. The desktop entries are
# then indexed (mimeinfo.cache): without it the desktop portal sees no
# registered handler for claude:// and shows a "No apps available" window
# instead of handing the sign-in's link back to Claude Desktop.
# `install` rather than COPY --chmod: on a directory copy, --chmod also strips
# the execute bit from the directories, which leaves them unreadable to the agent.
RUN --mount=type=bind,target=/tmp/kit set -eux; \
    install -D -m 0755 -t /opt/my-secure-claude-desktop/bin /tmp/kit/bin/*; \
    install -D -m 0644 -t /usr/local/share/applications /tmp/kit/applications/*.desktop; \
    install -D -m 0644 /tmp/kit/mimeapps.list /etc/xdg/mimeapps.list; \
    update-desktop-database /usr/local/share/applications /usr/share/applications; \
    test -s /usr/local/share/applications/mimeinfo.cache; \
    # Playwright ships Chrome for Testing, which reads only this policy directory.
    policy_dir=/etc/opt/chrome_for_testing/policies/managed; \
    install -D -m 0644 /tmp/kit/chromium-policy.json "$policy_dir/claude-protocol.json"; \
    grep -aqF "${policy_dir%/managed}" /opt/ms-playwright/chromium-*/chrome-linux*/chrome

USER agent

# /opt/my-secure-claude-desktop/bin comes first so its launchers win, and its
# xdg-open wins over the host-forwarding shim sbx writes to /usr/local/bin.
ENV PATH=/opt/my-secure-claude-desktop/bin:${PATH}

WORKDIR /home/agent/workspace

# Setting ENTRYPOINT drops the template's CMD ["bash"]; the empty CMD says so.
# In a sandbox tini isn't PID 1: -s registers it as a child subreaper, so it
# still reaps the zombies Electron leaves behind.
ENTRYPOINT ["tini", "-s", "--", "/opt/my-secure-claude-desktop/bin/my-secure-claude-desktop-session"]
CMD []
