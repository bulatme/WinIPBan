@echo off
setlocal
set "WINIPBAN_SCRIPT=%~f0"
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$f=$env:WINIPBAN_SCRIPT; $t=[System.IO.File]::ReadAllText($f); $m='# WINIPBAN_POWERSHELL_START'; $i=$t.LastIndexOf($m); if($i -lt 0){throw 'Invalid WinIPBan file'}; Invoke-Expression ($t.Substring($i))"
set "WINIPBAN_EXIT=%ERRORLEVEL%"
endlocal & exit /b %WINIPBAN_EXIT%
# WINIPBAN_POWERSHELL_START
# WinIPBan v1.0 - all-in-one CMD + Windows PowerShell 5.1 application.
# Unofficial convenience frontend for installing, configuring and monitoring DigitalRuby/IPBan.
# All blocking and detection are performed by IPBan, not by WinIPBan.
# Upstream project: https://github.com/DigitalRuby/IPBan

$ErrorActionPreference = 'Stop'
$script:AppVersion = '1.0'
$script:AppDir = Split-Path -Path $env:WINIPBAN_SCRIPT -Parent
$script:LogsDir = Join-Path $script:AppDir 'logs'
$script:InstallDir = Join-Path $env:ProgramFiles 'IPBan'
$script:ConfigPath = Join-Path $script:InstallDir 'ipban.config'
$script:OverridePath = Join-Path $script:InstallDir 'ipban.override.config'
$script:LogPath = Join-Path $script:InstallDir 'logfile.txt'
$script:LastAttempts = @()
$script:LastPeriod = 0
$script:LastLoadedAt = $null
$script:FailureCacheMinutes = 5
$script:LastTruncated = $false
$script:SkipMenuPause = $false
$script:WindowsLabel = ''


function Get-WindowsVersionLabel {
	try
	{
		$os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
		$caption = ([string]$os.Caption).Trim() -replace '^Microsoft\s+', ''
		$build = ([string]$os.BuildNumber).Trim()

		if ([string]::IsNullOrWhiteSpace($caption))
		{
			throw 'Windows version is unavailable.'
		}

		if ([string]::IsNullOrWhiteSpace($build))
		{
			return $caption
		}

		return ('{0} (build {1})' -f $caption, $build)
	}
	catch
	{
		return ('Windows {0}' -f [System.Environment]::OSVersion.Version)
	}
}

function Write-Banner([string]$Title) {
	Write-Host ''
	Write-Host ('  {0}' -f ('=' * 68)) -ForegroundColor DarkCyan
	Write-Host ('  WinIPBan {0}' -f $script:AppVersion) -ForegroundColor Cyan
	Write-Host ('  {0}' -f $script:WindowsLabel) -ForegroundColor DarkGray
	Write-Host ('  {0}' -f $Title) -ForegroundColor White
	Write-Host ('  {0}' -f ('-' * 68)) -ForegroundColor DarkCyan
}

function Write-Notice([string]$Message) {
	Write-Host ('  [!] {0}' -f $Message) -ForegroundColor Yellow
}

function Write-Success([string]$Message) {
	Write-Host ('  [+] {0}' -f $Message) -ForegroundColor Green
}

function Write-MenuItem([string]$Key, [string]$Title) {
	Write-Host ('  {0}: ' -f $Key) -NoNewline -ForegroundColor Cyan
	Write-Host $Title
}

function Ensure-LogsDirectory {
	if (-not (Test-Path -LiteralPath $script:LogsDir -PathType Container))
	{
		[void](New-Item -Path $script:LogsDir -ItemType Directory -Force -ErrorAction Stop)
	}
}

function Show-Pages([object[]]$Items, [string]$Title, [scriptblock]$Renderer, [scriptblock]$Exporter, [string[]]$Summary = @()) {
	$itemsArray = @($Items)
	$pageSize = 10
	$page = 0

	while ($true)
	{
		Clear-Host
		Write-Banner $Title

		foreach ($line in $Summary)
		{
			Write-Host ('  {0}' -f $line)
		}

		$offset = $page * $pageSize
		$rows = @($itemsArray | Select-Object -Skip $offset -First $pageSize)
		Write-Host ''

		if ($rows.Count -eq 0)
		{
			Write-Notice 'No records to display.'
		}
		else
		{
			& $Renderer $rows $offset
		}

		$remaining = [Math]::Max(0, $itemsArray.Count - ($offset + $rows.Count))
		$rangeStart = 0

		if ($itemsArray.Count -gt 0)
		{
			$rangeStart = $offset + 1
		}

		Write-Host ''
		Write-Host ('  Showing {0}-{1} of {2}  |  {3} more' -f $rangeStart, ($offset + $rows.Count), $itemsArray.Count, $remaining) -ForegroundColor DarkGray
		Write-Host ''
		Write-MenuItem 'N' 'Next 10'
		Write-MenuItem 'P' 'Previous 10'
		Write-MenuItem 'E' 'Export complete list to Notepad (logs folder)'
		Write-MenuItem 'Q' 'Back'
		$choice = (Read-Host '  Please choose an option').Trim().ToUpperInvariant()

		switch ($choice)
		{
			'N'
			{
				if ($remaining -gt 0)
				{
					$page++
				}
			}
			'P'
			{
				if ($page -gt 0)
				{
					$page--
				}
			}
			'E'
			{
				& $Exporter
				[void](Read-Host '  Press Enter to continue')
			}
			'Q'
			{
				$script:SkipMenuPause = $true
				return
			}
			default
			{
				Write-Notice 'Unknown option.'
			}
		}
	}
}

