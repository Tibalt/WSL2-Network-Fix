# to execute you need to set this up:
# Set-ExecutionPolicy RemoteSigned
# let's check how boot process is going to be
$global:logPath = "C:\Startup\wsl2_boot.log"

# win+r "control.exe ncpa.cpl"可以看到所有网卡的名字
# 将wsl linux和host win的以下"realcardname"网卡通过虚拟的交换机桥接
$global:realcardname =  "e3"

#该"vEthernet (WSL) 2"名字暂时这样，todo：修改一个更容易理解的名字
#这是桥接之后，host win虚拟出的连接虚拟交换机的网卡
$global:virtualwincardname =  "vEthernet (WSL) 2"



#wsl linux的ip
$wslip = "192.168.103.99/24"
#局域网网关，如果需要转发或者上网，需要设置
$gw = "192.168.103.1"

#windows的ip
$global:winip = "192.168.103.7/24"

$global:wslnet_arguments =  "-u root /usr/local/hiit/configureWSL2Net.sh",$wslip,$gw

$global:wslforte_arguments =  "-d Ubuntu-18.04 -u root /etc/init.wsl"


function RemoveMulticastRoute{
  $rtn  = 1;
  Do{
      & route delete 224.0.0.0  
      $rtn = $LASTEXITCODE
      if($rtn -ne 0) {
        write-host "RemoveMulticastRoute failed" >>$logPath
        Start-Sleep 1
      }
  }
  Until($rtn -eq 0)
  write-host "RemoveMulticastRoute done" >>$logPath
}

function StartForteSupervisord{
  $rtn  = 1;
  Do{
    Start-Sleep 1
    $rtn = (Start-Process -FilePath "wsl.exe" --ArgumentList $wslforte_arguments -Wait -Passthru).ExitCode
    if ($rtn -ne 0) {
      write-host "StartForteSupervisord failed" >>$logPath
      Start-Sleep 1
    }
  }
  Until($rtn -eq 0)
  write-host "StartForteSupervisord done" >>$logPath
}



function ConfigureWINNetwork {
#netsh interface ip set address "vEthernet (WSL) 2" static $winip
  $rtn  = 1;
  Do{
      & netsh interface ip set address $virtualwincardname static $winip
      $rtn = $LASTEXITCODE
      if ($rtn -ne 0) {
        write-host "ConfigureWINNetwork failed" >>$logPath
        Start-Sleep 1
      }
  }
  Until($rtn -eq 0)
}
# TODO: configureWSL2Net set global variable with path to shell script to configure WSL network interface inside Linux
# this function is used to configure network settings after VMSwitch is ready to be used by wsl instance
function ConfigureWSLNetwork {

     
    Write-Output "Starting WSL..." >> $logPath
    
    $wslStatus = Get-Process -Name "wsl" -ErrorAction SilentlyContinue
    if (!($wslStatus)) {
        Start-Job -ScriptBlock { Start-Process -FilePath "wsl.exe" -WindowStyle hidden }
    }   
    
    Do {

        $wslStatus = Get-Process -Name "wsl" -ErrorAction SilentlyContinue
    
        If (!($wslStatus)) { Write-Output 'Waiting for WSL2 process to start' >> $logPath ; Start-Sleep 1 }
        
        Else { Write-Output 'WSL Process has started, configuring network' >> $logPath ; $wslStarted = $true }
    
    }
    Until ( $wslStarted )

    $wslStatus 5>> $logPath
    
    # wsl --distribution Ubuntu-20.04 -u root /home/p/configureWSL2Net.sh
    # configureWSL2Net.sh needs to be made executable
    #Start-Process -FilePath "wsl.exe" -ArgumentList "-u root /usr/local/hiit/configureWSL2Net.sh"
    Start-Process -FilePath "wsl.exe" -ArgumentList $wslnet_arguments 

    Write-Output "wsl network configuration completed" >> $logPath
    
    Write-Output $wslStatus 5>> $logPath
    
    return 0
    
    
}


#  force launch without going to bash prompt
wsl exit

wsl -l -v *>> $logPath


$started = $false

Do {

    RemoveMulticastRoute ;

    $status = Get-VMSwitch WSL -ErrorAction SilentlyContinue
    Write-Output $status >> $logPath
    If (!($status)) { Write-Output 'Waiting for WSL swtich to get registered' ; Start-Sleep 1 }
    
    Else {
        Write-Output  "WSL Network found" ; 
        $started = $true; 
        # manipulate network adapter tickboxes - Adapter cannot be bound because binding to Hyper-V is still there after M$ windows restarts.
        # Get-NetAdapterBinding Ethernet to view components of the interface vms_pp is what we look for
        Set-NetAdapterBinding -Name $realcardname -ComponentID vms_pp -Enabled $False ;
        Set-VMSwitch WSL -NetAdapterName $realcardname ;
        $started = $true ;
        # Hook all Hyper V VMs to WSL network => avoid network performance issues.
        Write-Output  "Getting all Hyper V machines to use WSL Switch" >> $logPath ; 
        Get-VM | Get-VMNetworkAdapter | Connect-VMNetworkAdapter -SwitchName "WSL" ; 
        # now that host network is configured we can set up wsl network
        ConfigureWSLNetwork ;
        ConfigureWINNetwork ;
        # Start All Hyper VMs
        Get-VM | Start-VM ;
        StartForteSupervisord ;
    }

}
Until ( $started )
