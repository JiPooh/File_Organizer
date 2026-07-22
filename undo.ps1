# Three main directories
$UnsortedDir  = "C:\Users\cream\Downloads\asdf\Unsorted" 	# Where the unsorted files are located
$SortedDir    = "C:\Users\cream\Downloads\asdf\Sorted"		# Where the sorted files/folders are located
$ShortcutsDir = "C:\Users\cream\Downloads\asdf\Shortcuts"	# Where the shortcut files are located

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "Starting Undo process..." -ForegroundColor Yellow

# 1. Move all files inside Sorted subfolders back to Unsorted
if (Test-Path -LiteralPath $SortedDir) {
    $Subfolders = @(Get-ChildItem -LiteralPath $SortedDir -Directory)

    foreach ($folder in $Subfolders) {
        $Files = @(Get-ChildItem -LiteralPath $folder.FullName -File)
        foreach ($file in $Files) {
            Move-Item -LiteralPath $file.FullName -Destination $UnsortedDir -Force
        }
        # Delete empty folder
        Remove-Item -LiteralPath $folder.FullName -Force -Recurse
    }
}

# 2. Clean up shortcut files
if (Test-Path -LiteralPath $ShortcutsDir) {
    Get-ChildItem -LiteralPath $ShortcutsDir -Filter "*.lnk" | Remove-Item -Force
}

Write-Host "Undo complete! All files returned to Unsorted, folders and shortcuts cleaned up." -ForegroundColor Green
Read-Host -Prompt "Press Enter to exit..."