function Pause-Menu {
	[void](Read-Host "`nPress Enter to continue")
}

function Confirm-Action([string]$Message) {
	$answer = Read-Host "$Message [y/N]"
	return $answer -match '^(y|yes)$'
}

function Ensure-Admin {
	$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
	$principal = New-Object Security.Principal.WindowsPrincipal($identity)

	if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
	{
		Write-Notice 'Administrator privileges are required. Requesting elevation...'

		try
		{
			Start-Process -FilePath $env:WINIPBAN_SCRIPT -Verb RunAs -WorkingDirectory $script:AppDir -ErrorAction Stop
		}
		catch
		{
			Write-Notice ('Elevation failed: {0}' -f $_.Exception.Message)
			[void](Read-Host 'Press Enter to exit')
		}

		return $false
	}

	return $true
}

function Get-IPBanService {
	return Get-Service -Name 'IPBan' -ErrorAction SilentlyContinue
}

function Get-ConfigValue([string]$Key) {
	$value = $null

	foreach ($path in @($script:ConfigPath, $script:OverridePath))
	{
		if (Test-Path -LiteralPath $path)
		{
			[xml]$document = Get-Content -LiteralPath $path -Raw -Encoding UTF8

			foreach ($node in @($document.SelectNodes('/configuration/appSettings/add')))
			{
				if ($node.GetAttribute('key') -eq $Key)
				{
					$value = $node.GetAttribute('value')
				}
			}
		}
	}

	return $value
}

function Backup-Config([string]$Path) {
	if (-not (Test-Path -LiteralPath $Path))
	{
		return
	}

	Ensure-LogsDirectory
	$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
	$dest = Join-Path $script:LogsDir ('{0}.{1}.bak' -f (Split-Path $Path -Leaf), $stamp)
	Copy-Item -LiteralPath $Path -Destination $dest -Force
	Write-Host ('  Backup: {0}' -f $dest) -ForegroundColor DarkGray
}

function Set-ConfigValue([string]$Key, [string]$Value) {
	# Edit the effective setting: override.config takes precedence over ipban.config.
	$target = $null

	foreach ($path in @($script:ConfigPath, $script:OverridePath))
	{
		if (-not (Test-Path -LiteralPath $path))
		{
			continue
		}

		$xml = New-Object System.Xml.XmlDocument
		$xml.PreserveWhitespace = $true
		$xml.Load($path)

		foreach ($node in @($xml.SelectNodes('/configuration/appSettings/add')))
		{
			if ($node.GetAttribute('key') -eq $Key)
			{
				$target = $path
			}
		}
	}

	if ($null -eq $target)
	{
		throw "Setting '$Key' was not found in the IPBan configuration."
	}

	$xml = New-Object System.Xml.XmlDocument
	$xml.PreserveWhitespace = $true
	$xml.Load($target)

	foreach ($node in @($xml.SelectNodes('/configuration/appSettings/add')))
	{
		if ($node.GetAttribute('key') -eq $Key)
		{
			if ($node.GetAttribute('value') -eq $Value)
			{
				Write-Host 'The value is already set; no changes made.'
				return
			}

			Backup-Config $target
			$node.SetAttribute('value', $Value)
			$xml.Save($target)
			Write-Host ('Updated: {0}' -f $target) -ForegroundColor Green
			return
		}
	}
}

function Show-Status {
	Write-Banner 'IPBan service and settings'
	$service = Get-IPBanService

	if ($null -eq $service)
	{
		Write-Host 'IPBan service is not installed.' -ForegroundColor Yellow
		return
	}

	$serviceInfo = Get-CimInstance -ClassName Win32_Service -Filter "Name='IPBan'"
	$exe = Join-Path $script:InstallDir 'DigitalRuby.IPBan.exe'
	$version = 'Unknown'

	if (Test-Path -LiteralPath $exe)
	{
		$version = (Get-Item -LiteralPath $exe).VersionInfo.ProductVersion
	}

	Write-Host ('Service status:        {0}' -f $service.Status)
	Write-Host ('Startup mode:          {0}' -f $serviceInfo.StartMode)
	Write-Host ('IPBan version:         {0}' -f $version)
	Write-Host ('Install path:          {0}' -f $script:InstallDir)
	Write-Host ('Failures before ban:   {0}' -f (Get-ConfigValue 'FailedLoginAttemptsBeforeBan'))
	Write-Host ('Ban duration:          {0}' -f (Get-ConfigValue 'BanTime'))
	Write-Host ('Failure expiry:        {0}' -f (Get-ConfigValue 'ExpireTime'))
	Write-Host ('Minimum gap:           {0}' -f (Get-ConfigValue 'MinimumTimeBetweenFailedLoginAttempts'))
	Write-Host ('Firewall rule prefix:  {0}' -f (Get-ConfigValue 'FirewallRulePrefix'))
}

function Restart-IPBan {
	if ($null -eq (Get-IPBanService))
	{
		Write-Host 'IPBan is not installed.' -ForegroundColor Yellow
		return
	}

	Restart-Service -Name 'IPBan' -Force
	(Get-Service -Name 'IPBan').WaitForStatus('Running', [timespan]::FromSeconds(30))
	Write-Host 'IPBan service restarted.' -ForegroundColor Green
}

