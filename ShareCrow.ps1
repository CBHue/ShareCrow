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

  .PARAMETER maxWorkers

    Maximum threads to run

  .PARAMETER testFile

    Name of the test file to create during write check. Default: sclog_<date>.txt

  .EXAMPLE

    C:\PS>  .\ShareCrow.ps1 -accessCheck -inputFile .\targets\smbHosts.txt -outputDir 'C:\Users\Me\Temp\'

    Description
    -----------
    This command will perform a net view on the target host, then run test-path on each item to find readable paths. For each readable path it will list the contents. 

  .EXAMPLE
    C:\PS>  .\ShareCrow.ps1 -writeCheck -inputFile .\targets\accessibleShares.txt -outputDir 'C:\Users\Me\Temp\' 
    
    Description
    -----------
    This command will perform a write test on all directorys in the supplied share.
    If successfull it notify and then delete the created test file.
     
#>
Param
  (
    # Check if you can write
    [switch]$writeCheck  = $false,
    
    # filename to test write
    [string]$testFile = "sclog_$(get-date -f MM-dd-yy_HHmmss).txt",

    # Check if you can access 
    [switch]$accessCheck = $false,
    
    [Parameter(Mandatory = $true)]
    [string]$inputFile,
    
    [Parameter(Mandatory = $true)]
    [string]$outputDir,

    # Worker Dem
    [parameter(Mandatory=$false)]
    [ValidateRange(3,10000)]
    [System.Int32]
    # Max number of threads for RunspacePool.
    $maxWorkers = 10
    
  )

$banner = @"

ShareCrow v2.0 - CBHue
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

# Store the results
$CBH = [hashtable]::Synchronized([ordered]@{})

# check what were supposed to do. 
if ((!$writeCheck -and !$accessCheck) -or ($writeCheck -and $accessCheck)){ 
    write-Host "[!] You must choose -accessCheck OR -writeCheck" -ForegroundColor Red -BackgroundColor Black
    write-Host "`t.\ShareCrow.ps1 -accessCheck -inputFile .\targets\smb3.txt -outputDir .\shareCrow"
    write-Host "`t.\ShareCrow.ps1 -writeCheck -inputFile .\targets\accessibleShares.txt -outputDir .\shareCrow"
    exit 
}

$module = "unknown"
if ($accessCheck) {
    $CBH.add("accessCheck","accessCheck")
    $module = $CBH["accessCheck"]
    }
else              {
    $CBH.add("writeCheck",$testFile)
    $module = "writeCheck"
    }

write-Host $banner
write-Host ("[!] Welcome to ShareCrow").PadRight(40," ") " : " -NoNewline 
write-Host $module -ForegroundColor Green
write-Host ("[!] Pooled Workers").PadRight(40," ") " : " -NoNewline 
write-Host $maxWorkers -ForegroundColor Green

# Output file
$outBasics = $outputDir + "\ShareCrow_" + $module + "_$(get-date -f MM-dd-yyyy_HH_mm_ss)" + ".csv"
$outDetail = $outputDir + "\ShareCrow_" + $module + "_$(get-date -f MM-dd-yyyy_HH_mm_ss)" + "_Details.txt"

# Define the workers job
$Worker = {
    Param($target, $CBH)
    #Start-Sleep -Seconds 5 # Doing some work....

    Try {
        # Lets check our access ... 
        if ($CBH.ContainsKey("accessCheck")) {
            
            $shares = net view \\$target /all | select -Skip 7 | ?{$_ -match 'disk*'} | %{$_ -match '^(.+?)\s+Disk*'|out-null;$matches[1]}
            $shares | % { 
                $FP = "\\" + $target + "\" + $_
                Write-Host ("[*] Processing").PadRight(40," ") " : " -NoNewline
                Write-Host -ForegroundColor Green  $FP
                if (Test-Path $FP) {
                    $folders = Get-ChildItem $FP -Force -Verbose | Sort-Object LastWriteTime
                    $CBH.add($FP,$folders)
                }
            } # End Share Loop
        }
        # Only other option is writeCheck ...
        else {
            Write-Host ("[*] Processing").PadRight(40," ") " : " -NoNewline
            Write-Host -ForegroundColor Green  $target      
            $dirs = Get-ChildItem $target -Directory -Recurse
            foreach ($d in $dirs) {
                $file = $d.FullName + "\" + $CBH["writeCheck"]
                try   { 
                    Out-File -FilePath $file 
                }
                catch {   
                
                }
                if(Test-Path -ErrorAction SilentlyContinue $file){
                    $CBH.add($file,1)
                
                    # Ok it worked .... now delete the file
                    #Write-Host "[*] Deleting created file : $file"
                    try   { 
                        Remove-Item $file 
                        $CBH[$file] = "$file"
                    }
                    catch {
                        $CBH[$file] = "Error Deleting $file" 
                    }
                }
            }
        } 
    }
    Catch {
        $CBH.add($target, $_.Exception.Message)
    }
}

# Create the pool
$SessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$RunspacePool = [RunspaceFactory]::CreateRunspacePool(1, $maxWorkers, $SessionState, $Host)
$RunspacePool.Open()
$Jobs = New-Object System.Collections.ArrayList

# Read list of Hosts to check for open shares
$targets = Get-Content $inputFile

# Task workers to do all the things
foreach ($target in $targets) {
    Write-Host ("[*] Creating runspace for").PadRight(40," ") " : " -NoNewline
    Write-Host -ForegroundColor Green $target
    $PowerShell = [powershell]::Create()
	$PowerShell.RunspacePool = $RunspacePool
    $PowerShell.AddScript($Worker).AddArgument($target).AddArgument($CBH) | Out-Null
    
    $JobObj = New-Object -TypeName PSObject -Property @{
		Runspace = $PowerShell.BeginInvoke()
		PowerShell = $PowerShell  
    }

    $Jobs.Add($JobObj) | Out-Null
}

# Check on the status
while ($Jobs.Runspace.IsCompleted -contains $false) {
    #Write-Host (Get-date).Tostring() "Still running..."
    Write-Verbose -Message "Jobs in progress $($Jobs.Count)"
	Start-Sleep 1
}

# Print the results
# Write module to outfile
$banner | Out-File $outDetail
"Module: " + $CBH[0] | Out-File $outDetail -Append
" "  | Out-File $outDetail -Append

# write the basics
$CBH.GetEnumerator()  | Select Key | Export-CSV -path $outBasics -NoTypeInformation

# write the details
$CBH.GetEnumerator() | ForEach-Object {
     $_.value | Out-File $outDetail -Append
}

Write-Host ("[*] All basic results written to ").PadRight(40," ") " : " -NoNewline
Write-Host "$outBasics" -ForegroundColor green
Write-Host ("[*] All detailed results written to ").PadRight(40," ") " : "  -NoNewline
Write-Host "$outDetail" -ForegroundColor green
