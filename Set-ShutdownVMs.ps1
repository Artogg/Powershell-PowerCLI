<#
.DESCRIPTION
Shutdown toutes les VMs sur tous les ESXi sur vCenter
.INPUTS
Pre-requis:
- module KeePass pour SecretManagement
- module VMWare pour PowerCLI
#>

#Variables
$vCenter="monserveur"

#Connexion au vCenter
Connect-VIServer -Server $vCenter -Protocol https -Credential (Get-Secret -vault "monvaultKeePass" -name "monentreekeepass") -Force

# On recupere tous les ESXI (saufles exceptions)
$TableauESXi = Get-VMHost | Where-Object { $_.name -notlike "mon exception" }
# On recupere toutes les vm sur chaque ESXI et on shutdown (sans confirmation)
Foreach ($VM in ($TableauESXi | Get-VM)){
   $VM | Shutdown-VMGuest -Confirm:$false
}

# J'attends que toutes les VMs soient eteintes avant d'eteindre les ESXi
# J'attends 200 secondes / Valeur arbitraire a estimer selon la taille du parc
$TempsAttente = 200 #Seconds

#Je recupere l'heure pour faire des calculs sur le temps restant
$TempsDebut = (Get-Date).TimeofDay

#Calcul du temps qui passe, si on depasse le temps d'attente parce que certaines VMs ne sont pas eteintes, c'est que certaines vieilles VMs sont potentiellement
#stuck et ont du mal a s'eteindre, passe le delai, j'eteins les ESXi pour forcer le shutdown
do {
    Start-Sleep 1.0
    #le temps restant est le temps d'attente moins le temps ecoule (initialise plus bas, apres la premiere boucle)
    $TempsRestant = $waittime - ($TempsEcoule.seconds)
    #Je prompte le nombre de VM restantes a eteindre et le temps restant
    Write-Output "Il reste : $(($TableauESXi | Get-VM | Where-Object { $_.PowerState -eq "poweredOn" }).Count) VMs àeteindre. `nVeuillez patienter $TempsRestant secondes."
    #Le nouveau temps est l'heure actuelle moins l'heure du debut
    $TempsEcoule = (Get-Date).TimeofDay - $TempsDebut
    } until ((@($TableauESXi | Get-VM | Where-Object { $_.PowerState -eq "poweredOn" }).Count) -eq 0 -or ($TempsEcoule).Seconds -ge $TempsAttente)
 
# On eteint les ESXI apres avoir attendu
$TableauESXi | ForEach-Object {Get-View $_.ID} | ForEach-Object {$_.ShutdownHost_Task($TRUE)}

#On se deconnecte du serveur
Disconnect-VIServer -Server $vCenter -Confirm:$false

Write-Host "Operation terminee."