function Read-Integer([string]$Prompt, [int]$Minimum, [int]$Maximum) {
	while ($true)
	{
		$raw = (Read-Host ('{0} [Q=Cancel]' -f $Prompt)).Trim()

		if ($raw.ToUpperInvariant() -eq 'Q')
		{
			$script:SkipMenuPause = $true
			return $null
		}

		$number = 0

		if (-not [int]::TryParse($raw, [ref]$number))
		{
			Write-Notice 'Enter a whole number, or Q to cancel.'
			continue
		}

		if ($number -lt $Minimum -or $number -gt $Maximum)
		{
			Write-Notice ('Allowed range: {0}-{1}. Enter Q to cancel.' -f $Minimum, $Maximum)
			continue
		}

		return $number
	}
}

function Edit-Settings {
	if (-not (Test-Path -LiteralPath $script:ConfigPath))
	{
		Write-Host 'Install IPBan first.' -ForegroundColor Yellow
		return
	}

	Show-Status
	Write-Host ''
	Write-MenuItem 'F' 'Failed logins before ban'
	Write-MenuItem 'B' 'Ban duration (days)'
	Write-MenuItem 'E' 'Expire unbanned failures after (days)'
	Write-MenuItem 'M' 'Minimum interval between counted failures (seconds)'
	Write-MenuItem 'Q' 'Back'
	$choice = (Read-Host '  Please choose an option').Trim().ToUpperInvariant()

	if ($choice -eq 'Q')
	{
		$script:SkipMenuPause = $true
		return
	}

	$key = $null
	$value = $null

	switch ($choice)
	{
		'F'
		{
			$n = Read-Integer 'Threshold (1-100)' 1 100

			if ($null -ne $n)
			{
				$key = 'FailedLoginAttemptsBeforeBan'
				$value = [string]$n
			}
		}
		'B'
		{
			$n = Read-Integer 'Ban for how many days (1-9999)' 1 9999

			if ($null -ne $n)
			{
				$key = 'BanTime'
				$value = '{0:00}:00:00:00' -f $n
			}
		}
		'E'
		{
			$n = Read-Integer 'Keep unbanned failures for how many days (1-365)' 1 365

			if ($null -ne $n)
			{
				$key = 'ExpireTime'
				$value = '{0:00}:00:00:00' -f $n
			}
		}
		'M'
		{
			$n = Read-Integer 'Minimum interval (1-3600 seconds)' 1 3600

			if ($null -ne $n)
			{
				$key = 'MinimumTimeBetweenFailedLoginAttempts'
				$value = ([timespan]::FromSeconds($n)).ToString('dd\:hh\:mm\:ss')
			}
		}
	}

	if ($null -eq $key)
	{
		return
	}

	Write-Host ('{0}: {1} -> {2}' -f $key, (Get-ConfigValue $key), $value)

	if (Confirm-Action 'Save the change and restart IPBan?')
	{
		Set-ConfigValue $key $value
		Restart-IPBan
	}
}

function Test-IpBanBlockRule($Rule, [string]$Prefix) {
	# Firewall rule Name may be a GUID; DisplayName may be IPBan_Block_0.
	$prefixes = @('IPBan_')

	if (-not [string]::IsNullOrWhiteSpace($Prefix) -and $Prefix -notin $prefixes)
	{
		$prefixes += $Prefix
	}

	foreach ($item in $prefixes)
	{
		$pattern = ('^{0}Block_' -f [regex]::Escape($item))

		if ([string]$Rule.Name -match $pattern -or [string]$Rule.DisplayName -match $pattern)
		{
			return $true
		}
	}

	return $false
}

function Get-FirewallSnapshot {
	$prefix = Get-ConfigValue 'FirewallRulePrefix'
	$store = 'ActiveStore'
	$allRules = @()

	try
	{
		# ActiveStore is the effective set, not just the local persistent rules.
		$allRules = @(Get-NetFirewallRule -PolicyStore ActiveStore -ErrorAction Stop)
	}
	catch
	{
		$store = 'Default'
		Write-Host 'ActiveStore query failed; trying default firewall policy store.' -ForegroundColor Yellow
		$allRules = @(Get-NetFirewallRule -ErrorAction Stop)
	}

	$matching = @($allRules | Where-Object { Test-IpBanBlockRule $_ $prefix })
	$enabled = @($matching | Where-Object {
		[string]$_.Action -eq 'Block' -and [string]$_.Direction -eq 'Inbound' -and [string]$_.Enabled -eq 'True'
	})

	$ipAddresses = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	$ranges = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	$failures = New-Object 'System.Collections.Generic.List[string]'
	$details = New-Object 'System.Collections.Generic.List[object]'
	$anyRemote = 0

	foreach ($rule in $matching)
	{
		$active = $enabled -contains $rule
		$remote = @()
		$errorText = ''

		try
		{
			# The pipeline form is documented by Microsoft and works with ActiveStore objects.
			$filters = @($rule | Get-NetFirewallAddressFilter -ErrorAction Stop)

			if ($filters.Count -eq 0)
			{
				$errorText = 'No address filter returned'
				$failures.Add(('{0}: {1}' -f $rule.DisplayName, $errorText))
			}

			foreach ($filter in $filters)
			{
				$remote += @($filter.RemoteAddress)
			}
		}
		catch
		{
			$errorText = $_.Exception.Message
			$failures.Add(('{0}: {1}' -f $rule.DisplayName, $errorText))
		}

		$actualCount = 0

		foreach ($entry in $remote)
		{
			foreach ($part in ([string]$entry -split ','))
			{
				$address = $part.Trim()

				if ([string]::IsNullOrWhiteSpace($address))
				{
					continue
				}

				if ($address -eq 'Any')
				{
					if ($active)
					{
						$anyRemote++
					}
					continue
				}

				$actualCount++

				if (-not $active)
				{
					continue
				}

				$parsedIP = $null

				if ([System.Net.IPAddress]::TryParse($address, [ref]$parsedIP))
				{
					[void]$ipAddresses.Add($parsedIP.ToString())
				}
				else
				{
					[void]$ranges.Add($address)
				}
			}
		}

		$details.Add([PSCustomObject]@{
			Name = $rule.Name
			DisplayName = $rule.DisplayName
			Enabled = $rule.Enabled
			Action = $rule.Action
			Direction = $rule.Direction
			RemoteEntries = $actualCount
			Error = $errorText
		})
	}

	return [PSCustomObject]@{
		Store = $store
		ScannedRules = $allRules.Count
		MatchingRules = $matching.Count
		ActiveBlockRules = $enabled.Count
		IPs = @($ipAddresses | Sort-Object)
		Ranges = @($ranges | Sort-Object)
		AnyRemoteRules = $anyRemote
		Details = @($details.ToArray())
		Errors = @($failures.ToArray())
	}
}

