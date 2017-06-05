#!/bin/bash

#############################################################
#
# check_unifi45
#
# Version 1.0.01
#
# Ein Plugin für Icinga / Nagios
# zur Überwachung und Auswertung eines 
# Unifi-Controllers ab Version 4
#
# Urheber: Daniel Wenzel
# Kontakt: daniel@klenzel.de
#
#
# Abhängigkeiten:
# - 'jq'
# - 'awk'
# - 'curl'
#
# Beispiel für Debian: apt-get install jq curl
#
# ---------------------------------------------
#
# 1.0.01 - Changelog:
#
# 20170605
# - Errorhandling beim Login an Unifi-Controller hinzugefügt
# - Bugfixes
#
#############################################################

#Funktionen
function showUsage {
  echo "
  Benutzung: $0 [Parameter]

  -H  Hostname / IP-Adresse
  
  -P  Port (Standard = 8443)
  
  -u  Benutzername
  
  -p  Passwort
  
  -m  Modul
      'Count-Users'       => Zeigt im WLAN angemeldete Nutzer an
      'Active-Alarms'     => Anzahl der unbestätigten Alarm-Meldungen
      'Offline-APs'       => Anzahl der nicht verfügbaren Accesspoints
      'Has-Updates'       => Anzahl der Accesspoints, für die ein Update zur Verfügung steht
      'Not-Adopted'       => Anzahl der Accesspoints, die keiner Seite zugewiesen wurden
      'Get-DeviceLoad'    => Benötigt Parameter -d => Zeigt die CPU-Auslastung eines Accesspoints an
      'Get-DeviceMem'     => Benötigt Parameter -d => Zeigt die RAM-Belegung eines Accesspoints an
      'Get-DeviceUsers'   => Benötigt Parameter -d => Zeigt die mit einem AP verbundenen Nutzer an
      'Get-DeviceGuests'  => Benötigt Parameter -d => Zeigt die mit einem AP verbundenen Gäste an
      'Show-DevLastSeen'  => Benötigt Parameter -d => Zeigt die Sekunden an, wann der AP zuletzt gesehen wurde
      'Show-Updates'      => Zeigt, ob für den Unifi-Controller Aktualisierungen verfügbar sind
      
  -d  (nur bei bestimmten Modulen notwendig) Angabe der MAC-Adresse eines abzufragenden Accesspoints
  
  -s  Angabe der Seiten-ID (nicht Name!) (Standard = alle Seiten summiert)
  
  -w  Angabe, unter welchem Wert der Status 'Warning' ausgegeben werden soll
      'Count-Users'      => Warnung, wenn Anzahl Nutzer kleiner als der definierte Warning-Wert
                            Eingabe im Format: 'n'
      'Active-Alarms'    => Ab dieser Anzahl von Alarmmeldungen wird der Status 'Warning' ausgeben
                            Eingabe im Format: 'n'
      'Offline-APs'      => Ab dieser Anzahl nicht verfügbarer APs wird der Status 'Warning' ausgeben
                            Eingabe im Format: 'n'
      'Has-Updates'      => Ab dieser Anzahl von gefundenen Upgrades wird der Status 'Warning' ausgeben
                            Eingabe im Format: 'n'
      'Not-Adopted'      => Ab dieser Anzahl nicht zugewiesener Accesspoints wird der Status 'Warning' ausgeben
                            Eingabe im Format: 'n'
      'Get-DeviceLoad'   => Ist die Load der letzten Minute größer als der angegebene Wert, wird der Status 'Warning' ausgeben
                            Eingabe im Format: 'n.nn'
      'Get-DeviceMem'    => Ist die Auslastung des Arbeitsspeichers höher als der angegebene Wert, wird der Status 'Warning' ausgeben
                            Eingabe im Format: 'nn' (z.B. '80' für 80% Auslastung)
      'Get-DeviceUsers'  => Gibt die maximale Anzahl der mit einem AP verbundenen Nutzer an, ab der der Status 'Warning' ausgegeben wird
                            Eingabe im Format: 'n'
      'Get-DeviceGuests' => Gibt die maximale Anzahl der mit einem AP verbundenen Gäste an, ab der der Status 'Warning' ausgegeben wird
                            Eingabe im Format: 'n'
      'Show-DevLastSeen' => Gibt die vergangenen Sekunden der letzten Sichtung an, ab die der Status 'Warning' ausgegeben wird
      
  -c  Angabe, unter welchem Wert der Status 'Critical' ausgegeben werden soll
      Erläuterungen analog zu 'Warning'
  "
}


