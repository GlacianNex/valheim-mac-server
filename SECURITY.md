# Security and data safety

Please report exploitable vulnerabilities privately using GitHub's private vulnerability reporting if enabled, or contact the maintainer privately before publishing sensitive details. Do not include real passwords, join codes, player IDs, logs, or world saves in a public issue.

The core safety boundaries are copy-only imports, app-owned directories, strict process ownership before signaling, and refusing to start on occupied ports. The app never force-kills a timed-out server.

Passwords are stored in the user's private profile database (0600) and passed to the dedicated server as required by its command-line interface. The manager is not a protection boundary against other software running as the same macOS user. Do not share your profile database or unredacted logs.

SteamCMD and server downloads come from Valve. Server signatures and supported binary architectures are checked before an installation replaces the app-managed runtime. No game binaries or credentials belong in the source repository or release ZIP.