function Open-Report([string]$Title, [string[]]$Lines) {
	Ensure-LogsDirectory
	$filename = '{0}_{1}.txt' -f $Title, (Get-Date -Format 'yyyyMMdd_HHmmss_fff')
	$path = Join-Path $script:LogsDir $filename
	$Lines | Set-Content -LiteralPath $path -Encoding UTF8 -ErrorAction Stop
	Start-Process -FilePath 'notepad.exe' -ArgumentList ('"{0}"' -f $path)
	Write-Success ('Saved and opened: {0}' -f $path)
	Write-Host '  Reports are snapshots; editing them does not change IPBan.' -ForegroundColor DarkGray
}

function Show-Bans {
	Write-Host '  Reading effective Windows Firewall rules...' -ForegroundColor Cyan
	$snapshot = Get-FirewallSnapshot
	$summary = @(
		('Firewall store: {0}; scanned rules: {1}' -f $snapshot.Store, $snapshot.ScannedRules),
		('IPBan rules: {0}; active inbound block rules: {1}' -f $snapshot.MatchingRules, $snapshot.ActiveBlockRules),
		('Unique blocked IPs: {0}; ranges/CIDRs: {1}' -f $snapshot.IPs.Count, $snapshot.Ranges.Count)
	)

	if ($snapshot.MatchingRules -eq 0)
	{
		$summary += 'WARNING: No matching rules: current ban count is UNKNOWN, not confirmed zero.'
	}

	if ($snapshot.Errors.Count -gt 0)
	{
		$summary += ('WARNING: Failed to read {0} rule filters; count may be incomplete.' -f $snapshot.Errors.Count)
	}

	if ($snapshot.AnyRemoteRules -gt 0)
	{
		$summary += 'WARNING: A block rule uses RemoteAddress=Any; cannot count individual IPs.'
	}

	$export = {
		$lines = @(
			'WinIPBan - current Windows Firewall IPBan block entries',
			('Generated: {0}' -f (Get-Date)),
			('Firewall store: {0}' -f $snapshot.Store),
			('Active block rules: {0}' -f $snapshot.ActiveBlockRules),
			('Individual IPs: {0}; ranges/CIDRs: {1}' -f $snapshot.IPs.Count, $snapshot.Ranges.Count),
			'',
			'=== INDIVIDUAL IP ADDRESSES ==='
		) + @($snapshot.IPs) + @('', '=== CIDRS AND RANGES ===') + @($snapshot.Ranges)
		Open-Report 'WinIPBan-Blocked' $lines
	}.GetNewClosure()

	Show-Pages -Items @($snapshot.IPs) -Title 'Active blocked IP addresses (sorted by IP)' -Summary $summary -Renderer {
		param($rows, $offset)

		for ($i = 0; $i -lt $rows.Count; $i++)
		{
			Write-Host ('  {0,4}. {1}' -f ($offset + $i + 1), $rows[$i])
		}
	} -Exporter $export
}

function Show-FirewallDiagnostics {
	$snapshot = Get-FirewallSnapshot
	$summary = @(
		('Store: {0}; scanned: {1}; matched: {2}; active blocks: {3}' -f $snapshot.Store, $snapshot.ScannedRules, $snapshot.MatchingRules, $snapshot.ActiveBlockRules),
		('Read errors: {0}' -f $snapshot.Errors.Count)
	)
	$rows = @($snapshot.Details)
	$export = {
		$lines = @('WinIPBan firewall diagnostics', ('Generated: {0}' -f (Get-Date)), ('Store: {0}' -f $snapshot.Store), ('Rules scanned: {0}' -f $snapshot.ScannedRules), '')
		$lines += @($snapshot.Details | Format-List * | Out-String)
		$lines += @('=== ERRORS ===') + @($snapshot.Errors)
		Open-Report 'WinIPBan-Firewall-Diagnostics' $lines
	}.GetNewClosure()

	Show-Pages -Items $rows -Title 'Firewall rule diagnostics' -Summary $summary -Renderer {
		param($entries, $offset)
		$entries | Select-Object DisplayName, Enabled, Action, Direction, RemoteEntries, Error | Format-Table -AutoSize | Out-Host
	} -Exporter $export

}