#Paramter verarbeiten
while [ "$1" != "" ]; do
  case "$1" in
    -H) shift; strHost="$1";;
    -P) shift; intPort="$1";;
    -u) shift; strUsername="$1";;
    -p) shift; strPassword="$1";;
    -m) shift; strModus="$1";;
    -d) shift; strDevice="$1";;
    -s) shift; strSeite="$1";;
    -w) shift; intWarning="$1";;
    -c) shift; intCritical="$1";;
    *) showUsage; exit 3;;
  esac
  shift
done

if [ -z $strHost ] || [ -z $strUsername ] || [ -z $strPassword ] || [ -z $strModus ] || [ -z $intWarning ] || [ -z $intCritical ]; then
  showUsage
  exit 1
fi

if ( [ $strModus == "Get-DeviceLoad" ] || [ $strModus == "Get-DeviceMem" ] || [ $strModus == "Get-DeviceUsers" ] || [ $strModus == "Get-DeviceGuests" ] ) && ( [ -z $strDevice ] ) ; then
  showUsage
  exit 1
fi

if [ -n $strDevice ] ; then
  strDevice=${strDevice,,}
fi

if [ -z $intPort ] ; then
  intPort=8443
fi

if [ -z $strSeite ] ; then
  strSeite="all_sites"
fi



#################

strJQBinary=$(which jq)
if [ $? -ne 0 ] ; then
  echo "Bitte den JSON-Prozessor ${strJQBinary} installieren"
  exit 3
fi

strCurlBinary=$(which curl)
if [ $? -ne 0 ] ; then
  echo "Bitte das Paket curl installieren"
  exit 3
fi

strAWKBinary=$(which awk)
if [ $? -ne 0 ] ; then
  echo "Bitte das Paket awk installieren"
  exit 3
fi


#Meta
intRandom=$(( $RANDOM % 100000 ))
strBaseURL="https://${strHost}:${intPort}"
strCookieFile="/tmp/unifi_${intRandom}.cookie"
strCurlCommand="${strCurlBinary} --tlsv1 --silent --cookie ${strCookieFile} --cookie-jar ${strCookieFile} --insecure"
strLogOutAndCleanUp="${strCurlCommand} $strBaseURL/logout > /dev/null 2>&1 ; rm -f ${strCookieFile}"

#Anmelden am Controller
strLoginStatus=$(${strCurlCommand} --data "{'username':'$strUsername', 'password':'$strPassword'}" $strBaseURL/api/login | ${strJQBinary} '.meta.rc')

if [ $strLoginStatus != "\"ok\"" ] ; then
  echo "Unknown: Anmeldung am Unifi-Controller fehlgeschlagen"
  eval ${strLogOutAndCleanUp}
  exit 2
fi


#Sites ermitteln
arrSites=$(${strCurlCommand} $strBaseURL/api/self/sites | ${strJQBinary} -r '.data[].name')


########## Modi Beginn ##########



# [Count-Users] Zeige angemeldete Nutzer im WLAN
# -------------------------------------------
if [ $strModus == "Count-Users" ] ; then

  intAngemeldeteNutzer=0

  if [ $strSeite == "all_sites" ] ; then

    for strSite in $arrSites; do
      intAngemeldeteNutzer=$((intAngemeldeteNutzer + $(${strCurlCommand} $strBaseURL/api/s/${strSite}/stat/sta | ${strJQBinary} '.data[].mac' | wc -l))) 
    done
    
  else
    intAngemeldeteNutzer=$(${strCurlCommand} $strBaseURL/api/s/${strSeite}/stat/sta | ${strJQBinary} '.data[].mac' | wc -l)
  fi
  
  if [ $intAngemeldeteNutzer -lt $intCritical ] ; then
    echo "Critical: Angemeldete Nutzer (${intAngemeldeteNutzer}) kleiner als die minimale Menge (${intCritical}) | ActiveUsers=${intAngemeldeteNutzer}"
    eval ${strLogOutAndCleanUp}
    exit 2
  elif [ $intAngemeldeteNutzer -lt $intWarning ] ; then
    echo "Warning: Angemeldete Nutzer (${intAngemeldeteNutzer}) kleiner als die minimale Menge (${intWarning}) | ActiveUsers=${intAngemeldeteNutzer}"
    eval ${strLogOutAndCleanUp}
    exit 1
  else
    echo "OK: Es sind ${intAngemeldeteNutzer} Nutzer/Geräte im WLAN aktiv | ActiveUsers=${intAngemeldeteNutzer}"
    eval ${strLogOutAndCleanUp}
    exit 0
  fi
  
