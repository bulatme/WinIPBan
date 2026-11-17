# WinIPBan

**WinIPBan 1.0** is a lightweight, unofficial console interface for [DigitalRuby/IPBan](https://github.com/DigitalRuby/IPBan) on Windows Server. It makes IPBan easier to **install, configure, monitor, and manage** through a simple, keyboard-driven console menu.

**IPBan does the actual protection.** WinIPBan is a management interface, not a separate intrusion-prevention engine. It does not bundle IPBan or replace Windows Defender Firewall. Automatic blocking requires the [IPBan service](https://github.com/DigitalRuby/IPBan), which WinIPBan can install using the official upstream installer.

WinIPBan is an independent community project and is **not affiliated with or endorsed by DigitalRuby**.

## Features

- **Install and update IPBan** using its official installer.
- **Manage the service:** start, stop, restart, and check its status.
- **Configure protection:** set failed-login thresholds, ban duration, failure expiry, and the minimum interval between counted failures.
- **View active blocks:** list IP addresses currently blocked by IPBan in Windows Firewall, with 10 addresses per page.
- **Analyze attacks:** inspect failed logons, source IPs, attempted usernames, and failure codes from Windows Security events.
- **Review successful RDP logons** and inspect the history of a specific IP address.
- **Manually ban or unban IPs** through IPBan's supported control files.
- **Inspect logs and firewall rules**, including diagnostics when active blocks cannot be detected.
- **Export complete reports to Notepad** and keep generated files and configuration backups in the local `logs/` folder.

## Requirements

| Requirement | Details |
| --- | --- |
| Operating system | Windows Server 2022 or 2025 |
| PowerShell | Windows PowerShell 5.1 (included with Windows Server) |
| Permissions | Local administrator privileges |
| Firewall | Windows Defender Firewall |
| IPBan | Free/community edition; can be installed from WinIPBan |
| Event logging | Windows Security auditing for events `4624` and `4625` (for logon reports) |

WinIPBan is designed for Windows Server 2022 and 2025. It has undergone static checks, but has not been fully integration-tested on both versions.

## Getting started

1. Download or clone this repository.
2. Extract it to a writable folder, such as `C:\WinIPBan\`.
3. Run **`WinIPBan.cmd`** and approve the administrator prompt.
4. If IPBan is not installed, select **`U` — Install or update IPBan**.

WinIPBan requires no additional PowerShell modules. Its complete application and launcher are contained in **one file: `WinIPBan.cmd`**. Review the source before running administrative tools.

## Menu preview

```text
====================================================================
WinIPBan 1.0
Windows Server 2025 Standard (build 26100)
Unofficial console for DigitalRuby/IPBan
--------------------------------------------------------------------
IPBan service: Running
Upstream IPBan: https://github.com/DigitalRuby/IPBan
Report location: C:\Tools\WinIPBan\logs

SERVICE & CONFIGURATION
S: Status and current settings
C: Change ban settings
R: Start / restart / stop IPBan
U: Install or update IPBan
E: Edit IPBan configuration (Notepad copy)

SECURITY & ANALYTICS
B: Active blocked IPs (10 per page)
A: Failed logon statistics by IP / username
F: Recent failed logons (10 per page)
I: Inspect an IP address
M: Manually ban or unban an IP
H: Successful RDP logons (10 per page)
L: View IPBan logfile / Notepad export
D: Firewall discovery diagnostics

Q: Quit
Please choose an option:
```

## Reports and data

Generated reports, editable configuration copies, and backups are stored in the **`logs/` directory next to `WinIPBan.cmd`**. The application does not automatically delete older reports.

IPBan's own configuration and service logs stay in its installation directory (usually `C:\Program Files\IPBan\`). Windows Security events remain in the Windows Event Log, while active IP blocks are enforced through Windows Firewall.

The `logs/` directory may contain IP addresses, usernames, and configuration details. **Do not commit its contents to a public repository.** Generated files are excluded by `.gitignore`.

## Notes and limitations

- Active blocked-IP counts are based on enabled inbound IPBan block rules in Windows Firewall. Custom rules or IPBan Pro filtering backends may not be detected. The diagnostics menu helps investigate missing counts.
- CIDR ranges are reported separately from individual IP addresses. The blocked-IP list is sorted by address, not by ban time.
- One connection may generate multiple Windows or RDP failure events. Event counts are not necessarily equal to distinct password attempts.
- Windows logs can show attempted **usernames**, but not the passwords attackers entered.
- Event searches have limits to avoid excessive memory use. Recently loaded failure data may be cached for up to five minutes.
- Manual ban and unban actions are queued for IPBan to process; a queued request does not mean that the firewall has already changed.
- Incorrect ban settings can block your own remote IP. Keep an alternative recovery method, such as your hosting provider's remote console.

## Security

WinIPBan runs with administrator privileges. Inspect its source before use and see [SECURITY.md](SECURITY.md) for security guidance. Sanitize IP addresses, usernames, and server details before sharing logs or screenshots publicly.

## License and attribution

WinIPBan's original wrapper code is available under the [MIT License](LICENSE).

**[DigitalRuby/IPBan](https://github.com/DigitalRuby/IPBan)** is a separate, independently maintained project and provides the underlying IP banning functionality. IPBan is also licensed under MIT; its code and binaries are **not included** in this repository. All credit for IPBan belongs to its respective authors and contributors.

For information about the blocking engine, configuration options, and upstream releases, visit the [official IPBan repository](https://github.com/DigitalRuby/IPBan).
