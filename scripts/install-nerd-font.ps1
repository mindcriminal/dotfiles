<#
.SYNOPSIS
  Install Hack Nerd Font on the Windows side, from the copy Nix already built
  inside WSL.

.DESCRIPTION
  home.nix installs nerd-fonts.hack into the WSL user profile, which is enough
  for anything rendering inside Linux. It is NOT enough for WezTerm: WezTerm is
  a Windows program and reads Windows-installed fonts, so without this the
  terminal silently falls back and every glyph in the starship prompt is a box.

  This is the Windows counterpart of the video's Homebrew font cask. It installs
  per-user (no admin, no UAC): the files go to the per-user font directory and
  are registered under HKCU.

.EXAMPLE
  # From PowerShell on Windows, in this repo's Windows path:
  powershell -ExecutionPolicy Bypass -File .\scripts\install-nerd-font.ps1

.NOTES
  Re-running is safe; existing files are overwritten in place.
  Log out and back in (or restart WezTerm) if the font does not appear at once.
#>
[CmdletBinding()]
param(
    # WSL distribution to read the fonts from. Defaults to the registered name.
    [string]$Distro = "rocky10",

    # Install every variant (Mono and Propo too), not just the base family.
    [switch]$AllVariants
)

$ErrorActionPreference = "Stop"

Write-Host "==> Locating Hack Nerd Font inside WSL ($Distro)"

$fontDirLinux = (wsl.exe -d $Distro -- bash -lc `
    'readlink -f ~/.nix-profile/share/fonts/truetype/NerdFonts/Hack 2>/dev/null').Trim()

if ([string]::IsNullOrWhiteSpace($fontDirLinux)) {
    throw "Could not find the font in WSL. Run ./rebuild.sh inside WSL first."
}

$fontDir = (wsl.exe -d $Distro -- wslpath -w $fontDirLinux).Trim()
if (-not (Test-Path $fontDir)) {
    throw "WSL reported $fontDir but Windows cannot read it."
}
Write-Host "    $fontDir"

$pattern = if ($AllVariants) { "Hack*.ttf" } else { "HackNerdFont-*.ttf" }
$fonts = Get-ChildItem -Path $fontDir -Filter $pattern
if ($fonts.Count -eq 0) { throw "No files matching $pattern in $fontDir" }

$targetDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
$regKey    = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
New-Item -Path $regKey -Force | Out-Null

# Each registry value name must be UNIQUE PER FACE, not per family. Every face
# in this family reports the same family name ("Hack Nerd Font"), so naming the
# values after it makes each write overwrite the last: you end up with a single
# entry pointing at whichever file happened to be written last, and Windows
# knows the family only by that one style. WezTerm then reports it cannot find
# a Regular face. Windows' own convention is family name alone for Regular,
# family + style for everything else.
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
function Get-FontFamilyName([string]$path, [string]$fallback) {
    try {
        $collection = New-Object System.Drawing.Text.PrivateFontCollection
        $collection.AddFontFile($path)
        return $collection.Families[0].Name
    } catch {
        return $fallback
    }
}

# "HackNerdFont-BoldItalic" -> "Bold Italic"
function Get-FontStyleName([string]$baseName) {
    $style = ($baseName -split '-')[-1]
    if ($style -eq $baseName) { return "Regular" }
    return [regex]::Replace($style, '(?<!^)(?=[A-Z])', ' ')
}

Write-Host "==> Installing $($fonts.Count) font file(s) for the current user"

$claimed = @{}
foreach ($font in $fonts) {
    $dest = Join-Path $targetDir $font.Name
    Copy-Item -Path $font.FullName -Destination $dest -Force

    $family = Get-FontFamilyName -path $dest -fallback $font.BaseName
    $style  = Get-FontStyleName  -baseName $font.BaseName
    $name   = if ($style -eq "Regular") { "$family (TrueType)" } else { "$family $style (TrueType)" }

    # Never let two faces silently claim one name again - that was the bug.
    if ($claimed.ContainsKey($name)) {
        throw "Two font files both claim the registry name '$name': $($claimed[$name]) and $($font.Name). Refusing to overwrite."
    }
    $claimed[$name] = $font.Name

    Set-ItemProperty -Path $regKey -Name $name -Value $dest
    Write-Host ("    {0,-40} {1}" -f $name, $font.Name)
}

# Register the faces with GDI and tell running apps, so the fonts work now
# instead of after the next sign-out.
Add-Type -Namespace Win32Font -Name Native -MemberDefinition @'
[DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
public static extern int AddFontResourceW(string lpFilename);
[DllImport("user32.dll", CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, IntPtr wParam,
    IntPtr lParam, uint fuFlags, uint uTimeout, out IntPtr lpdwResult);
'@ -ErrorAction SilentlyContinue

try {
    foreach ($font in $fonts) {
        [Win32Font.Native]::AddFontResourceW((Join-Path $targetDir $font.Name)) | Out-Null
    }
    $HWND_BROADCAST = [IntPtr]0xffff
    $WM_FONTCHANGE  = 0x001D
    $result = [IntPtr]::Zero
    [Win32Font.Native]::SendMessageTimeout($HWND_BROADCAST, $WM_FONTCHANGE,
        [IntPtr]::Zero, [IntPtr]::Zero, 0, 1000, [ref]$result) | Out-Null
    Write-Host "    registered with GDI and notified running applications"
} catch {
    Write-Host "    (could not notify running apps; sign out and back in if fonts do not appear)"
}

Write-Host ""
Write-Host "==> Done. Restart WezTerm to pick up the font."
Write-Host "    If glyphs still render as boxes, sign out and back in."