function Read-FailureEvents([int]$Days) {
	$maxEvents = 50000
	$since = (Get-Date).AddDays(-$Days)
	$events = @()

	try
	{
		$events = @(Get-WinEvent -FilterHashtable @{
			LogName = 'Security'
			Id = 4625
			StartTime = $since
		} -MaxEvents $maxEvents -ErrorAction Stop)
	}
	catch
	{
		if ($_.Exception.Message -notmatch 'No events were found|No matching events')
		{
			throw ('Unable to load failed logon events (Security 4625). Check administrator permissions and Windows Security log access. Details: {0}' -f $_.Exception.Message)
		}
	}

	$script:LastTruncated = $events.Count -ge $maxEvents
	$records = New-Object 'System.Collections.Generic.List[object]'

	foreach ($event in $events)
	{
		[xml]$xml = $event.ToXml()
		$data = @{}

		foreach ($node in @($xml.Event.EventData.Data))
		{
			$data[$node.Name] = $node.'#text'
		}

		$ip = [string]$data['IpAddress']
		$type = [string]$data['LogonType']

		if ([string]::IsNullOrWhiteSpace($ip) -or $ip -eq '-' -or $type -notin @('3', '10'))
		{
			continue
		}

		if ($ip.StartsWith('::ffff:'))
		{
			$ip = $ip.Substring(7)
		}

		$records.Add([PSCustomObject]@{
			Time = $event.TimeCreated
			IP = $ip
			User = [string]$data['TargetUserName']
			Type = $type
			Code = [string]$data['SubStatus']
		})
	}

	$script:LastAttempts = @($records.ToArray())
	$script:LastPeriod = $Days
	$script:LastLoadedAt = Get-Date
	return $script:LastAttempts
}

function Get-FailureEventsCached([int]$Days, [switch]$ForceRefresh) {
	$cacheFresh = $null -ne $script:LastLoadedAt -and
		$script:LastPeriod -eq $Days -and
		((Get-Date) - $script:LastLoadedAt).TotalMinutes -lt $script:FailureCacheMinutes

	if (-not $ForceRefresh -and $cacheFresh)
	{
		return $script:LastAttempts
	}

	Write-Host ('  Loading Windows Security failed logons (last {0} day(s), up to 50,000 events)...' -f $Days) -ForegroundColor Cyan
	return (Read-FailureEvents $Days)
}

function Get-DefaultFailurePeriod {
	if ($script:LastPeriod -ge 1 -and $script:LastPeriod -le 30)
	{
		return $script:LastPeriod
	}

	return 1
}

function Show-AttackStatistics {
	$days = Read-Integer 'Look back how many days (1-30)' 1 30

	if ($null -eq $days)
	{
		return
	}

	$records = @(Get-FailureEventsCached -Days $days -ForceRefresh)
	$ipGroups = @($records | Group-Object IP | Sort-Object Count -Descending)
	$userGroups = @($records | Group-Object User | Sort-Object Count -Descending)
	$invalidUsers = @($records | Where-Object { $_.Code -ieq '0xc0000064' }).Count
	$wrongPasswords = @($records | Where-Object { $_.Code -ieq '0xc000006a' }).Count

	$summary = @(
		('Window: last {0} days; events: {1}; source IPs: {2}' -f $days, $records.Count, $ipGroups.Count),
		('Unknown username: {0}; incorrect password: {1}' -f $invalidUsers, $wrongPasswords)
	)

	if ($script:LastTruncated)
	{
		$summary += 'WARNING: Security event cap (50,000) reached; statistics are incomplete.'
	}

	$summary += 'Event 4625, logon type 3 or 10; not necessarily exclusively RDP.'
	$export = {
		$lines = @('WinIPBan - failed logons and attempted usernames', ('Last {0} days' -f $days), ('Total: {0}; unique IPs: {1}' -f $records.Count, $ipGroups.Count), 'Windows does not log the passwords attempted.', '', 'IP | attempts | usernames | first seen | last seen')

		foreach ($group in $ipGroups)
		{
			$items = @($group.Group | Sort-Object Time)
			$userNames = @($items | Select-Object -ExpandProperty User -Unique | Select-Object -First 30)
			$lines += ('{0} | {1} | {2} | {3} | {4}' -f $group.Name, $group.Count, ($userNames -join ', '), $items[0].Time, $items[-1].Time)
		}

		$lines += @('', '=== ATTEMPTED USERNAMES ===', 'Username | attempts')

		foreach ($group in $userGroups)
		{
			$lines += ('{0} | {1}' -f $group.Name, $group.Count)
		}

		Open-Report 'WinIPBan-Attacks' $lines
	}.GetNewClosure()

	while ($true)
	{
		Clear-Host
		Write-Banner 'Failed logon statistics'

		foreach ($line in $summary)
		{
			Write-Host ('  {0}' -f $line)
		}

		Write-Host ''
		Write-Host '  Top 10 source IPs' -ForegroundColor Cyan
		$ipGroups | Select-Object -First 10 @{Name='Attempts';Expression={$_.Count}}, @{Name='IP';Expression={$_.Name}} | Format-Table -AutoSize | Out-Host
		Write-Host '  Top 10 attempted usernames' -ForegroundColor Cyan
		$userGroups | Select-Object -First 10 @{Name='Attempts';Expression={$_.Count}}, @{Name='Username';Expression={$_.Name}} | Format-Table -AutoSize | Out-Host
		Write-MenuItem 'I' 'Browse all source IPs (10 per page)'
		Write-MenuItem 'U' 'Browse all attempted usernames (10 per page)'
		Write-MenuItem 'E' 'Export full statistics to Notepad'
		Write-MenuItem 'Q' 'Back'
		$choice = (Read-Host '  Please choose an option').Trim().ToUpperInvariant()

		switch ($choice)
		{
			'I'
			{
				Show-Pages -Items $ipGroups -Title 'Attack sources by IP' -Summary $summary -Renderer {
					param($rows, $offset)
					$rows | Select-Object @{Name='Attempts';Expression={$_.Count}}, @{Name='IP';Expression={$_.Name}} | Format-Table -AutoSize | Out-Host
				} -Exporter $export
			}
			'U'
			{
				Show-Pages -Items $userGroups -Title 'Attempted usernames' -Summary $summary -Renderer {
					param($rows, $offset)
					$rows | Select-Object @{Name='Attempts';Expression={$_.Count}}, @{Name='Username';Expression={$_.Name}} | Format-Table -AutoSize | Out-Host
				} -Exporter $export
			}
			'E'
			{
				& $export
				Pause-Menu
			}
			'Q'
			{
				$script:SkipMenuPause = $true
				return
			}
			default
			{
				Write-Notice 'Unknown option.'
			}
		}
	}
}

