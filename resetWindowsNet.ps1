$inifile=".\config.ini"
# to execute you need to set this up:
# Set-ExecutionPolicy RemoteSigned
# let's check how boot process is going to be
$global:logPath = "C:\Startup\wsl2_boot.log"

# win+r "control.exe ncpa.cpl"可以看到所有网卡的名字
# 将wsl linux和host win的以下"realcardname"网卡通过虚拟的交换机桥接
$global:realcardname =  "e2"

#该"vEthernet (WSL) 2"名字暂时这样，todo：修改一个更容易理解的名字
#这是桥接之后，host win虚拟出的连接虚拟交换机的网卡
$global:virtualwincardname =  "vEthernet (WSL) 2"



#wsl linux的ip
$wslip = "192.168.103.199"
#局域网网关，如果需要转发或者上网，需要设置
$gw = "192.168.103.1"

#windows的ip
$global:winip = "192.168.103.200"
$global:winmask = "255.255.255.0"
$global:wingw = "192.168.103.254"

$global:wslforte_arguments =  "-d Ubuntu-18.04 -u root /etc/init.wsl"


Function GetIniFile
{
$ini = @{}

Get-Content $inifile | ForEach-Object {
  $_.Trim()
} | Where-Object {
  $_ -notmatch '^(;|$)'
} | ForEach-Object {
  if ($_ -match '^\[.*\]$') {
    $section = $_ -replace '\[|\]'
    $ini[$section] = @{}
  } else {
    $key, $value = $_ -split '\s*=\s*', 2
    $ini[$section][$key] = $value
  }
}

$global:winip=$ini.Setting.winip
$global:wslip =$ini.Setting.wslip
$global:gw=$ini.Setting.gw
$global:winmask=$ini.Setting.winmask
$global:wingw=$ini.Setting.wingw
$global:realcardname=$ini.Setting.realcardname
}
GetIniFile
Write-Output " $(Get-Date): $winip" >>$logPath
Write-Output " $(Get-Date): $wslip" >>$logPath
Write-Output " $(Get-Date): $gw" >>$logPath
Write-Output " $(Get-Date): $winmask" >>$logPath
Write-Output " $(Get-Date): $wingw" >>$logPath
Write-Output " $(Get-Date): $realcardname" >>$logPath
$global:wslnet_arguments =  "-u root /usr/local/hiit/configureWSL2Net.sh",$wslip,$gw

function RemoveMulticastRoute{
  $rtn  = 1;
  Do{
      & route delete 224.0.0.0  
      $rtn = $LASTEXITCODE
      if($rtn -ne 0) {
        Write-Output "$(Get-Date):RemoveMulticastRoute failed" >>$logPath
        Start-Sleep 1
      }
  }
  Until($rtn -eq 0)
  Write-Output "$(Get-Date):RemoveMulticastRoute done" >>$logPath
}

function StartForteSupervisord{
  $rtn  = 1;
  Do{
    Start-Sleep 1
    $rtn = (Start-Process -FilePath "wsl.exe" -ArgumentList $wslforte_arguments -Wait -Passthru).ExitCode
    if ($rtn -ne 0) {
      Write-Output "$(Get-Date):StartForteSupervisord failed" >>$logPath
      Start-Sleep 1
    }
  }
  Until($rtn -eq 0)
  Write-Output "$(Get-Date):StartForteSupervisord done" >>$logPath
}



function ConfigureWINNetwork {
  $rtn  = 1;
  Do{
      #& netsh interface ipv4 set address name=$virtualwincardname source=dhcp
      #& netsh interface ipv4 set dns name=$virtualwincardname source=dhcp
      & netsh interface ipv4 set address name=$virtualwincardname static $winip $winmask $wingw
      & netsh interface ipv4 set dns name=$virtualwincardname  static 8.8.8.8
      $rtn = $LASTEXITCODE
      if ($rtn -ne 0) {
        Write-Output "$(Get-Date):ConfigureWINNetwork failed" >>$logPath
        Start-Sleep 1
      }
  }
  Until($rtn -eq 0)
  Write-Output "$(Get-Date):ConfigureWINNetwork done" >>$logPath
}
# TODO: configureWSL2Net set global variable with path to shell script to configure WSL network interface inside Linux
# this function is used to configure network settings after VMSwitch is ready to be used by wsl instance
function ConfigureWSLNetwork {

     
    #Write-Output "Starting WSL..." >> $logPath
    
    $wslStatus = Get-Process -Name "wsl" -ErrorAction SilentlyContinue
    if (!($wslStatus)) {
        Start-Job -ScriptBlock { Start-Process -FilePath "wsl.exe" -WindowStyle hidden }
    }   
    
    Do {

        $wslStatus = Get-Process -Name "wsl" -ErrorAction SilentlyContinue
    
        If (!($wslStatus)) { Write-Output "$(Get-Date):Waiting for WSL2 process to start" >> $logPath ; Start-Sleep 1 }
        
        Else { Write-Output "$(Get-Date):WSL Process has started, configuring network" >> $logPath ; $wslStarted = $true }
    
    }
    Until ( $wslStarted )

    $wslStatus 5>> $logPath
    
    # wsl --distribution Ubuntu-20.04 -u root /home/p/configureWSL2Net.sh
    # configureWSL2Net.sh needs to be made executable
    #Start-Process -FilePath "wsl.exe" -ArgumentList "-u root /usr/local/hiit/configureWSL2Net.sh"
    Start-Process -FilePath "wsl.exe" -ArgumentList $wslnet_arguments 

    Write-Output "$(Get-Date):ConfigureWSLNetwork done" >> $logPath
    
    Write-Output "$(Get-Date):$wslStatus" 5>> $logPath
    
    return 0
    
    
}


#  force launch without going to bash prompt
wsl exit

wsl -l -v *>> $logPath


$started = $false

Do {

    

    Write-Output " $(Get-Date): forte is starting!" >>$logPath
    RemoveMulticastRoute ;

    $status = Get-VMSwitch WSL -ErrorAction SilentlyContinue
    Write-Output "$(Get-Date):$status" >> $logPath
    If (!($status)) { Write-Output "$(Get-Date):Waiting for WSL swtich to get registered" ; Start-Sleep 1 }
    
    Else {
        #Write-Output  "WSL Network found" ; 
        $started = $true; 
        # manipulate network adapter tickboxes - Adapter cannot be bound because binding to Hyper-V is still there after M$ windows restarts.
        # Get-NetAdapterBinding Ethernet to view components of the interface vms_pp is what we look for
        Set-NetAdapterBinding -Name $realcardname -ComponentID vms_pp -Enabled $False ;
        Set-VMSwitch WSL -NetAdapterName $realcardname ;
        $started = $true ;
        # Hook all Hyper V VMs to WSL network => avoid network performance issues.
        #Write-Output  "Getting all Hyper V machines to use WSL Switch" >> $logPath ; 
        Get-VM | Get-VMNetworkAdapter | Connect-VMNetworkAdapter -SwitchName "WSL" ; 
        # now that host network is configured we can set up wsl network
        ConfigureWSLNetwork ;
        ConfigureWINNetwork ;
        # Start All Hyper VMs
        Get-VM | Start-VM ;

        Write-Output "$(Get-Date):After network card bridging" >>$logPath
        $statusA = Get-VMSwitch WSL -ErrorAction SilentlyContinue
        Write-Output "$(Get-Date):$statusA" >> $logPath

        StartForteSupervisord ;
    }

}
Until ( $started )