fi




# [Active-Alarms] Anzahl der unbestätigten Alarm-Meldungen
# -------------------------------------------
if [ $strModus == "Active-Alarms" ] ; then

  intAlarmMeldungen=0

  if [ $strSeite == "all_sites" ] ; then

    for strSite in $arrSites; do
      intAlarmMeldungen=$((intAlarmMeldungen + $(${strCurlCommand} $strBaseURL/api/s/${strSite}/cnt/alarm?archived=false | ${strJQBinary} '.data[].count'))) 
    done
    
  else
    intAlarmMeldungen=$(${strCurlCommand} $strBaseURL/api/s/${strSeite}/cnt/alarm?archived=false | ${strJQBinary} '.data[].count')
  fi
  
  if [ $intAlarmMeldungen -ge $intCritical ] ; then
    echo "Critical: ${intAlarmMeldungen} aktive Alarmmeldungen (> ${intCritical}) | ActiveAlarms=${intAlarmMeldungen}"
    eval ${strLogOutAndCleanUp}
    exit 2
  elif [ $intAlarmMeldungen -ge $intWarning ] ; then
    echo "Warning: ${intAlarmMeldungen} aktive Alarmmeldungen (> ${intWarning}) | ActiveAlarms=${intAlarmMeldungen}"
    eval ${strLogOutAndCleanUp}
    exit 1
  else
    echo "OK: Es liegen keine oder nur wenige unbestätigte Alarmmeldungen vor (Anzahl ${intAlarmMeldungen})| ActiveAlarms=${intAlarmMeldungen}"
    eval ${strLogOutAndCleanUp}
    exit 0
  fi
  
fi





# [Offline-APs] Anzahl der nicht verfügbaren Accesspoints
# -------------------------------------------
if [ $strModus == "Offline-APs" ] ; then

  strOfflineAPs=""
  intOfflineAPs=0
  intAvailAPs=0

  if [ $strSeite == "all_sites" ] ; then

    for strSite in $arrSites; do
      intAvailAPs=$(( intAvailAPs + $(${strCurlCommand} $strBaseURL/api/s/${strSite}/stat/device | ${strJQBinary} '.data[] | .name' | wc -l)))
      strOfflineAPs+=$(${strCurlCommand} $strBaseURL/api/s/${strSite}/stat/device | ${strJQBinary} '.data[] | select(.state!=1) | .name')
      intOfflineAPs=$(( intOfflineAPs + $(${strCurlCommand} $strBaseURL/api/s/${strSite}/stat/device | ${strJQBinary} '.data[] | select(.state!=1) | .name' | wc -l)))
    done
    
    strOfflineAPs=$(echo ${strOfflineAPs} | tr "\n" ", ")
    
  else
    intAvailAPs=$(${strCurlCommand} $strBaseURL/api/s/${strSeite}/stat/device | ${strJQBinary} '.data[] | .name' | wc -l)
    intOfflineAPs=$(( intOfflineAPs + $(${strCurlCommand} $strBaseURL/api/s/${strSeite}/stat/device | ${strJQBinary} '.data[] | select(.state!=1) | .name' | wc -l)))
    strOfflineAPs=$(${strCurlCommand} $strBaseURL/api/s/${strSeite}/stat/device | ${strJQBinary} '.data[] | select(.state!=1) | .name')
    strOfflineAPs=$(echo ${strOfflineAPs} | tr "\n" ", ")
  fi
  
  intOnlineAPs=$(( intAvailAPs - intOfflineAPs ))
  
  if [ $intOfflineAPs -ge $intCritical ] ; then
    echo "Critical: ${intOfflineAPs} von ${intAvailAPs} Accesspoints nicht verfügbar (${strOfflineAPs}) | OnlineAPs=${intOnlineAPs} OfflineAPs=${intOfflineAPs}"
    eval ${strLogOutAndCleanUp}
    exit 2
  elif [ $intOfflineAPs -ge $intWarning ] ; then
    echo "Warning: ${intOfflineAPs} von ${intAvailAPs} Accesspoints nicht verfügbar (${strOfflineAPs}) | OnlineAPs=${intOnlineAPs} OfflineAPs=${intOfflineAPs}"
    eval ${strLogOutAndCleanUp}
    exit 1
  else
    echo "OK: ${intAvailAPs} von ${intAvailAPs} Accesspoints sind verfügbar | OnlineAPs=${intOnlineAPs} OfflineAPs=${intOfflineAPs}"
    eval ${strLogOutAndCleanUp}
    exit 0
  fi
  
