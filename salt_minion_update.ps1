[string]$latest_minion_url = "https://repo.saltproject.io/windows/Salt-Minion-Latest-Py3-AMD64-Setup.exe"
[string]$downloaded_minion = "C:\windows\temp\Salt-Minion-Latest-Py3-AMD64-Setup.exe"
[string]$salt_master = "MASTER_SALT" # MUST BE REPLACED WITH YOUR MASTER
[string]$salt_dir ="C:\salt"

[string]$scripts_folder = "C:\scripts"
[string]$log_folder = "salt_log"
[bool]$result = $false

# --- log procedures --------------------------------------------------------------------

function Prepare-LogFolder
    {
        $e = Test-Path -Path ($scripts_folder + "\" + $log_folder) 
        if($e -eq $false)
            {
                $n = New-Item -Path $scripts_folder -ItemType Directory -Name $log_folder
                $r = 1 # New Directory has been created
            }
        else
            {
                $c = ChildItem -Path ($scripts_folder + "\" + $log_folder + "\") -File | Where-Object { $_.LastWriteTime -lt $log_remove_day } | Remove-Item
                $r = 2 # There was an existing directory, old files have been removed
            }
        return $r
    }

function Write-MyLog
    {
        param ([Parameter(Mandatory = $true)][string]$MyLogstring)
        $cdate = Get-Date
        $ctime = [string]$cdate.TimeOfDay
        $d = [string]$cdate.Day
        $m = [string]$cdate.Month
        $y = [string]$cdate.Year
        $fn = ($d + "_" + $m + "_" + $y + ".txt")
        Add-Content -Path ($scripts_folder + "\" + $log_folder + "\" + $fn) -Value ($ctime + " --- " + $MyLogstring)
    }

# --- task-specific procedures ---------------------------------------------------------

function Uninstall-Salt
    {
        param([Parameter(Mandatory = $true)][string]$MinionPath)
        [bool]$ok = $false
        Write-MyLog -MyLogstring ("Uninstalling at " + $MinionPath + " ...")
        & $MinionPath '/S' '/delete-root-dir'
        [bool]$not_deleted = $true
        while($not_deleted -eq $true)
            {
                Start-Sleep 5
                Write-MyLog -MyLogstring "check old version is exist"
                $t = Test-Path -Path $MinionPath
                if($t -eq $false)
                   { $not_deleted = $false }
            }
    }

function Install-Salt
    {
        $result_code = 0
        try { Invoke-WebRequest -Uri $latest_minion_url -OutFile $downloaded_minion }
        catch { $result_code = 404  } # cannot download latest minion
        $option_master = "/master=" + $salt_master
        $option_dir = "/install-dir=" + $salt_dir
        if($result_code -eq 0)
            {
                 Write-MyLog -MyLogstring "trying to install"
                 [string]$machine_name = ("/minion-name=windows-" + [System.Net.Dns]::GetHostName())
                 & $downloaded_minion '/S' $option_master $machine_name $option_dir
        
                 [bool]$minion_run = $false
                 while($minion_run -eq $false)
                    {
                        Start-Sleep 5
                        Write-MyLog -MyLogstring "checking service ..."
                        $l_services = @(Get-Service | Where-Object { ($_.Name -like '*salt*') -and ($_.Name -like '*minion*') })
                        if($l_services.Count -gt 0)
                            {
                                Write-MyLog -MyLogstring "service found"
                                if((Get-Service -Name salt-minion).Status -like 'Running')
                                    {
                                        Write-MyLog -MyLogstring "service is running, trying to delete installation package"
                                        $minion_run = $true
                                        try { Remove-Item -Path $downloaded_minion -force }
                                        catch { Write-MyLog -MyLogstring "cannot delete installation file" }
                                    }
                            }
                
                    }
            }
        if($result_code -eq 404) { Write-MyLog -MyLogstring "download FAILED" }
    }

function Check-InstallAllow
    {
        [bool]$a = $false
        [string]$chkpth = "\\dc1.ad.almara.org\deploy\salt\automated\install.txt"
        Write-MyLog -MyLogstring "checking allow-file ... "
        $f = Test-Path -Path $chkpth
        if($f -eq $true)
            {
                $i = @(Get-Content -Path $chkpth)
                Write-MyLog -MyLogstring ([string]($i.Count))
                foreach($n in $i)
                    {
                        Write-MyLog -MyLogstring ("found string: " + $n)
                        if($n -like '#*')
                            {
                                Write-MyLog -MyLogstring "String with sharp"
                            }
                        else
                            {
                                if($n -like 'install*allow*')
                                    {
                                        [bool]$a = $true
                                        Write-MyLog -MyLogstring "ALLOW this script. Continue"
                                    }
                                #if($n -like 'install*deny*')
                                 #   {
                                #[bool]$a = $false
                                #Write-MyLog -MyLogstring "DENY this script. Stopping"
                                        #}
                            }
                    }
            }
        return $a
    }

# ---------------------------------------------------------------------------------------


Prepare-LogFolder

Write-MyLog -MyLogstring "*** START ***"

$checkallow = Check-InstallAllow
if($checkallow -eq $false)
    {
        Write-MyLog -MyLogstring "*** STOP ***"
        break
    }

[int32]$cur_ver = -1
try { $s = (Get-Service | Where-Object { $_.Name -like '*salt-minion*' }).Status }
catch { $s = "" }
if($s -ne "")
    {
        $p = ([string]((Get-CimInstance -ClassName win32_service | Where {$_.Name -like '*salt?minion*'}).PathName)).Trim('"')
        $f = @($p.Split("\"))
        $num = ($f.Count - 2)
        [bool]$uninst_found = $false
        while($num -gt 0)
            {
                [int]$n = 0
                [string]$rootstr = ""
                    while($n -le $num)
                        {
                            if($n -ne 0) { $rootstr += "\" }
                            $rootstr += $f[$n]
                            $n += 1
                        }
                $num -= 1
                $uninst_fullpath = ($rootstr + "\uninst.exe")
                $uninst_exe = [bool](Test-Path -Path $uninst_fullpath)
                if($uninst_exe -eq $true)
                    {
                        $uninst_found = $true  
                        $num = 0
                    }
           }
        # find out installed version of minion
        $salt_exe = [string]($rootstr + "\salt-minion")       
        [string]$minion_output = (& $salt_exe '-V' '|' 'findstr' '"Salt:"')
        [string]$h = ($minion_output.Split(':'))[1].Split('.')[0]
        [string]$l = ($minion_output.Split(':'))[1].Split('.')[1]
        $verstr = ($h + $l).Trim()
        $cur_ver = [int32]$verstr
     }


# ---------------------------------------------------------------------------------------

[int32]$act_ver = -1
[string]$checkver = "https://repo.saltproject.io/windows/Salt-Minion-Latest-Py3-AMD64-Setup.exe.sha256"
[string]$ctrlfile = "c:\windows\temp\Salt-Minion-Latest-Py3-AMD64-Setup.exe.sha256"

try { Invoke-WebRequest -Uri $checkver -OutFile $ctrlfile }
catch { Write-MyLog -MyLogstring "CANNOT DOWNLOAD" }
if((Test-Path -Path $ctrlfile) -eq $true)
    {
        Write-MyLog -MyLogstring "control file has been downloaded"
        $c = @([string](Get-Content -Path $ctrlfile -Raw)).Split(' ')
        $fl = $c.Count
        $m = @($c[$fl-1].Split('-'))
        foreach($fb in $m)
            {
                if($fb -like '[0-9][0-9][0-9][0-9].[0-9]')
                    {
                        $m_str = $fb
                        [string]$h = ($m_str.Split('.')[0])
                        [string]$l = ($m_str.Split('.')[1])
                        $verstr = ($h + $l).Trim()
                        $act_ver = [int32]$verstr
                        #Write-MyLog -MyLogstring ("actual version at web site is " + $verstr)               
                    }
            }
    }
else { Write-MyLog -MyLogstring "FILE NOT FOUND" }
try { Remove-Item -Path $ctrlfile }
catch { }


Write-MyLog -MyLogstring ("installed root is - " + $rootstr)
Write-MyLog -MyLogstring ("uninstaller found at - " + $uninst_fullpath)
Write-MyLog -MyLogstring ("installed minion - " + $cur_ver)
Write-MyLog -MyLogstring ("actual minion - " + $act_ver)

if($cur_ver -eq -1)
    {
        Write-MyLog -MyLogstring "minion not installed"
        Install-Salt
    }
else
    {
        if($act_ver -gt $cur_ver)
            {
                Write-MyLog -MyLogstring "minion installed but older than actual"
                Uninstall-Salt -MinionPath $uninst_fullpath
                Install-Salt
            }
        Write-MyLog -MyLogstring "minion is installed, version is actual"
    }

Write-MyLog -MyLogstring "*** END ***"