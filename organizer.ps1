<#
.SYNOPSIS
A short powershell script to organize files and its
subfiles into subfolders and create a Unicode-safe shortcut to the master file
to make things look more organized with less icons

.DESCRIPTION
This script scans an unsorted directory for master files (like .mp4 or .mkv) 
and their associated sub-files (like .srt or .jpg). 
It creates a dedicated folder for each master file, moves all related files into it, 
and uses a native C# wrapper to generate .lnk shortcuts that safely support non-English characters

.AUTHOR
Jihoo
#>

# Three main directories
$UnsortedDir  = "C:\Path\To\Unsorted"		# Where the unsorted files are located
$SortedDir    = "C:\Path\To\Sorted"			# Where the files are sorted by folder
$ShortcutsDir = "C:\Path\To\Shortcuts"		# Where the shortcut are created

# Master file extension types
$MasterExtensions = @(".fileExtentionType")	# Example: ".mp4", ".av1", ".mkv", ".mov"

# Allows more then English to be used in folder/shortcut names
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Ensure destination folders exist
# If not, create approporiate folder
if (!(Test-Path -LiteralPath $SortedDir)) { New-Item -ItemType Directory -Force -Path $SortedDir | Out-Null }
if (!(Test-Path -LiteralPath $ShortcutsDir)) { New-Item -ItemType Directory -Force -Path $ShortcutsDir | Out-Null }

# =========================================================================
# UNICODE SHORTCUT CREATOR (IShellLinkW Native Interop)
# Defines a low-level C# wrapper that interfaces directly with Windows COM
# Overcomes legacy WScript.Shell limitations when handling Chinese/Japanese/Korean characters
# Ensures shortcut paths with non-English characters save without corruption or range errors
# =========================================================================
if (-not ([System.Management.Automation.PSTypeName]'NativeShortcut').Type) {
    $Source = @"
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

public class NativeShortcut {
    [ComImport]
    [Guid("00021401-0000-0000-C000-000000000046")]
    internal class Shortcut { }

    [ComImport]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    [Guid("000214F9-0000-0000-C000-000000000046")]
    internal interface IShellLinkW {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszFile, int cchMaxPath, out IntPtr pfd, int fFlags);
        void GetIDList(out IntPtr ppidl);
        void SetIDList(IntPtr pidl);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszName, int cchMaxName);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string pszName);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszDir, int cchMaxDir);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string pszDir);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszArgs, int cchMaxPath);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string pszArgs);
        void GetHotkey(out short pwHotkey);
        void SetHotkey(short wHotkey);
        void GetShowCmd(out int piShowCmd);
        void SetShowCmd(int iShowCmd);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszIconPath, int cchIconPath, out int piIcon);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string pszIconPath, int iIcon);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string pszPathRel, int dwReserved);
        void Resolve(IntPtr hwnd, int fFlags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string pszFile);
    }

    public static void Create(string shortcutPath, string targetPath) {
        IShellLinkW link = (IShellLinkW) new Shortcut();
        link.SetPath(targetPath);
        IPersistFile file = (IPersistFile) link;
        file.Save(shortcutPath, true);
    }
}
"@
    Add-Type -TypeDefinition $Source
}

# =========================================================================
# SHORTCUT GENERATOR FUNCTION
# Accepts the target master file path and desired base name
# Constructs the target shortcut path in the Shortcuts folder
# Triggers the C# NativeShortcut engine to write the .lnk file
# Displays a warning if shortcut generation fails instead of stopping the script
# =========================================================================
function Create-MasterShortcut ($MasterFilePath, $BaseName) {
    $ShortcutPath = Join-Path -Path $ShortcutsDir -ChildPath "$BaseName.lnk"
    try {
        [NativeShortcut]::Create($ShortcutPath, $MasterFilePath)
    } catch {
        Write-Warning "Failed to save shortcut for '$BaseName': $_"
    }
}

# =========================================================================
# FILE SAFE MOVE FUNCTION
# Checks list of names that exsists in sorted file
# Checks for duplicate names
# If duplicate name exsists rename new files by adding number just like windows file explorer
# Sort/move files to sorted folder
# =========================================================================
function Move-FileSafely ($sourcePath, $targetDirectory) {
    $fileName = [System.IO.Path]::GetFileName($sourcePath)
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($sourcePath)
    $ext      = [System.IO.Path]::GetExtension($sourcePath)

    $targetPath = Join-Path -Path $targetDirectory -ChildPath $fileName
    $counter = 1

    while (Test-Path -LiteralPath $targetPath) {
        $newName = "$baseName ($counter)$ext"
        $targetPath = Join-Path -Path $targetDirectory -ChildPath $newName
        $counter++
    }

    Move-Item -LiteralPath $sourcePath -Destination $targetPath -Force
}

