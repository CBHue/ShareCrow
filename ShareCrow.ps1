<#
  .SYNOPSIS

    ShareCrow.ps1
    
    Author: CB Hue - HueBSolutions LLC
    https://github.com/CBHue/

    Required Dependencies: None
    Optional Dependencies: None  


  .DESCRIPTION

    Checks provided hosts for readable shares.
    Checks shares for writeable directories. 
        - This is only useful in certain circumstances. 
        - Note if you supply it with a share with exponetially large depth it will most likely die. 

  .PARAMETER inputFile

    If you are doing an access check, a list of IPs or Hosts names, one per line, with port 445 open
        + Example file Contents:
        ------------------------
        10.10.10.10
        ServerA.local
        10.10.10.20

    If you are doing a write check, a list of shares you want to check, one per line. 
        + Example file Contents:
        ------------------------
        \\10.10.10.10\C$
        \\10.10.10.20\Tomcat

  .PARAMETER outputDir

    The directory to output the results. 

  .PARAMETER Threads

    (Placeholder for multi-threading to be added in later)

  .EXAMPLE

    C:\PS>  .\ShareCrow.ps1 -accessCheck -inputFile .\targets\smbHosts.txt -outputDir .\SC 

    Description
    -----------
    This command will perform a net view on the target host, then run test-path on each item to find readable paths. For each readable path it will list the contents. 

  .EXAMPLE
    C:\PS>  .\ShareCrow.ps1 -writeCheck -inputFile .\targets\accessibleShares.txt -outputDir .\SC 
    
    Description
    -----------
    This command will perform a write test on all directorys in the supplied share.
    If successfull it notify and then delete the created test file.
     
#>
Param
  (
    # Check if you can write
    [switch]$writeCheck  = $false,

    # Check if you can access 
    [switch]$accessCheck = $false,
    
    [Parameter(Mandatory = $true)]
    [string]$inputFile,
    
    [Parameter(Mandatory = $true)]
    [string]$outputDir
    
  )

$CBH = @"
ShareCrow v1.0 - CBHue
                              __
                              | \      _
                           ==='=='==  (o>
                              \++/   / )
                     __.-------------^^-.__
                        \----.  : .----/
                              \_/\|          ()
                              / _ \       _  \/()
                             / /|\ \     |/| | \/
                           _/_/ | \_\_     | |//
                          /_/   |   \_\    \_\|
                                             CBH

"@

Function getShares {
    Param($smb)
    $SMBArray = New-Object System.Collections.ArrayList

    # Turn off errors for this bc i dont care
    $ErrorActionPreference = "SilentlyContinue"; 
 
    net view \\$smb /all | %{
        if($_.IndexOf(' Disk ') -gt 0) {
            $shareName = $_.Split('      ')[0]
            $FP = Join-Path $smb $shareName;
            $FP = "\\" + $FP

            if (Test-Path $FP -ErrorAction SilentlyContinue) {
                $null = $SMBArray.Add($FP)
                $null = $AllShares.Add($FP)
            }
        }
    }

    # might care about other errors lol
    $ErrorActionPreference = "Continue";


    return $SMBArray 
}

Function listContents { 
    Param($share)
    $Folders = Get-ChildItem $share -Force | Sort-Object LastWriteTime
    $null = $AllDetail.Add($Folders)
    return $Folders
}

Function test-create {
    Param($DIR)
    $file = $DIR + "\_c8h.txt"
    try   { Out-File -FilePath $file }
    catch {   }
    
    # check if file exists
    if(Test-Path -ErrorAction SilentlyContinue $file){
        Write-Host -NoNewline "[!] Writable Directory    : " 
        Write-Host $file -ForegroundColor Green
        $global:counter++
        $null = $AllShares.Add($DIR)

        # delete the file
        Write-Host "[*] Deleting created file : $file"
        try 
        {
            Remove-Item $file
        }
        catch 
        {
            Write-Host -NoNewline "[!] Error deleteing file  : "
            Write-Host $file -BackgroundColor Black -ForegroundColor red
        }
    }
}

#######################
#                     #
# Do the work here!!! #
#                     #
#######################

# check what were supposed to do. 
if ((!$writeCheck -and !$accessCheck) -or ($writeCheck -and $accessCheck)){ 
    write-Host "[!] You must choose -accessCheck OR -writeCheck" -ForegroundColor Red -BackgroundColor Black
    write-Host "`t.\ShareCrow.ps1 -accessCheck -inputFile .\targets\smb3.txt -outputDir .\SC"
    write-Host "`t.\ShareCrow.ps1 -writeCheck -inputFile .\targets\accessibleShares.txt -outputDir .\SC"
    exit 
}