fi





# [Has-Updates] Anzahl der Accesspoints, für die ein Update zur Verfügung steht
# -------------------------------------------
if [ $strModus == "Has-Updates" ] ; then

  strUpgradableAPs=""
  intUpgradableAPs=0
  intAvailAPs=0

  if [ $strSeite == "all_sites" ] ; then

    for strSite in $arrSites; do
      intAvailAPs=$(( intAvailAPs + $(${strCurlCommand} $strBaseURL/api/s/${strSite}/stat/device | ${strJQBinary} '.data[] | .name' | wc -l)))
      strUpgradableAPs+=$(${strCurlCommand} $strBaseURL/api/s/${strSite}/stat/device | ${strJQBinary} '.data[] | select (.upgradable==true) | .name')
      intUpgradableAPs=$(( intUpgradableAPs + $(${strCurlCommand} $strBaseURL/api/s/${strSite}/stat/device | ${strJQBinary} '.data[] | select (.upgradable==true) | .name' | wc -l)))
    done
    strUpgradableAPs=$(echo ${strUpgradableAPs} | tr "\"" " ")
    
  else
    intAvailAPs=$(${strCurlCommand} $strBaseURL/api/s/${strSeite}/stat/device | ${strJQBinary} '.data[] | .name' | wc -l)
    intUpgradableAPs=$(( intUpgradableAPs + $(${strCurlCommand} $strBaseURL/api/s/${strSeite}/stat/device | ${strJQBinary} '.data[] | select (.upgradable==true) | .name' | wc -l)))
    strUpgradableAPs=$(${strCurlCommand} $strBaseURL/api/s/${strSeite}/stat/device | ${strJQBinary} '.data[] | select (.upgradable==true) | .name')
    strUpgradableAPs=$(echo ${strUpgradableAPs} | tr "\n" ", ")
  fi
  
  if [ $intUpgradableAPs -ge $intCritical ] ; then
    echo "Critical: Für ${intUpgradableAPs} von ${intAvailAPs} Accesspoints ist ein Upgrade verfügbar (${strUpgradableAPs}) | UpgradableAPs=${intUpgradableAPs}"
    eval ${strLogOutAndCleanUp}
    exit 2
  elif [ $intUpgradableAPs -ge $intWarning ] ; then
    echo "Warning: Für ${intUpgradableAPs} von ${intAvailAPs} Accesspoints ist ein Upgrade verfügbar (${strUpgradableAPs}) | UpgradableAPs=${intUpgradableAPs}"
    eval ${strLogOutAndCleanUp}
    exit 1
  else
    echo "OK: Es sind keine oder nur wenige Upgrades für Accesspoints verfügbar | UpgradableAPs=${intUpgradableAPs}"
    eval ${strLogOutAndCleanUp}
    exit 0
  fi
  
fi