# =========================================================================
# SMART SUB-FILE MATCHING FUNCTION
# Compares an unsorted file against a target master file name
# Normalizes Unicode encoding (NFC/NFD) to prevent matching failures on foreign titles
# Checks for exact base name matches (e.g., "Project1.jpg")
# Checks for multi-extension or delimited sub-files (e.g., "Project1.kr.srt", "Project1_thumb.png")
# =========================================================================
function Test-FileMatchesMaster ($file, $baseName) {
    $fBase = $file.BaseName.Normalize()
    $mBase = $baseName.Normalize()

    # 1. Exact base name match (e.g., "Movie" == "Movie" or "A" == "A")
    if ($fBase -eq $mBase) { return $true }

    # 2. Multi-extension match (e.g., "Movie.zh.srt" or "A.1.jpg")
    if ($fBase.StartsWith($mBase + ".")) { return $true }

    # 3. Delimited sub-files allowed ONLY for master names longer than 2 characters
    if ($mBase.Length -gt 2) {
        if ($fBase.StartsWith($mBase + "_") -or 
            $fBase.StartsWith($mBase + "-") -or 
            $fBase.StartsWith($mBase + " ")) {
            return $true
        }
    }

    return $false
}

# =========================================================================
# PHASE 1: SWEEP EXISTING SORTED FOLDERS
# Checks the sorted folder and get all names of master files
# Checks the unsorted folder for any possible orphaned sub files
# Move the orphaned files to the approporiate folder with master file
# Update shortcut
# =========================================================================
Write-Host "Phase 1: Checking existing Sorted folders for left-out sub-files..." -ForegroundColor Cyan

$ExistingFolders = @(Get-ChildItem -LiteralPath $SortedDir -Directory)

foreach ($folder in $ExistingFolders) {
    $BaseName = $folder.Name

    # Check Unsorted for left-out sub-files and move them safely
    $OrphanFiles = @(Get-ChildItem -LiteralPath $UnsortedDir) | Where-Object { Test-FileMatchesMaster $_ $BaseName }
    foreach ($file in $OrphanFiles) {
        Move-FileSafely -sourcePath $file.FullName -targetDirectory $folder.FullName
        Write-Host "  Swept orphaned file '$($file.Name)' into '$BaseName'" -ForegroundColor Gray
    }

    # Ensure shortcut exists and points to master file inside the folder
    $MasterInFolder = @(Get-ChildItem -LiteralPath $folder.FullName) | Where-Object { $_.Extension -in $MasterExtensions } | Select-Object -First 1
    if ($MasterInFolder) {
        Create-MasterShortcut -MasterFilePath $MasterInFolder.FullName -BaseName $BaseName
    }
}

# =========================================================================
# PHASE 2: PROCESS NEW MASTER FILES IN UNSORTED
# Check unsorted folder and get all names of master files
# Create master folder in the sorted folder
# Move master file and all its related sub files in its approporiate sorted folder
# Create shortcut to the master file
# =========================================================================
Write-Host "Phase 2: Processing new master files..." -ForegroundColor Cyan

$MasterFiles = @(Get-ChildItem -LiteralPath $UnsortedDir) | Where-Object { $_.Extension -in $MasterExtensions }

foreach ($master in $MasterFiles) {
    if (!(Test-Path -LiteralPath $master.FullName)) { continue }

    $BaseName = $master.BaseName
    $TargetFolder = Join-Path -Path $SortedDir -ChildPath $BaseName

    if (!(Test-Path -LiteralPath $TargetFolder)) {
        New-Item -ItemType Directory -Force -Path $TargetFolder | Out-Null 
    }

    # Move all matching files safely
    $MatchingFiles = @(Get-ChildItem -LiteralPath $UnsortedDir) | Where-Object { Test-FileMatchesMaster $_ $BaseName }
    foreach ($file in $MatchingFiles) {
        Move-FileSafely -sourcePath $file.FullName -targetDirectory $TargetFolder
    }

    # Create shortcut
    $NewMasterPath = Join-Path -Path $TargetFolder -ChildPath $master.Name
    Create-MasterShortcut -MasterFilePath $NewMasterPath -BaseName $BaseName
}

Write-Host "Organization and sweep complete." -ForegroundColor Green
Read-Host -Prompt "Press Enter to exit..."