Claude Desktop (the Linux beta of the Claude desktop app) is this sandbox's entrypoint. It runs on
the Wayland display named by `$SANDBOX_WAYLAND_SOCKET` (default `/run/display/wayland-0`) and shows
up as a window on the host. The sandbox session ends when the Claude Desktop window is closed.

The project mounted in the sandbox is the working directory; open it from the Code tab.

The sandbox has no GPU, so start Claude Desktop with `sandbox-claude-desktop`, which adds the
software-rendering flags and starts a D-Bus session with an unlocked gnome-keyring for the sign-in;
running `/usr/bin/claude-desktop` without them shows a blank window or forgets the sign-in.
Claude Desktop allows a single instance: a second launch only focuses the existing window.

Cowork is not available: it needs KVM, which the sandbox doesn't expose. Network access is limited
by the sandbox policy to Anthropic and Claude hosts.

Links open in an in-sandbox Chromium (`sandbox-chromium`), not the host browser: that's where the
sign-in happens, and its `claude://` link back reaches this Claude Desktop.
`/opt/my-secure-claude-desktop/bin/xdg-open` comes first on PATH and shadows the host-forwarding
shim in `/usr/local/bin`; call `/usr/local/bin/xdg-open` explicitly to open a link on the host.
Use `pkill -x claude-desktop` to stop the app; `pkill -f claude-desktop` also matches your own shell.