# [Not-Adopted] Anzahl der Accesspoints, die keiner Seite zugewiesen wurden
# -------------------------------------------
if [ $strModus == "Not-Adopted" ] ; then

  strNotAdoptedAPs=""
  intNotAdoptedAPs=0

  if [ $strSeite == "all_sites" ] ; then

    for strSite in $arrSites; do
      strNotAdoptedAPs+=$(${strCurlCommand} $strBaseURL/api/s/${strSite}/stat/device | ${strJQBinary} '.data[] | select (.adopted!=true) | .name')
      intNotAdoptedAPs=$(( intNotAdoptedAPs + $(${strCurlCommand} $strBaseURL/api/s/${strSite}/stat/device | ${strJQBinary} '.data[] | select (.adopted!=true) | .name' | wc -l)))
    done

    strNotAdoptedAPs=$(echo ${strNotAdoptedAPs} | tr "\"" " ")
    
  else
    intNotAdoptedAPs=$(( intNotAdoptedAPs + $(${strCurlCommand} $strBaseURL/api/s/${strSeite}/stat/device | ${strJQBinary} '.data[] | select (.adopted!=true) | .name' | wc -l)))
    strNotAdoptedAPs=$(${strCurlCommand} $strBaseURL/api/s/${strSeite}/stat/device | ${strJQBinary} '.data[] | select (.adopted!=true) | .name')
    strNotAdoptedAPs=$(echo ${strNotAdoptedAPs} | tr "\n" ", ")
  fi
  
  if [ $intNotAdoptedAPs -ge $intCritical ] ; then
    echo "Critical: Es wurden ${intNotAdoptedAPs} nicht zugewiesene Accesspoints gefunden | NotAdoptedAPs=${intNotAdoptedAPs}"
    eval ${strLogOutAndCleanUp}
    exit 2
  elif [ $intNotAdoptedAPs -ge $intWarning ] ; then
    echo "Warning: Es wurden ${intNotAdoptedAPs} nicht zugewiesene Accesspoints gefunden | NotAdoptedAPs=${intNotAdoptedAPs}"
    eval ${strLogOutAndCleanUp}
    exit 1
  else
    echo "OK: Es wurden keine nicht zugewiesene Accesspoints gefunden | NotAdoptedAPs=${intNotAdoptedAPs}"
    eval ${strLogOutAndCleanUp}
    exit 0
  fi
  
fi





# [Get-DeviceUsers] Zeigt die mit einem AP verbundenen Nutzer an
# -------------------------------------------
if [ $strModus == "Get-DeviceUsers" ] ; then

  intAPBenutzer=0

  for strSite in $arrSites; do
    intAPBenutzerTMP=0
    strAPBenutzerCMD="${strCurlCommand} $strBaseURL/api/s/${strSite}/stat/device | ${strJQBinary} '.data[] | select (.mac==\"${strDevice}\") | .[\"user-num_sta\"]'"
    intAPBenutzerTMP=$(eval ${strAPBenutzerCMD})
    intAPBenutzer=$((intAPBenutzer + intAPBenutzerTMP )) 
  done
  
  if [ $intAPBenutzer -gt $intCritical ] ; then
    echo "Critical: Angemeldete Nutzer am Accesspoint '${strDevice}' größer als die maximale Menge (${intAPBenutzer} > ${intCritical}) | ActiveAPUsers=${intAPBenutzer}"
    eval ${strLogOutAndCleanUp}
    exit 2
  elif [ $intAPBenutzer -gt $intWarning ] ; then
    echo "Warning: Angemeldete Nutzer am Accesspoint '${strDevice}' größer als die maximale Menge (${intAPBenutzer} > ${intWarning}) | ActiveAPUsers=${intAPBenutzer}"
    eval ${strLogOutAndCleanUp}
    exit 1
  else
    echo "OK: Es sind ${intAPBenutzer} Nutzer/Geräte am Accesspoint '${strDevice}' angemeldet | ActiveAPUsers=${intAPBenutzer}"
    eval ${strLogOutAndCleanUp}
    exit 0
  fi
  
fi






# [Get-DeviceGuests] Zeigt die mit einem AP verbundenen Nutzer an
# -------------------------------------------
if [ $strModus == "Get-DeviceGuests" ] ; then

  intAPGaeste=0

  for strSite in $arrSites; do
    intAPGaesteTMP=0
    strAPGaesteCMD="${strCurlCommand} $strBaseURL/api/s/${strSite}/stat/device | ${strJQBinary} '.data[] | select (.mac==\"${strDevice}\") | .[\"guest-num_sta\"]'"
    intAPGaesteTMP=$(eval ${strAPGaesteCMD})
    intAPGaeste=$((intAPGaeste + intAPGaesteTMP )) 
  done
  
  if [ $intAPGaeste -gt $intCritical ] ; then
    echo "Critical: Angemeldete Gäste am Accesspoint '${strDevice}' größer als die maximale Menge (${intAPGaeste} > ${intCritical}) | ActiveAPGuests=${intAPGaeste}"
    eval ${strLogOutAndCleanUp}
    exit 2
  elif [ $intAPGaeste -gt $intWarning ] ; then
    echo "Warning: Angemeldete Gäste am Accesspoint '${strDevice}' kleiner als die maximale Menge (${intAPGaeste} > ${intWarning}) | ActiveAPGuests=${intAPGaeste}"
    eval ${strLogOutAndCleanUp}
    exit 1
  else
    echo "OK: Es sind ${intAPGaeste} Gäste am Accesspoint '${strDevice}' angemeldet | ActiveAPGuests=${intAPGaeste}"
    eval ${strLogOutAndCleanUp}
    exit 0
  fi
  
