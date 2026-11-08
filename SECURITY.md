# Security policy

## Reporting a vulnerability

Please **do not open a public issue** for a security problem. Use GitHub's private reporting instead:
go to the repository's **Security** tab and choose **Report a vulnerability**. Include the FolderServe version, what you did and what you saw,
and, if you can, a minimal way to reproduce it.

This is a one-person project, so I'll do my best to reply within a week and keep you updated until it is fixed. Please give me a reasonable time to ship a fix before you share details publicly.

## Supported versions

Only the latest release gets fixes. FolderServe tells you when a newer release exists (Settings ▸ Check for updates).

## What is in scope

FolderServe serves local folders over HTTP, so the interesting problems are about what a web page or another machine can reach. Examples:

- reading files outside the served folder (path traversal, symlinks, encoded paths);
- reaching a server from a web page or another device when it should not be reachable (DNS rebinding, the `Host` header policy, the CORS and cross-origin rules,
  the Share option);
- the proxy forwarding to places it should not, or leaking headers it should not;
- the app writing request data to disk, or reading folders it was not given;
- problems with the signed release or the update check opening the wrong address.

## Good to know

- Servers listen on `127.0.0.1` only, unless you turn on **Share** for a folder. Then everyone on your network can reach that folder and its proxy rules.
- Request headers and bodies, including `Authorization` and cookies, are shown unmasked in Activity (like browser dev tools) and are kept in memory only.
- The update check asks GitHub for the latest release and sends nothing else. It never installs anything.