$module = "unknown"
if ($accessCheck) {$module = "_accessCheck_"}
else              {$module = "_writeCheck_"}

write-Host $CBH
write-Host "Welcome to ShareCrow      : " -NoNewline 
write-Host $module.Trim("_","*") -ForegroundColor Green

# Globals and thangs
$global:AllShares = New-Object System.Collections.ArrayList
$global:AllDetail = New-Object System.Collections.ArrayList
$global:counter = 0

# Output file
$outBasics = $outputDir + "\ShareCrow" + $module + "$(get-date -f MM-dd-yyyy_HH_mm_ss)" + ".txt"
$outDetail = $outputDir + "\ShareCrow" + $module + "$(get-date -f MM-dd-yyyy_HH_mm_ss)" + "_Details.txt"

# Input File
$targets = get-content $inputFile

# This is kinda hacky ... getting percentage of each loop: 1/Total * 100 = Each Loops %
$Count = $Total = $tPerc = 0
$Total = $targets.Count
$oPerc = (1 / $Total) * 100

# If you are doing an access check 
if ($accessCheck) {
    
    # Write module to outfile
    $CBH | Out-File $outDetail
    "Module: " + $module.Trim('_','*') | Out-File $outDetail -Append
    " "  | Out-File $outDetail -Append

    write-Host "We have work to do        : " -NoNewline
    write-Host $Total -NoNewline -ForegroundColor green
    Write-Host " Hosts" -ForegroundColor green
     
    foreach ($smb in $targets) {
        # Give a status and a percentage complete
        $Total = $Total - 1
        $tPerc = $tPerc + $oPerc
        $dperc = [Math]::Round($tPerc)
        Write-Progress -Activity "Testing Ports: $hst ... Hosts Left: $Total ..." -Status "Percentage complete: $dperc % " -PercentComplete $dperc   

        Write-Host ""
        Write-Host -NoNewline "[*] Checking access to    : "
        Write-Host $smb -ForegroundColor Yellow
        $SMBA = New-Object System.Collections.ArrayList
        $SMBA = getShares $smb

        if ($SMBA.Count -lt 1){
            Write-Host -NoNewline "[!] No shares accessible  : "
            Write-Host $smb -BackgroundColor black -ForegroundColor red
        }

        foreach ($share in $SMBA) {
            if (!$share){ continue }
            Write-Host -NoNewline "[*] Listing contents      : "
            Write-Host $share -ForegroundColor green
            listContents $share
        }
    }

    $global:AllShares | Out-File $outBasics
    Write-Host -NoNewline "`n[*] All accessible shares written to        : "
    Write-Host "$outBasics" -ForegroundColor green

    $global:AllDetail | Out-File $outDetail -Append
    Write-Host -NoNewline "[*] All accessible share details written to : "  
    Write-Host "$outDetail" -ForegroundColor green
}

if ($writeCheck) {

    # Write module to outfile
    $CBH | Out-File $outBasics
    "Module: " + $module.Trim('_','*') | Out-File $outBasics -Append
    " "  | Out-File $outBasics -Append

    write-Host "We have work to do        : " -NoNewline
    write-Host $Total -NoNewline -ForegroundColor green
    Write-Host " Shares" -ForegroundColor green

    # loop thru each provided share
    foreach ($share in $targets) {
        
        # Give a status and a percentage complete
        $Total = $Total - 1
        $tPerc = $tPerc + $oPerc
        $dperc = [Math]::Round($tPerc)
        Write-Progress -Activity "Getting Shares: $hst ... Hosts Left: $Total ..." -Status "Percentage complete: $dperc % " -PercentComplete $dperc  
        
        # get all directories in the share ... this may take a while depending on how deep it is
        Write-Host -NoNewline "`n[*] Attempting to write   : " 
        Write-Host $share"\*" -ForegroundColor Yellow
        $dirs = Get-ChildItem $share -Directory -Recurse

        $global:counter = 0
        # try to create a file in each directory
        foreach ($d in $dirs) {
            test-create $d.FullName
        }
        Write-Host -NoNewline "[*] Writeable Directories : "
        Write-Host $global:counter -ForegroundColor Yellow
        $global:counter = 0
    }
    
    if ($global:AllShares.Count -lt 1){
        Write-Host "`n[*] No writable shares    : " -ForegroundColor Red
    }
    else {
        $global:AllShares | Out-File -Append $outBasics
        Write-Host -NoNewline "`n[*] All writeable shares saved to : "
        Write-Host "$outBasics" -ForegroundColor green
    }
}