fi




# [Get-DeviceLoad] Zeigt die CPU-Auslastung eines Accesspoints an
# -------------------------------------------
if [ $strModus == "Get-DeviceLoad" ] ; then

  intLoad1Min=0
  intLoad5Min=0
  intLoad15Min=0
  for strSite in $arrSites; do
    strAPLoad1MinCMD="${strCurlCommand} $strBaseURL/api/s/${strSite}/stat/device | ${strJQBinary} '.data[] | select (.mac==\"${strDevice}\") | .sys_stats | .loadavg_1' | tr -d '\"'"
    strAPLoad5MinCMD="${strCurlCommand} $strBaseURL/api/s/${strSite}/stat/device | ${strJQBinary} '.data[] | select (.mac==\"${strDevice}\") | .sys_stats | .loadavg_5' | tr -d '\"'"
    strAPLoad15MinCMD="${strCurlCommand} $strBaseURL/api/s/${strSite}/stat/device | ${strJQBinary} '.data[] | select (.mac==\"${strDevice}\") | .sys_stats | .loadavg_15' | tr -d '\"'"
    intCheckAPLoad=$(eval ${strAPLoad1MinCMD})
    
    if [ "x${intCheckAPLoad}" != "x" ] ; then
      intLoad1Min=$(eval ${strAPLoad1MinCMD})
      intLoad5Min=$(eval ${strAPLoad5MinCMD})
      intLoad15Min=$(eval ${strAPLoad15MinCMD})
    fi
  done
  
  if ( expr $intLoad1Min \> $intCritical >/dev/null ) ; then
    echo "Critical: CPU-Auslastung des Accesspoints '${strDevice}' zu hoch (${intLoad1Min} > ${intCritical}) | APLoad1Min=${intLoad1Min} APLoad5Min=${intLoad5Min} APLoad15Min=${intLoad15Min}"
    eval ${strLogOutAndCleanUp}
    exit 2
  elif ( expr $intLoad1Min \> $intWarning >/dev/null ) ; then
    echo "Warning: CPU-Auslastung des Accesspoints '${strDevice}' zu hoch (${intLoad1Min} > ${intWarning}) | APLoad1Min=${intLoad1Min} APLoad5Min=${intLoad5Min} APLoad15Min=${intLoad15Min}"
    eval ${strLogOutAndCleanUp}
    exit 1
  else
    echo "OK: CPU-Auslastung des Accesspoints '${strDevice}' in Ordnung (${intLoad1Min}) | APLoad1Min=${intLoad1Min} APLoad5Min=${intLoad5Min} APLoad15Min=${intLoad15Min}"
    eval ${strLogOutAndCleanUp}
    exit 0
  fi

fi





