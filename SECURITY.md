# Security policy

WinIPBan is an unofficial administrator-facing **frontend to [DigitalRuby/IPBan](https://github.com/DigitalRuby/IPBan)**, for easier installation, configuration and monitoring. **The upstream IPBan service performs the actual protection and blocking.** It is **not** an RDP proxy, firewall engine, endpoint antivirus or replacement for network hardening.

- Review the single `WinIPBan.cmd` file before executing it with elevation.
- Treat `logs/` contents as sensitive; they can contain source IP addresses, account names, copies of configuration and downloaded installer scripts. Do not commit or publish them.
- The update operation downloads an **upstream** script from GitHub and explicitly asks the administrator to review it in Notepad and confirm execution. Review it before approving.
- The service can block your own source IP if the configured login-failure threshold is too strict. Retain out-of-band/KVM access.
- Event 4625 alone cannot prove an RDP-specific attack or show what password was typed.
- Manual ban/unban actions are queued with IPBan and are not instant firewall changes.

For a security issue affecting WinIPBan, avoid posting proof-of-concept exploits or real logs in public issues. Use your repository's GitHub private vulnerability reporting once enabled; otherwise request a private reporting channel from the maintainer.

WinIPBan is an independent community project and is not supported by DigitalRuby/IPBan.
