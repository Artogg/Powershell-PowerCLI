<#
.DESCRIPTION
Genere un mail de reporting sur l'utilisation des VMs en se connectant au vCenter au groupe mail de distribution de l'equipe.
.INPUTS
Pre-requis: 
- le module KeePass (et SecretManagement),
- le module VMWare pour PowerCLI.
.EXAMPLE
A placer dans un plannifcateur de tache.
#>

#Connexion au vCenter
$vCenter="monserver"
Connect-VIServer -Server $vCenter -Protocol https -Credential (Get-Secret -vault "monvaultKeePass" -name "monentreekeepass") -Force | Out-Null

#Initialisation des tableaux
$TableauVms = @()
$TableauMemoire = @()
$TableauVMEteintes = @()

#Je recupere les infos des VMs
foreach($vm in Get-View -ViewType Virtualmachine){
    $vms = "" | Select-Object VMHost, VMName, IPAddress, OS, VMState, TotalCPU, TotalMemory, TotalNics, ToolsStatus,ToolsVersion, HardwareVersion, UsedSpaceGB, Datastore, DataStoreSpaceFree, DataStoreSpaceCapacity, Notes
    $vms.VMName = $vm.Name
    $vms.VMHost = Get-View -Id $vm.Runtime.Host -property Name | Select-Object -ExpandProperty Name
    $vms.IPAddress = $vm.guest.ipAddress
    $vms.OS = $vm.Config.GuestFullName 
    $vms.VMState = $vm.summary.runtime.powerState
    $vms.TotalCPU = $vm.summary.config.numcpu
    $vms.TotalMemory = $vm.summary.config.memorysizemb
    $vms.TotalNics = $vm.summary.config.numEthernetCards
    $vms.ToolsStatus = $vm.guest.toolsstatus
    $vms.ToolsVersion = $vm.config.tools.toolsversion 
    $vms.HardwareVersion = $vm.config.Version
    $vms.UsedSpaceGB = [math]::Round($vm.Summary.Storage.Committed/1GB,2)
    $vms.Datastore = $vm.Config.DatastoreUrl[0].Name
    $vms.DataStoreSpaceFree = (get-datastore $vm.Config.DatastoreUrl[0].Name).FreespaceGB
    $vms.DataStoreSpaceCapacity = (get-datastore $vm.Config.DatastoreUrl[0].Name).CapacityGB 
    $TableauVms += $vms

    #Alerte VM eteinte en ciblant le champs VMState
    if ($vms.VMState -like "*poweredOff*"){
        $TableauVMEteintes += $vms.VMName
    }

    #Je catch les alertes de memoire
    #La memoire utilisee est la difference entre la capacite et l'espace libre
    $DatastoreMemoireUtilisee=($vms.DataStoreSpaceCapacity-$vms.DataStoreSpaceFree)
    #Le taux d'occupation
    $DatastoreMemoryThreshold = [math]::Round((($DatastoreMemoireUtilisee*100)/($vms.DataStoreSpaceCapacity)))
    if ($DatastoreMemoryThreshold -ge 85){
        $DatastoreMemoire = New-Object -TypeName PSObject -Property ([Ordered] @{
            'Datastore' = $vms.Datastore
            'Mémoire utilisée Gb' = [math]::Round($DatastoreMemoireUtilisee)
            'Mémoire totale Gb' = [math]::Round($vms.DataStoreSpaceCapacity)
            "Taux d' occupation en %" = $DatastoreMemoryThreshold
        })
        #Les exclusions
        if ($DatastoreMemoire.'Datastore' -notlike 'monexclusion'){
            $TableauMemoire += $DatastoreMemoire
        } 
    }
}

#Je ferme la connection au vCenter
Disconnect-VIServer -Server $vCenter -Confirm:$false
#J'enleve les duplicats de datastore car ils sont lies a plusieurs VMs
$TableauMemoire = $TableauMemoire | Sort-Object -Unique -Property Datastore
#J'exporte les infos des VMs sous forme de CSV et tableau HTML
$TableauVms | Export-Csv ESXI.csv -NoTypeInformation -UseCulture -Encoding Default
$TableauVms | Sort-object -Property VMHost -Ascending | ConvertTo-Html -Head $css -Body "<h1>RAPPORT ESXi Automatique </h1>`n<h5> GENERE LE $(Get-Date -f dd-MM-yyyy)</h5>`n<h5>" | Out-File "ESXI.html"

#GENERATION DU RAPPORT TRANSFERT HTML + CSS POUR RAPPORT TRANSFERT####
$css = @"
<style>
h1, h5, th { text-align: center; font-family: Segoe UI; }
table { margin: auto; font-family: Segoe UI; box-shadow: 10px 10px 5px #888; border: thin ridge grey; }
th { background: #0046c3; color: #fff; max-width: 400px; padding: 5px 10px; }
td { font-size: 11px; padding: 5px 20px; color: #000; }
tr { background: #b8d1f3; }
tr:nth-child(even) { background: #dae5f4; }
tr:nth-child(odd) { background: #b8d1f3; }
</style>
"@

#Configuration des paramètres du mail
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { return $true }
    $encoding = [System.text.encoding]::UTF8
    $smtpServer = ""
    $TO = ""
    $FROM = ""                                                        
    $Subject = "[VmWare] Rapport de Santé des VMs - $(Get-Date -f dd-MM-yyyy)"
    $PJ = "ESXI.html","ESXI.csv"
    
    #Configuration du corps du mail en mettant les alertes de VM eteintes et de datastore en saturation de memoire
    $Body = "Bonjour,

        Veuillez trouver ci-joint le rapport VmWare à date du $(Get-Date -f dd-MM-yyyy)

            $(if (($TableauMemoire) -or ($TableauVMEteintes)){
                if ($TableauMemoire){
                    Write-Output "ATTENTION: Les datastores suivants sont en saturation de mémoire:`n*********************************************************`n"
                    Format-List -InputObject $TableauMemoire  | Out-String 
                }
                if ($TableauVMEteintes.count -gt 0){
                    Write-output "`nLes VMs suivantes sont éteintes:`n*********************************************************`n"
                    Format-List -InputObject $TableauVMeteintes  | Out-String 
            } else {
                Write-Output "Aucune alerte à signaler.`n"
                }
              }   
            )
        Cordialement."    
  
    #J'envoies le mail
    Send-MailMessage -From $FROM -To $TO  -Subject $Subject -Body $Body -Encoding $encoding -Credential (Get-Secret -vault "monvaultKeePass" -name "monentreekeepass") -SmtpServer $smtpServer -UseSsl  -Attachments $PJ

 
   