# [GGet-DeviceMem] Zeigt die RAM-Belegung eines Accesspoints an
# -------------------------------------------
if [ $strModus == "Get-DeviceMem" ] ; then

  intAPMemTotal=0
  intAPMemUsed=0
  for strSite in $arrSites; do
    strAPMemTotalCMD="${strCurlCommand} $strBaseURL/api/s/${strSite}/stat/device | ${strJQBinary} '.data[] | select (.mac==\"${strDevice}\") | .sys_stats | .mem_total'"
    strAPMemUsedCMD="${strCurlCommand} $strBaseURL/api/s/${strSite}/stat/device | ${strJQBinary} '.data[] | select (.mac==\"${strDevice}\") | .sys_stats | .mem_used'"
    intCheckAPMem=$(eval ${strAPMemTotalCMD})
    
    if [ "x${intCheckAPMem}" != "x" ] ; then
      intAPMemTotal=$(eval ${strAPMemTotalCMD})
      intAPMemUsed=$(eval ${strAPMemUsedCMD})
    fi
  done
  
  intAPMemFree=$(( intAPMemTotal - intAPMemUsed ))
  intAPMemUsedPercent=$(${strAWKBinary} "BEGIN {OFMT=\"%.2f\"; print $intAPMemUsed / $intAPMemTotal * 100;}")
  
  if ( expr $intAPMemUsedPercent \> $intCritical >/dev/null ) ; then
    echo "Critical: Speicherauslastung des Accesspoints '${strDevice}' zu hoch (${intAPMemUsedPercent}% > ${intCritical}%) | APMemUsedPercent=${intAPMemUsedPercent}% APMemTotal=${intAPMemTotal}B APMemUsed=${intAPMemUsed}B APMemFree=${intAPMemFree}B"
    eval ${strLogOutAndCleanUp}
    exit 2
  elif ( expr $intAPMemUsedPercent \> $intWarning >/dev/null ) ; then
    echo "Warning: Speicherauslastung des Accesspoints '${strDevice}' zu hoch (${intAPMemUsedPercent}% > ${intWarning}%) | APMemUsedPercent=${intAPMemUsedPercent}% APMemTotal=${intAPMemTotal}B APMemUsed=${intAPMemUsed}B APMemFree=${intAPMemFree}B"
    eval ${strLogOutAndCleanUp}
    exit 1
  else
    echo "OK: Speicherauslastung des Accesspoints '${strDevice}' in Ordnung (${intAPMemUsedPercent}% belegt) | APMemUsedPercent=${intAPMemUsedPercent}% APMemTotal=${intAPMemTotal}B APMemUsed=${intAPMemUsed}B APMemFree=${intAPMemFree}B"
    eval ${strLogOutAndCleanUp}
    exit 0
  fi

fi





# [Show-DevLastSeen] Zeigt die Sekunden an, wann der AP zuletzt gesehen wurde
# -------------------------------------------
if [ $strModus == "Show-DevLastSeen" ] ; then

  intTimeStampNow=$(date +%s)
  intDevLastSeen=0
  
  for strSite in $arrSites; do
    strDevLastSeenCMD="${strCurlCommand} $strBaseURL/api/s/${strSite}/stat/device | ${strJQBinary} '.data[] | select (.mac==\"${strDevice}\") | .last_seen'"
    intCheckDevLastSeen=$(eval ${strDevLastSeenCMD})
    if [ $(echo "$intCheckDevLastSeen" | grep [[:digit:]]) ] ; then
      intDevLastSeen=$intCheckDevLastSeen
    fi
  done

  intDevLastSeenSeconds=$(( intTimeStampNow - intDevLastSeen ))
  
  if ( expr $intDevLastSeenSeconds \> $intCritical >/dev/null ); then
    echo "Critical: Letzter Kontakt zum Accesspoint '${strDevice}' zu lange her (vor ${intDevLastSeenSeconds} Sekunden) | APLastSeenSecondsBefore=${intDevLastSeenSeconds}s"
    eval ${strLogOutAndCleanUp}
    exit 2
  elif ( expr $intDevLastSeenSeconds \> $intWarning >/dev/null ) ; then
    echo "Warning: Letzter Kontakt zum Accesspoint '${strDevice}' zu lange her (vor ${intDevLastSeenSeconds} Sekunden) | APLastSeenSecondsBefore=${intDevLastSeenSeconds}s"
    eval ${strLogOutAndCleanUp}
    exit 1
  else
    echo "OK: Letzter Kontakt zum Accesspoint '${strDevice}' vor ${intDevLastSeenSeconds} Sekunden | APLastSeenSecondsBefore=${intDevLastSeenSeconds}s"
    eval ${strLogOutAndCleanUp}
    exit 0
  fi

fi






# [Show-Updates] Zeigt, ob für den Unifi-Controller Aktualisierungen verfügbar sind
# -------------------------------------------
if [ $strModus == "Show-Updates" ] ; then

  boolControllerHasUpdates="false"
  boolControllerHasUpdates="${strCurlCommand} $strBaseURL/api/s/default/stat/sysinfo | ${strJQBinary} '.data[].update_available'"
  
  if [ "z$boolControllerHasUpdates" == "xtrue" ] ; then
    echo "Warning: Für den Unifi-Controller sind Updates verfügbar"
    eval ${strLogOutAndCleanUp}
    exit 1
  else
    echo "OK: Für den Unifi-Controller sind keine Updates verfügbar"
    eval ${strLogOutAndCleanUp}
    exit 0
  fi

fi






#es wurde kein passender Modus gefunden
echo "Unkown: Ungültige Angabe des Moduls"
eval ${strLogOutAndCleanUp}
exit 3
########## Modi Ende ##########