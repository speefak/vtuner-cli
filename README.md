# vtuner-cli
vtuner config tool / CLI interface managemant 

📡 Aktive vtunerc-Geräte: 0
  Keine vtunerc-Geräte gefunden.

🛰️  Laufende SAT>IP-Verbindungen: 0
  Keine satip-Prozesse aktiv.

📋 Aktuelle Zuordnung (vtuner → SatIP Tuner): 0
  Keine aktive Zuordnung vorhanden.


+---------------------------------------------+
| ✖  Das Modul vtunerc ist nicht geladen.     |
| 1) vtuner Module laden                      |
| 2) vtuner/satip installieren oder prüfen    |
| 3) VDR neu starten                          |
| 4) Abbrechen                                |
+---------------------------------------------+
=> 1

--------------------------------------------------------------------------------------------------------


📡 Aktive vtunerc-Geräte: 4
/dev/vtunerc0 /dev/vtunerc1 /dev/vtunerc2 /dev/vtunerc3 

🛰️  Laufende SAT>IP-Verbindungen: 4
872 /usr/local/bin/satip -s 192.168.1.9 -p 554 -d /dev/vtunerc0 -D DVBS DVBS2 -f 5
873 /usr/local/bin/satip -s 192.168.1.9 -p 554 -d /dev/vtunerc1 -D DVBS DVBS2 -f 6
874 /usr/local/bin/satip -s 192.168.1.9 -p 554 -d /dev/vtunerc2 -D DVBS DVBS2 -f 7
875 /usr/local/bin/satip -s 192.168.1.9 -p 554 -d /dev/vtunerc3 -D DVBS DVBS2 -f 8

📋 Aktuelle Zuordnung (vtuner → SatIP Tuner): 4
  vtunerc0 → frontend 5
  vtunerc1 → frontend 6
  vtunerc2 → frontend 7
  vtunerc3 → frontend 8


+---------------------------------------------+
| ✔  Das Modul vtunerc ist geladen.           |
+---------------------------------------------+
| 1) vtuner Module entladen                   |
| 2) Neu laden (Entladen + neue devices)      |
| 3) SAT>IP-Verbindungen beenden              |
| 4) Alle vtuner/SAT>IP anzeigen              |
| 5) VDR neu starten                          |
| 6) systemd-Service vtuner-satip erstellen   |
| 7) systemd-Service vtuner-satip löschen     |
| 8) vtuner/satip installieren oder prüfen    |
| 9) Abbrechen                                |
+---------------------------------------------+
=>   
