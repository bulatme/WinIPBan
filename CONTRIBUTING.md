# Contributing to WinIPBan

Issues, feedback and pull requests are welcome. WinIPBan is an **unofficial convenience frontend for [DigitalRuby/IPBan](https://github.com/DigitalRuby/IPBan)** intended to remain a **single-file, dependency-free** Windows PowerShell 5.1 application. IPBan performs the actual blocking.

- Preserve compatibility with Windows Server 2022 and 2025 / Windows PowerShell 5.1.
- Keep **one executable launch file** (`WinIPBan.cmd`) and all user-facing messages in English.
- Keep all generated output under `logs/`; do not embed telemetry or transmit reports remotely.
- Prefer clear, recoverable operations over silently editing IPBan state or firewall rules.
- Update README when behavior changes. Validate the modified code on Windows PowerShell 5.1 and, when possible, against a test IPBan installation before distributing it. No test scripts are included in public releases.
- Exclude real logs, server addresses, credentials and configuration backups from commits, example output and issues.

This project is independent of DigitalRuby/IPBan. Submit issues about IPBan itself to the [original upstream project](https://github.com/DigitalRuby/IPBan).