function Show-RecentAttempts {
	$days = Get-DefaultFailurePeriod
	$items = @(Get-FailureEventsCached -Days $days | Sort-Object Time -Descending)
	$summary = @(
		('Lookback: last {0} day(s); failed logons: {1}' -f $days, $items.Count),
		('Loaded: {0}; cache refreshes after {1} minutes.' -f $script:LastLoadedAt, $script:FailureCacheMinutes),
		'Windows Security event 4625, logon type 3 or 10; not necessarily RDP only.'
	)

	if ($script:LastTruncated)
	{
		$summary += 'WARNING: 50,000-event cap reached; older entries may be missing.'
	}

	$export = {
		$lines = @('WinIPBan - failed logon history', ('Generated: {0}' -f (Get-Date)), ('Lookback: last {0} day(s)' -f $days), 'Date | IP | username | logon type | substatus')
		$lines += @($items | ForEach-Object {
			'{0:yyyy-MM-dd HH:mm:ss} | {1} | {2} | {3} | {4}' -f $_.Time, $_.IP, $_.User, $_.Type, $_.Code
		})
		Open-Report 'WinIPBan-Attempts' $lines
	}.GetNewClosure()

	Show-Pages -Items $items -Title 'Recent failed logons (newest first)' -Summary $summary -Renderer {
		param($rows, $offset)
		$rows | Select-Object Time, IP, User, Type, Code | Format-Table -AutoSize | Out-Host
	} -Exporter $export
}

function Show-SuccessfulRDP {
	$days = Read-Integer 'Look back how many days (1-30)' 1 30

	if ($null -eq $days)
	{
		return
	}

	$events = @()

	try
	{
		$events = @(Get-WinEvent -FilterHashtable @{
			LogName = 'Security'
			Id = 4624
			StartTime = (Get-Date).AddDays(-$days)
		} -MaxEvents 30000 -ErrorAction Stop)
	}
	catch
	{
		if ($_.Exception.Message -notmatch 'No events were found|No matching events')
		{
			throw
		}
	}

	$rows = New-Object 'System.Collections.Generic.List[object]'

	foreach ($event in $events)
	{
		[xml]$xml = $event.ToXml()
		$data = @{}

		foreach ($node in @($xml.Event.EventData.Data))
		{
			$data[$node.Name] = $node.'#text'
		}

		if ([string]$data['LogonType'] -eq '10')
		{
			$rows.Add([PSCustomObject]@{
				Time = $event.TimeCreated
				User = [string]$data['TargetUserName']
				IP = [string]$data['IpAddress']
			})
		}
	}

	$items = @($rows.ToArray() | Sort-Object Time -Descending)
	$summary = @(('Successful RDP logons: {0}' -f $items.Count))

	if ($events.Count -ge 30000)
	{
		$summary += 'WARNING: Event limit reached; this report may be incomplete.'
	}

	$export = {
		$lines = @('WinIPBan - successful RDP logons', ('Generated: {0}' -f (Get-Date)), 'Date | Username | IP')
		$lines += @($items | ForEach-Object {
			'{0:yyyy-MM-dd HH:mm:ss} | {1} | {2}' -f $_.Time, $_.User, $_.IP
		})
		Open-Report 'WinIPBan-SuccessfulRDP' $lines
	}.GetNewClosure()

	Show-Pages -Items $items -Title 'Successful RDP logons (Security 4624)' -Summary $summary -Renderer {
		param($records, $offset)
		$records | Select-Object Time, User, IP | Format-Table -AutoSize | Out-Host
	} -Exporter $export
}

function Read-ValidIP {
	$value = (Read-Host 'IP address [Q=Back]').Trim()

	if ($value.ToUpperInvariant() -eq 'Q')
	{
		$script:SkipMenuPause = $true
		return $null
	}

	$parsedIP = $null

	if (-not [System.Net.IPAddress]::TryParse($value, [ref]$parsedIP))
	{
		Write-Host 'Invalid IP address.' -ForegroundColor Yellow
		return $null
	}

	return $parsedIP.ToString()
}

