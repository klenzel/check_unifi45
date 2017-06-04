# check_unifi45
Nagios / Icinga-Plugin für den Unifi-Controller (Version >4)

Meta:
#####
Ein Plugin für Icinga / Nagios
zur Überwachung und Auswertung eines 
Unifi-Controllers ab Version 4

Urheber: Daniel Wenzel
Kontakt: daniel@klenzel.de

Installation
############
Abhängigkeiten:
- 'jq'
- 'awk'
- 'curl'

Beispiel für Debian: apt-get install jq curl

Beispiele für die Konfigurartion von Icinga unter examples.txt!

Benutzung:
##########
-H  Hostname / IP-Adresse

-P  Port (Standard = 8443)

-u  Benutzername

-p  Passwort

-m  Modul
    'Count-Users'       => Zeigt im WLAN angemeldet Nutzer an
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
    'Get-DeviceMem'    =>
                          Eingabe im Format: 'nn' (z.B. '80' für 80% Auslastung)
    'Get-DeviceUsers'   => Gibt die maximal Anzahl der mit einem AP verbundenen Nutzer an, ab der der Status 'Warning' ausgegeben wird
                          Eingabe im Format: 'n'
    'Get-DeviceGuests' => Gibt die maximal Anzahl der mit einem AP verbundenen Gäste an, ab der der Status 'Warning' ausgegeben wird
                          Eingabe im Format: 'n'
    'Show-DevLastSeen' => Gibt die vergangenen Sekunden der letzten Sichtung an, ab der der Status 'Warning' ausgegeben wird
    
-c  Angabe, unter welchem Wert der Status 'Critical' ausgegeben werden soll
    Erläuterungen analog zu 'Warning'
