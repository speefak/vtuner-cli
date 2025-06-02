#!/bin/bash
# name          : vtuner-cli
# desciption    : manage vtuner and satip connections
# autor         : speefak ( itoss@gmx.de )
# licence       : (CC) BY-NC-SA
# version       : 1.5
# notice        :
# infosource    : ChatGPT
#
#------------------------------------------------------------------------------------------------------------------------------------------------
############################################################################################################
#######################################   define global variables   ########################################
############################################################################################################
#------------------------------------------------------------------------------------------------------------------------------------------------

 SatipBIN="/usr/local/bin/satip"
 SatipServer="192.168.1.9"
 SatipPORT="554"
 
 RequiredPackets="dkms git build-essential linux-headers-$(uname -r) libcap-dev psmisc w-scan"

 SystemdServiceFile="/etc/systemd/system/vtuner-satip.service"
 CheckMark=$'\033[0;32m✔\033[0m'   # Grün ✔
 CrossMark=$'\033[0;31m✖\033[0m'   # Rot ✖

#------------------------------------------------------------------------------------------------------------------------------------------------
############################################################################################################
###########################################   define functions   ###########################################
############################################################################################################
#------------------------------------------------------------------------------------------------------------------------------------------------
show_status () {
    vTunerModules=$(ls /dev/vtunerc* 2>/dev/null | tr " " "\n")
    SatIPProcesses=$(pgrep -fa "$SatipBIN" | grep -v "/bin/bash -c  $SatipBIN")

    echo ""
    echo "+------------------------------------------------------------------------------------------+"
    echo "| Aktive vtuner 📡 und SAT>IP-Verbindungen 🛰️                                               |"
    echo "+-------------+-----------------+----------------------------------------------------------+"
    if is_driver_loaded; then
        for vtunerPath in $vTunerModules; do
            vtuner=$(basename "$vtunerPath")             # z.B. vtunerc0
            stuner=$(echo "$SatIPProcesses" | grep $vtunerPath | awk -F " -f" '{print $2}' )
            process=$(pgrep -fa "$SatipBIN" | grep -v "/bin/bash -c  $SatipBIN" | grep "$vtunerPath" <<< $SatIPProcesses)

            if [ -n "$process" ]; then
                echo "| 📡 $vtuner | 🛰️  xIP tuner$stuner  | $(echo "$process" | awk -F "$SatipBIN -s " '{print $2}' ) $CheckMark |"
            else
                echo "| 📡 $vtuner | 🛑  no tuner    |                                                        $CrossMark |"
            fi
        done
    else
        echo "| 📡 Keine vtunerc-Geräte gefunden.                                                         |"
   fi
   echo "+-------------+-----------------+----------------------------------------------------------+"
}
#------------------------------------------------------------------------------------------------------------------------------------------------
load_driver() {
    local devices
    while true; do
        read -p " Wie viele Devices sollen geladen werden? " devices
        if [[ "$devices" =~ ^[1-9][0-9]*$ ]]; then
            break
        else
            echo " Bitte eine gültige Zahl eingeben."
        fi
    done
    printf "\r 📥 Lade vtunerc mit $devices Devices..."
    sudo modprobe vtunerc devices=$devices && printf "\r Lade vtunerc mit $devices Devices $CheckMark     " || printf "\r Lade vtunerc mit $devices Devices $CrossMark     "
    echo ""
}
#------------------------------------------------------------------------------------------------------------------------------------------------
unload_driver() {
    stop_satip_processes
    printf " 📤 Entlade vtunerc-Module ... "
    if sudo rmmod -f vtunerc; then
        printf "\r Entlade vtunerc-Module $CheckMark     "
        echo ""
    else
        printf "\r Entlade vtunerc-Module $CrossMark     "
        echo ""
        exit 1
    fi
}
#------------------------------------------------------------------------------------------------------------------------------------------------
manage_vtuner_modules() {
    show_status
    echo ""
    echo "+------------------------------------------------------------------------------------------+"
    echo "| 1) vtuner Module entladen                  x) Zurück                                     |"
    echo "| 2) vtuner Module neu erstellen                                                           |"
    echo "+------------------------------------------------------------------------------------------+"
    read -p "=> " choice
    echo ""

    case "$choice" in
        1)
            unload_driver
            ;;
        2)
            unload_driver
            
            local devices
            devices=$(count_loaded_devices)
            configure_frontends "$devices"
            show_status

            while true; do
                read -p " Wie viele Devices sollen geladen werden? " devices
                if [[ "$devices" =~ ^[1-9][0-9]*$ ]]; then
                    break
                else
                    echo " Bitte eine gültige Zahl eingeben."
                fi
            done

            printf " 📥 Lade vtunerc mit $devices Devices..."
            sudo modprobe vtunerc devices=$devices && printf "\r 📥 Lade vtunerc mit $devices Devices $CheckMark     " || printf "\r 📥 Lade vtunerc mit $devices Devices $CrossMark     "
            echo ""

            read -e -p " 🛠️  SAT>IP-Verbindungen initiallisieren? (j/N): " -i "j" choice
            if [[ "$choice" =~ ^[JjYy]$ ]]; then
                manage_satip_connections
            else
                printf "\r ⚠️  🛠️  SAT>IP-Verbindungen nicht initialisiert."
            fi

            create_systemd_service
            ;;
        x|X)
            echo " ↩️  Zurück"
            return
            ;;
        *)
            echo " Ungültige Auswahl."
            ;;
    esac
}
#------------------------------------------------------------------------------------------------------------------------------------------------
manage_satip_connections() {
    show_status
    echo ""
    echo "+------------------------------------------------------------------------------------------+"
    echo "| 📡 SAT>IP-Verbindungen                                                                   |"
    echo "+------------------------------------------------------------------------------------------+"
    echo "| 1) Neue Verbindung herstellen                                                            |"
    echo "| 2) Verbindung beenden                      x) Zurück                                     |"
    echo "+------------------------------------------------------------------------------------------+"
    read -p "=> " satip_choice

    case "$satip_choice" in
        1)
            # Nur freie vtunerc-Geräte anzeigen
            local used=()
            while IFS= read -r line; do
                [[ "$line" =~ (/dev/vtunerc[0-9]+) ]] && used+=("${BASH_REMATCH[1]}")
            done < <(pgrep -fa "$SatipBIN")

            for dev in /dev/vtunerc*; do
                [[ -e "$dev" ]] || continue
                if [[ ! " ${used[*]} " =~ " ${dev} " ]]; then
                    local index=${dev#/dev/vtunerc}
                    local default_frontend=$((index+1))
                    echo ""
                    printf " → $dev"
                    while true; do
                        read -e -p " | SatIP Tuner für vtuner$index (default: ${default_frontend}): " frontend
                        frontend=${frontend:-$default_frontend}
                        if [[ "$frontend" =~ ^[0-9]+$ ]]; then
                            echo " → Starte SAT>IP-Anbindung für vtuner$index SatIP Tuner $frontend"
                            $SatipBIN -s $SatipServer -p $SatipPORT -d "$dev" -D DVBS,DVBS2 -f $frontend &
                            break
                        else
                            echo " Ungültige Eingabe. Bitte eine Zahl eingeben. $CrossMark"
                        fi
                    done
                fi
            done

            echo ""
            echo " Neue Verbindungen wurden hergestellt. $CheckMark"
            ;;

        2)
            # Nur aktive Prozesse zur Auswahl anbieten
            echo ""
            echo " 🔌 Aktive Verbindungen:"
            local pids=()
            local entries=()
            local i=1

            while IFS= read -r line; do
                local pid=$(awk '{print $1}' <<< "$line")
                local vt=$(grep -o '/dev/vtunerc[0-9]*' <<< "$line")
                local fe=$(echo "$line" | grep -oP -- '-f\s*\K\d+')
                pids+=("$pid")
                entries+=("$vt (Tuner $fe)")
                echo " $i) $vt (Tuner $fe)"
                ((i++))
            done < <(pgrep -fa "$SatipBIN")

            if [ ${#pids[@]} -eq 0 ]; then
                echo " Keine aktiven Verbindungen gefunden. $CrossMark"
                return
            fi

            echo ""
            read -p " Welche Verbindung soll beendet werden? (Nummer): " selection
            if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ${#pids[@]} )); then
                local kill_pid=${pids[$((selection-1))]}
                kill "$kill_pid"
                echo " Verbindung ${entries[$((selection-1))]} wurde beendet. $CheckMark"
            else
                echo " Ungültige Auswahl. $CrossMark"
            fi
            ;;
        x)
            echo " ↩️  Zurück"
            return
            ;;
        *)
            echo " Ungültige Auswahl."
            ;;
    esac
}
#------------------------------------------------------------------------------------------------------------------------------------------------
stop_satip_processes() {
    printf " Beende alle SAT>IP-Verbindungen ..."
    pkill -f "$SatipBIN" && printf "\r Beende alle SAT>IP-Verbindungen $CheckMark    " || printf "\r Beende alle SAT>IP-Verbindungen $CrossMark    "
    echo ""
}
#------------------------------------------------------------------------------------------------------------------------------------------------
configure_frontends() {
    local devices=$1
    echo ""
    echo " 🎛️  Starte Zuordnung der vtunerc-Devices zu SatIP Tunern:"
    for ((i=0; i<devices; i++)); do
        echo ""
        printf " → /dev/vtunerc$i"
        while true; do
            read -e -p " | SatIP Tuner für vtuner$i (default: ${default_frontend}): " frontend
            frontend=${frontend:-$default_frontend}
            if [[ "$frontend" =~ ^[0-9]+$ ]]; then
                echo " → Starte SAT>IP-Anbindung für vtuner$i SatIP Tuner $frontend"
                $SatipBIN -s $SatipServer -p $SatipPORT -d /dev/vtunerc$i -D DVBS,DVBS2 -f $frontend &
                break
            else
                echo " Ungültige Eingabe. Bitte eine Zahl für das VDR-Frontend eingeben. $CrossMark"
            fi
        done
    done
    echo ""
    echo " Alle Zuordnungen abgeschlossen. $CheckMark "
}
#------------------------------------------------------------------------------------------------------------------------------------------------
install_vtuner_and_satip() {
    echo " 🔍 Prüfe, ob vtunerc-Modul installiert ist ..."
    if modinfo vtunerc &>/dev/null; then
        echo " $CheckMark vtunerc ist bereits installiert."
    else
        echo " ⬇️  Installiere vtunerc-Modul über DKMS ..."

        set -e

        sudo apt update
        sudo apt install -y $RequiredPackets

        cd /tmp || exit 1

        if [ ! -d vtuner-ng ]; then
            git clone https://github.com/joed74/vtuner-ng.git
        else
            echo " vtuner-ng Verzeichnis existiert bereits."
        fi

        sudo mkdir -p /usr/src/vtuner-ng-0.0.1

        cat <<EOF | sudo tee /usr/src/vtuner-ng-0.0.1/dkms.conf >/dev/null
PACKAGE_NAME="vtuner-ng"
PACKAGE_VERSION="0.0.1"
BUILT_MODULE_NAME[0]="vtunerc"
DEST_MODULE_LOCATION[0]="/kernel/drivers/media/dvb-frontends/"
AUTOINSTALL="yes"
MAKE[0]="make -C /lib/modules/\${kernelver}/build M=\${dkms_tree}/\${PACKAGE_NAME}/\${PACKAGE_VERSION}/build"
CLEAN="make -C /lib/modules/\${kernelver}/build M=\${dkms_tree}/\${PACKAGE_NAME}/\${PACKAGE_VERSION}/build clean"
EOF

        cd vtuner-ng/kernel || exit 1
        sudo ln -sf . build
        sudo cp -r * /usr/src/vtuner-ng-0.0.1/

        sudo dkms remove -m vtuner-ng -v 0.0.1 --all || true
        sudo dkms add -m vtuner-ng -v 0.0.1
        sudo dkms build -m vtuner-ng -v 0.0.1
        sudo dkms install -m vtuner-ng -v 0.0.1

        echo " vtunerc modul installiert. $CheckMark"
    fi

    echo ""
    echo " 🔍 Prüfe, ob satip-Tool verfügbar ist ..."
    if command -v satip &>/dev/null; then
        echo " satip ist bereits installiert. $CheckMark"
    else
        echo " ⬇️  Baue und installiere satip ..."
        cd /tmp/vtuner-ng/satip || { echo "$CrossMark satip-Verzeichnis nicht gefunden!"; return 1; }
        make
        sudo make install
        echo " Satip erfolgreich installiert. $CheckMark"
    fi

    echo ""
    echo " 📦 Installation abgeschlossen."
}
#------------------------------------------------------------------------------------------------------------------------------------------------
create_systemd_service() {

    if [[ ! $1 == "-s" ]]; then
        read -e -p " 🛠️  Soll ein systemd-Service für vtuner-satip erstellt werden? (j/N): " -i "j" choice
        if [[ "$choice" =~ ^[Nn]$ ]]; then
            echo " ⚠️  Kein systemd-Service erstellt."
            return 1
        fi
    fi

    local SystemdServiceFile="/etc/systemd/system/vtuner-satip.service"
    local vtunerdevs=( /dev/vtunerc* )
    local pids=$(pgrep -fa "$SatipBIN" | grep -v "/bin/bash -c  $SatipBIN" | cut -d " " -f1)

    if [[ ! -e "${vtunerdevs[0]}" || -z "$pids" ]]; then
        echo " Keine aktiven vtuner- oder satip-Prozesse gefunden. $CrossMark "
        return 1
    fi

    echo " 📄 Erstelle systemd-Service: $SystemdServiceFile"

    # Header
    sudo tee "$SystemdServiceFile" > /dev/null <<EOF
[Unit]
Description=Start vtuner → satip Bindings
After=network.target vdr.service

[Service]
Type=simple
RemainAfterExit=false
ExecStartPre=/sbin/modprobe vtunerc devices=${#vtunerdevs[@]}
ExecStart=/bin/bash -c '\\
EOF

    # Für jeden satip-Prozess vollständige Kommandozeile extrahieren und Zeile schreiben
    for pid in $pids; do
        if [[ -f "/proc/$pid/cmdline" ]]; then
            # cmdline ist nullbyte-separiert → in lesbaren String umwandeln
            cmdline=$(tr '\0' ' ' < /proc/$pid/cmdline)
            [[ "$cmdline" == *"$SatipBIN"* ]] || continue
            # -D XX YY in -D XX,YY umwandeln
            cmdline=$(sed -E 's/-D ([A-Z0-9]+) ([A-Z0-9]+)/-D \1,\2/' <<< "$cmdline")
            sudo tee -a "$SystemdServiceFile" > /dev/null <<< "$cmdline & \\"
        fi
    done

    # VDR restart nach allen satip-Prozessen
    sudo tee -a "$SystemdServiceFile" > /dev/null <<< "/bin/systemctl restart vdr; \\"

    # Abschlusszeile
    sudo tee -a "$SystemdServiceFile" > /dev/null <<EOF
wait'
#ExecStop=/usr/bin/pkill -f $SatipBIN			# causes systemfreeze when shutdown system
#ExecStopPost=/sbin/rmmod -f vtunerc			# causes systemfreeze when shutdown system

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now vtuner-satip.service
    systemctl enable vtuner-satip.service
    echo " systemd-Service wurde korrekt erstellt und aktiviert. $CheckMark"
}
#------------------------------------------------------------------------------------------------------------------------------------------------
delete_systemd_service() {
    printf " 🗑️  Lösche vtuner systemd-service ..."

    if [[ -f "$SystemdServiceFile" ]]; then
        sudo systemctl stop vtuner-satip.service
        sudo systemctl disable vtuner-satip.service
        sudo rm -f "$SystemdServiceFile"
        sudo systemctl daemon-reload
        echo " Lösche vtuner systemd-service $CheckMark     "
    else
        echo " Lösche vtuner systemd-service $CrossMark    "
        echo " Kein vtuner-satip Service gefunden unter $SystemdServiceFile"
    fi
}
#------------------------------------------------------------------------------------------------------------------------------------------------
is_driver_loaded() {
    lsmod | grep -q "^vtunerc"
}
#------------------------------------------------------------------------------------------------------------------------------------------------
count_loaded_devices() {
    ls /dev/vtunerc* 2>/dev/null | wc -l
}
#------------------------------------------------------------------------------------------------------------------------------------------------
restart_vdr() {
    printf " vdr neustart in 3 sekunden, abbrechen mit belieber Taste"
    read -s -t 3 -n 1 key
    if [[ $? -eq 0 ]]; then
        printf "\r%-70s\r" " vdr neustart abgebrochen $CrossMark"
        echo ""
    else
        printf "\r%-70s\r" " VDR neustart ..."
        sudo timeout 30 systemctl restart vdr && echo " VDR neustart $CheckMark    " || echo " VDR neustart $CrossMark    " && journalctl -u vdr -xe
    fi
}
#------------------------------------------------------------------------------------------------------------------------------------------------
show_systemd_service() {
    echo ""
    echo "+------------------------------------------------------------------------------------------+"
    echo "| systemd service file ($SystemdServiceFile)                          |"
    echo "+------------------------------------------------------------------------------------------+"
    echo ""
    cat $SystemdServiceFile
    echo ""
    echo "+------------------------------------------------------------------------------------------+"
    echo "+                                                                                          +"
    echo "+------------------------------------------------------------------------------------------+"
    echo ""
}
#------------------------------------------------------------------------------------------------------------------------------------------------
manage_systemd_service() {
    show_status
    echo ""
    echo "+------------------------------------------------------------------------------------------+"
    echo "| 🛠️  systemd-Service Optionen                                                              |"
    echo "+------------------------------------------------------------------------------------------+"
    echo "| 1) Service erstellen                           3) Service löschen                        |"
    echo "| 2) Service anzeigen                            x) Zurück                                 |"
    echo "+------------------------------------------------------------------------------------------+"
    read -p "=> " subchoice
    echo ""

    case "$subchoice" in
        1)
            create_systemd_service -s
            ;;
        2)
            show_systemd_service
            ;;
        3)
            delete_systemd_service
            ;;
        x)
            echo "↩️  Zurück"
            return
            ;;
        *)
            echo "Ungültige Auswahl."
            ;;
    esac
}
#------------------------------------------------------------------------------------------------------------------------------------------------
show_main_menu() {
    while true; do
        if is_driver_loaded; then
            show_status
            echo ""
            echo "+------------------------------------------------------------------------------------------+"
            echo "| 1) vtuner Module verwalten                 4) VDR neu starten                            |"
            echo "| 2) SAT>IP-Verbindungen verwalten           5) vtuner/satip installieren oder prüfen      |"
            echo "| 3) systemd-Service verwalten               x) Exit                                       |"
            echo "+------------------------------------------------------------------------------------------+"
            read -p "=> " choice
            echo ""

            case "$choice" in
                1)
                    manage_vtuner_modules
                    ;;
                2)
                    manage_satip_connections
                    ;;
                3)
                    manage_systemd_service
                    ;;
                4)
                    restart_vdr
                    ;;
                5)
                    install_vtuner_and_satip
                    ;;
                x)
                    return
                    ;;
                *)
                    echo "Ungültige Auswahl."
                    ;;
            esac
        else
            echo ""
            echo "+---------------------------------------------+"
            echo "| $CrossMark  Das Modul vtunerc ist nicht geladen.     |"
            echo "| 1) vtuner Module laden                      |"
            echo "| 2) vtuner/satip installieren oder prüfen    |"
            echo "| x) Zurück                                   |"
            echo "+---------------------------------------------+"
            read -p "=> " choice
            echo ""
            case "$choice" in
                1)
                    load_driver
                    devices=$(count_loaded_devices)
                    configure_frontends "$devices"
                    create_systemd_service
                    restart_vdr
                    ;;
                2)
                    install_vtuner_and_satip
                    ;;
                3)
                    restart_vdr
                    ;;
                x)
                    return
                    ;;
                *)
                    echo " Ungültige Auswahl."
                    ;;
            esac
        fi
    done
}
#------------------------------------------------------------------------------------------------------------------------------------------------
############################################################################################################
#############################################   start script   #############################################
############################################################################################################
#------------------------------------------------------------------------------------------------------------------------------------------------

	# check for root permission
	if [ "$(whoami)" != "root" ]; then
		echo "Are you root?"
		exit 1
	fi

#------------------------------------------------------------------------------------------------------------------------------------------------

	# Main Script
	show_main_menu

#------------------------------------------------------------------------------------------------------------------------------------------------

exit 0

#------------------------------------------------------------------------------------------------------------------------------------------------


# TODO => detailielrte menu / abfragen für satip verbindunge verwalten:
# wenn neue verbindung dann nur freie /dev/vtunerX verwenden, wenn kein tuner frei dann meldung alle tuner belegt
# wenn verbindung beenden dann nur verbindungen zur auswahl anzeigen die mit einem satip prozess belegt sind

# TODO create function: save conf datei
# save config in /root/.vtuner-cli.conf (conf datei)
# config dialog for global variables | satip server ip =< save config in conf datei
# save vtuner count in conf datei
# save vtuner - frontend zuornung in conf datei

# TODO create function: load conf datei

# TODO show vdr logs : journalctl -xeu vdr.service

# TODO create new channels.conf
# systemctl stop vdr
# w_scan -fs -s S19E2 > raw.conf

#------------------------------------------------------------------------------------------------------------------------------------------------
#
# notice