function Inspect-IP {
	$ip = Read-ValidIP

	if ($null -eq $ip)
	{
		return
	}

	$bans = Get-FirewallSnapshot
	Write-Host ('Exact IP in active block rules: {0}' -f ($bans.IPs -contains $ip))
	Write-Host 'Membership in CIDR/range rules is not evaluated by this check.' -ForegroundColor DarkGray

	$days = Get-DefaultFailurePeriod
	$events = @(Get-FailureEventsCached -Days $days)
	$matches = @($events | Where-Object { $_.IP -eq $ip })
	Write-Host ('Failed logons in the last {0} day(s): {1}' -f $days, $matches.Count)

	if ($script:LastTruncated)
	{
		Write-Notice '50,000-event cap reached; results may be incomplete.'
	}
	$matches | Group-Object User | Sort-Object Count -Descending | Select-Object @{Name='Username';Expression={$_.Name}}, Count | Format-Table -AutoSize | Out-Host
	$matches | Sort-Object Time -Descending | Select-Object -First 15 Time, User, Code | Format-Table -AutoSize | Out-Host
}

function Queue-IPAction([string]$Action) {
	if ($null -eq (Get-IPBanService))
	{
		Write-Host 'IPBan is not installed.' -ForegroundColor Yellow
		return
	}

	$ip = Read-ValidIP

	if ($null -eq $ip)
	{
		return
	}

	if (-not (Confirm-Action "Queue $Action for $ip?"))
	{
		return
	}

	$file = Join-Path $script:InstallDir $Action
	Add-Content -LiteralPath $file -Value $ip -Encoding ASCII
	Write-Host "Request queued in $file. IPBan will process it on its next cycle." -ForegroundColor Green
	Write-Host 'This is not an instant firewall change; check the current ban list afterward.' -ForegroundColor DarkGray
}

function Open-Logs {
	if (-not (Test-Path -LiteralPath $script:LogPath))
	{
		Write-Notice 'Original IPBan logfile.txt not found.'
		return
	}

	Write-Banner 'IPBan service log'
	Write-Host '  Last 10 lines:' -ForegroundColor Cyan
	Get-Content -LiteralPath $script:LogPath -Tail 10 | Out-Host

	if (Confirm-Action 'Export a snapshot of the entire IPBan logfile to logs and open it?')
	{
		# Keep upstream files in Program Files; all Notepad-visible copies live in ./logs.
		Open-Report 'WinIPBan-IPBanLog' @(Get-Content -LiteralPath $script:LogPath)
	}
}

function Open-Config {
	$paths = @($script:ConfigPath)

	if (Test-Path -LiteralPath $script:OverridePath)
	{
		$paths += $script:OverridePath
	}

	if (-not (Test-Path -LiteralPath $script:ConfigPath))
	{
		Write-Notice 'IPBan configuration not found.'
		return
	}

	Write-Banner 'Edit configuration'
	Write-MenuItem 'M' 'ipban.config (main configuration)'

	if ($paths.Count -gt 1)
	{
		Write-MenuItem 'O' 'ipban.override.config (takes precedence)'
	}

	Write-MenuItem 'Q' 'Cancel'
	$selection = (Read-Host '  Please choose an option').Trim().ToUpperInvariant()

	if ($selection -eq 'Q')
	{
		$script:SkipMenuPause = $true
		return
	}

	if ($selection -notin @('M', 'O') -or ($selection -eq 'O' -and $paths.Count -lt 2))
	{
		Write-Notice 'Invalid choice.'
		return
	}

	if ($selection -eq 'M')
	{
		$target = $script:ConfigPath
	}
	else
	{
		$target = $script:OverridePath
	}
	Ensure-LogsDirectory
	$filename = 'WinIPBan-ConfigEdit_{0}_{1}.xml' -f (Split-Path -Path $target -Leaf), (Get-Date -Format 'yyyyMMdd_HHmmss_fff')
	$workingCopy = Join-Path $script:LogsDir $filename
	Copy-Item -LiteralPath $target -Destination $workingCopy -ErrorAction Stop
	$oldHash = (Get-FileHash -LiteralPath $workingCopy -Algorithm SHA256).Hash
	Write-Host ('  Editing a copy in: {0}' -f $workingCopy) -ForegroundColor DarkGray
	Start-Process -FilePath 'notepad.exe' -ArgumentList ('"{0}"' -f $workingCopy) -Wait

	$newHash = (Get-FileHash -LiteralPath $workingCopy -Algorithm SHA256).Hash

	if ($newHash -eq $oldHash)
	{
		Write-Host '  No changes detected. The original was not modified.'
		return
	}

	$test = New-Object System.Xml.XmlDocument
	$test.Load($workingCopy)

	if (Confirm-Action ('Apply this edited copy to {0}?' -f $target))
	{
		Backup-Config $target
		Copy-Item -LiteralPath $workingCopy -Destination $target -Force -ErrorAction Stop
		Write-Success 'Configuration applied.'

		if (Confirm-Action 'Restart IPBan to apply settings now?')
		{
			Restart-IPBan
		}
	}
	else
	{
		Write-Host '  Original configuration unchanged.'
	}
}

function Install-OrUpdate {
	$service = Get-IPBanService

	if ($null -ne $service)
	{
		Write-Notice 'IPBan is installed. This will UPDATE the upstream service.'
		Write-Host '  The IPBan service may temporarily stop during the update.'
	}

	if (-not (Confirm-Action 'Download the official DigitalRuby/IPBan installer for review?'))
	{
		return
	}

	foreach ($path in @($script:ConfigPath, $script:OverridePath))
	{
		Backup-Config $path
	}

	Ensure-LogsDirectory
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
	$url = 'https://raw.githubusercontent.com/DigitalRuby/IPBan/master/IPBanCore/Windows/Scripts/install_latest.ps1'
	$installer = Join-Path $script:LogsDir ('WinIPBan-OfficialInstaller_{0}.ps1' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
	Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing
	Start-Process -FilePath 'notepad.exe' -ArgumentList ('"{0}"' -f $installer) -Wait

	if (-not (Confirm-Action 'Have you reviewed the official installer? Execute this file as Administrator?'))
	{
		return
	}

	Unblock-File -LiteralPath $installer
	& $installer -startupType 'delayed-auto'
	Write-Success 'Installer finished. Review service status to confirm.'
}

function Service-Controls {
	$service = Get-IPBanService

	if ($null -eq $service)
	{
		Write-Host 'IPBan is not installed.' -ForegroundColor Yellow
		return
	}

	Write-Host ('Current status: {0}' -f $service.Status)
	Write-MenuItem 'S' 'Start service'
	Write-MenuItem 'R' 'Restart service'
	Write-MenuItem 'T' 'Stop service'
	Write-MenuItem 'Q' 'Back'
	$choice = (Read-Host '  Please choose an option').Trim().ToUpperInvariant()

	if ($choice -eq 'Q')
	{
		$script:SkipMenuPause = $true
		return
	}

	switch ($choice)
	{
		'S'
		{
			Start-Service -Name 'IPBan'
			Write-Host 'Start command sent.' -ForegroundColor Green
		}
		'R'
		{
			Restart-IPBan
		}
		'T'
		{
			if (Confirm-Action 'Stop IPBan? New attacks will not be automatically banned.')
			{
				Stop-Service -Name 'IPBan'
				Write-Host 'IPBan stopped.' -ForegroundColor Yellow
			}
		}
	}
}

if ($PSVersionTable.PSVersion.Major -lt 5)
{
	throw 'WinIPBan requires Windows PowerShell 5.1.'
}

if (-not (Ensure-Admin))
{
	return
}

$script:WindowsLabel = Get-WindowsVersionLabel
Ensure-LogsDirectory

while ($true)
{
	$script:SkipMenuPause = $false

	try
	{
		Clear-Host
		$service = Get-IPBanService
		$status = 'NOT INSTALLED'
		$statusColor = 'Yellow'

		if ($null -ne $service)
		{
			$status = [string]$service.Status

			if ($service.Status -eq 'Running')
			{
				$statusColor = 'Green'
			}
		}

		Write-Banner 'Unofficial console for DigitalRuby/IPBan'
		Write-Host '  IPBan service: ' -NoNewline
		Write-Host $status -ForegroundColor $statusColor
		Write-Host '  Upstream IPBan: https://github.com/DigitalRuby/IPBan' -ForegroundColor DarkGray
		Write-Host ('  Report location: {0}' -f $script:LogsDir) -ForegroundColor DarkGray
		Write-Host ''
		Write-Host '  SERVICE & CONFIGURATION' -ForegroundColor DarkCyan
		Write-MenuItem 'S' 'Status and current settings'
		Write-MenuItem 'C' 'Change ban settings'
		Write-MenuItem 'R' 'Start / restart / stop IPBan'
		Write-MenuItem 'U' 'Install or update IPBan'
		Write-MenuItem 'E' 'Edit IPBan configuration (Notepad copy)'
		Write-Host ''
		Write-Host '  SECURITY & ANALYTICS' -ForegroundColor DarkCyan
		Write-MenuItem 'B' 'Active blocked IPs (10 per page)'
		Write-MenuItem 'A' 'Failed logon statistics by IP / username'
		Write-MenuItem 'F' 'Recent failed logons (10 per page)'
		Write-MenuItem 'I' 'Inspect an IP address'
		Write-MenuItem 'M' 'Manually ban or unban an IP'
		Write-MenuItem 'H' 'Successful RDP logons (10 per page)'
		Write-MenuItem 'L' 'View IPBan logfile / Notepad export'
		Write-MenuItem 'D' 'Firewall discovery diagnostics'
		Write-Host ''
		Write-MenuItem 'Q' 'Quit'
		$selection = (Read-Host '  Please choose an option').Trim().ToUpperInvariant()

		switch ($selection)
		{
			'Q' { break }
			'S' { Show-Status }
			'C' { Edit-Settings }
			'R' { Service-Controls }
			'U' { Install-OrUpdate }
			'E' { Open-Config }
			'B' { Show-Bans }
			'A' { Show-AttackStatistics }
			'F' { Show-RecentAttempts }
			'I' { Inspect-IP }
			'M'
			{
				Write-Banner 'Manual IPBan actions'
				Write-MenuItem 'B' 'Ban IP'
				Write-MenuItem 'U' 'Unban IP'
				Write-MenuItem 'Q' 'Back'
				$action = (Read-Host '  Please choose an option').Trim().ToUpperInvariant()

				if ($action -eq 'Q')
				{
					$script:SkipMenuPause = $true
				}

				if ($action -eq 'B')
				{
					Queue-IPAction 'ban.txt'
				}
				elseif ($action -eq 'U')
				{
					Queue-IPAction 'unban.txt'
				}
			}
			'H' { Show-SuccessfulRDP }
			'L' { Open-Logs }
			'D' { Show-FirewallDiagnostics }
			default { Write-Notice 'Unknown menu option.' }
		}

		if ($selection -eq 'Q')
		{
			break
		}
	}
	catch
	{
		$script:SkipMenuPause = $false
		Write-Host ('  Error: {0}' -f $_.Exception.Message) -ForegroundColor Red
	}

	if (-not $script:SkipMenuPause)
	{
		Pause-Menu
	}
}
