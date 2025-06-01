#!/bin/bash
# name          : vtuner-cli
# desciption    : manage vtuner and satip connections
# autor         : speefak ( itoss@gmx.de )
# licence       : (CC) BY-NC-SA
# version       : 1.4
# notice        :
# infosource    : ChatGPT
#
#------------------------------------------------------------------------------------------------------------------------------------------------
############################################################################################################
#######################################   define global variables   ########################################
############################################################################################################
#------------------------------------------------------------------------------------------------------------------------------------------------

 SATIP_BIN="/usr/local/bin/satip"
 SATIP_SERVER="192.168.1.9"
 SATIP_PORT="554"
 
 RequiredPackets="dkms git build-essential linux-headers-$(uname -r) libcap-dev psmisc w-scan"

 CheckMark=$'\033[0;32m✔\033[0m'   # Grün ✔
 CrossMark=$'\033[0;31m✖\033[0m'   # Rot ✖

#------------------------------------------------------------------------------------------------------------------------------------------------
############################################################################################################
###########################################   define functions   ###########################################
############################################################################################################
#------------------------------------------------------------------------------------------------------------------------------------------------
show_status () {
    vTunerModules=$(ls /dev/vtunerc* 2>/dev/null | tr " " "\n")
    SatIPProcesses=$(pgrep -fa "$SATIP_BIN" | grep -v "/bin/bash -c  $SATIP_BIN")

    echo ""
    echo "+------------------------------------------------------------------------------------------+"
    echo "| Aktive vtuner 📡 und SAT>IP-Verbindungen 🛰️                                               |"
    echo "+-------------+-----------------+----------------------------------------------------------+"
    if is_driver_loaded; then
        for vtunerPath in $vTunerModules; do
            vtuner=$(basename "$vtunerPath")             # z.B. vtunerc0
            stuner=$(echo "$SatIPProcesses" | grep $vtunerPath | awk -F " -f" '{print $2}' )
            process=$(pgrep -fa "$SATIP_BIN" | grep -v "/bin/bash -c  $SATIP_BIN" | grep "$vtunerPath" <<< $SatIPProcesses)

            if [ -n "$process" ]; then
                echo "| 📡 $vtuner | 🛰️  xIP tuner$stuner  | $(echo "$process" | awk -F "$SATIP_BIN -s " '{print $2}' ) $CheckMark |"
            else
                echo "| 📡 $vtuner | 🛑  no tuner    |                                                        $CrossMark |"
            fi
        done
    else
        echo "| 📡 Keine vtunerc-Geräte gefunden.                                                     $CrossMark |"
   fi
   echo "+-------------+-----------------+----------------------------------------------------------+"
}
#------------------------------------------------------------------------------------------------------------------------------------------------
stop_satip_processes() {
    echo "🛑 Beende alle SAT>IP-Verbindungen..."
    pkill -f "$SATIP_BIN"
}
#------------------------------------------------------------------------------------------------------------------------------------------------
load_driver() {
    local devices
    while true; do
        read -p "Wie viele Devices sollen geladen werden? " devices
        if [[ "$devices" =~ ^[1-9][0-9]*$ ]]; then
            break
        else
            echo "Bitte eine gültige Zahl eingeben."
        fi
    done
    echo "📥 Lade vtunerc mit $devices Devices..."
    sudo modprobe vtunerc devices=$devices
}
#------------------------------------------------------------------------------------------------------------------------------------------------
unload_driver() {
    stop_satip_processes
    echo "📤 Entlade vtunerc-Module ..."
    sudo rmmod -f vtunerc
}
#------------------------------------------------------------------------------------------------------------------------------------------------
configure_frontends() {
    local devices=$1
    echo ""
    echo "🎛️  Starte Zuordnung der vtunerc-Devices zu SatIP Tunern:"
    for ((i=0; i<devices; i++)); do
        echo ""
        printf " → /dev/vtunerc$i"
        local default_frontend=$((i+1))
        while true; do
            read -e -p " | SatIP Tuner für vtuner$i (default: ${default_frontend}): " frontend
            frontend=${frontend:-$default_frontend}
            if [[ "$frontend" =~ ^[0-9]+$ ]]; then
                echo " → Starte SAT>IP-Anbindung für vtuner$i SatIP Tuner $frontend"
                $SATIP_BIN -s $SATIP_SERVER -p $SATIP_PORT -d /dev/vtunerc$i -D DVBS,DVBS2 -f $frontend &
                break
            else
                echo "  $CrossMark Ungültige Eingabe. Bitte eine Zahl für das VDR-Frontend eingeben."
            fi
        done
    done
    echo ""
    echo " $CheckMark Alle Zuordnungen abgeschlossen."
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
    echo " VDR Neustart ..."
    sudo systemctl restart vdr
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

        echo " $CheckMark vtunerc erfolgreich installiert."
    fi

    echo ""
    echo " 🔍 Prüfe, ob satip-Tool verfügbar ist ..."
    if command -v satip &>/dev/null; then
        echo " $CheckMark satip ist bereits installiert."
    else
        echo " ⬇️  Baue und installiere satip ..."
        cd /tmp/vtuner-ng/satip || { echo "$CrossMark satip-Verzeichnis nicht gefunden!"; return 1; }
        make
        sudo make install
        echo " $CheckMark satip erfolgreich installiert."
    fi

    echo ""
    echo " 📦 Installation abgeschlossen."
}
#------------------------------------------------------------------------------------------------------------------------------------------------
create_systemd_service() {
    local service_file="/etc/systemd/system/vtuner-satip.service"
    local vtunerdevs=( /dev/vtunerc* )
    local pids=$(pgrep -fa "$SATIP_BIN" | grep -v "/bin/bash -c  $SATIP_BIN" | cut -d " " -f1)

    if [[ ! -e "${vtunerdevs[0]}" || -z "$pids" ]]; then
        echo "$CrossMark Keine aktiven vtuner- oder satip-Prozesse gefunden. Abbruch."
        return 1
    fi

    echo "📄 Erstelle systemd-Service: $service_file"

    # Header
    sudo tee "$service_file" > /dev/null <<EOF
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
            [[ "$cmdline" == *"$SATIP_BIN"* ]] || continue
            # -D XX YY in -D XX,YY umwandeln
            cmdline=$(sed -E 's/-D ([A-Z0-9]+) ([A-Z0-9]+)/-D \1,\2/' <<< "$cmdline")
            sudo tee -a "$service_file" > /dev/null <<< "$cmdline & \\"
        fi
    done

    # VDR restart nach allen satip-Prozessen
    sudo tee -a "$service_file" > /dev/null <<< "/bin/systemctl restart vdr; \\"

    # Abschlusszeile
    sudo tee -a "$service_file" > /dev/null <<EOF
wait'
#ExecStop=/usr/bin/pkill -f $SATIP_BIN			# causes systemfreeze when shutdown system
#ExecStopPost=/sbin/rmmod -f vtunerc			# causes systemfreeze when shutdown system

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now vtuner-satip.service
    systemctl enable vtuner-satip.service
    echo "$CheckMark systemd-Service wurde korrekt erstellt und aktiviert."
}
#------------------------------------------------------------------------------------------------------------------------------------------------
delete_systemd_service() {
    local service_file="/etc/systemd/system/vtuner-satip.service"

    echo "🗑️  Lösche systemd-Service vtuner-satip ..."

    if [[ -f "$service_file" ]]; then
        sudo systemctl stop vtuner-satip.service
        sudo systemctl disable vtuner-satip.service
        sudo rm -f "$service_file"
        sudo systemctl daemon-reload
        echo "$CheckMark systemd-Service erfolgreich entfernt."
    else
        echo "$CrossMark Kein vtuner-satip Service gefunden unter $service_file"
    fi
}
#------------------------------------------------------------------------------------------------------------------------------------------------
show_systemd_service() {
    local service_file="/etc/systemd/system/vtuner-satip.service"

    echo ""
    echo ""
    echo "systemd service file ($service_file)":
    cat $service_file
    echo ""

}
#------------------------------------------------------------------------------------------------------------------------------------------------
satip_connection_menu() {

    show_status

    echo ""
    echo "+------------------------------------------------------------------------------------------+"
    echo "| 📡 SAT>IP-Verbindungen                                                                   |"
    echo "+------------------------------------------------------------------------------------------+"
    echo "| 1) Neue Verbindung herstellen                                                            |"
    echo "| 2) Verbindung beenden                      3) Zurück                                     |"
    echo "+------------------------------------------------------------------------------------------+"
    read -p "=> " satip_choice

    case "$satip_choice" in
        1)
            # Nur freie vtunerc-Geräte anzeigen
            local used=()
            while IFS= read -r line; do
                [[ "$line" =~ (/dev/vtunerc[0-9]+) ]] && used+=("${BASH_REMATCH[1]}")
            done < <(pgrep -fa "$SATIP_BIN")

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
                            $SATIP_BIN -s $SATIP_SERVER -p $SATIP_PORT -d "$dev" -D DVBS,DVBS2 -f $frontend &
                            break
                        else
                            echo "  $CrossMark Ungültige Eingabe. Bitte eine Zahl eingeben."
                        fi
                    done
                fi
            done

            echo ""
            echo " $CheckMark Neue Verbindungen wurden hergestellt."
            ;;

        2)
            # Nur aktive Prozesse zur Auswahl anbieten
            echo ""
            echo "🔌 Aktive Verbindungen:"
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
            done < <(pgrep -fa "$SATIP_BIN")

            if [ ${#pids[@]} -eq 0 ]; then
                echo "$CrossMark Keine aktiven Verbindungen gefunden."
                return
            fi

            echo ""
            read -p "Welche Verbindung soll beendet werden? (Nummer): " selection
            if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ${#pids[@]} )); then
                local kill_pid=${pids[$((selection-1))]}
                kill "$kill_pid"
                echo "$CheckMark Verbindung ${entries[$((selection-1))]} wurde beendet."
            else
                echo "$CrossMark Ungültige Auswahl."
            fi
            ;;
        3)
            echo "↩️  Zurück"
            return
            ;;
        *)
            echo "Ungültige Auswahl."
            ;;
    esac
}
#------------------------------------------------------------------------------------------------------------------------------------------------
manage_systemd_service() {

    show_status

    local service_file="/etc/systemd/system/vtuner-satip.service"

    echo ""
    echo "+------------------------------------------------------+"
    echo "| 🛠️  systemd-Service Optionen                                    |"
    echo "+------------------------------------------------------+"
    echo "| 1) Service erstellen                                 |"
    echo "| 2) Service anzeigen                                  |"
    echo "| 3) Service löschen                                   |"
    echo "| 4) Zurück                                            |"
    echo "+------------------------------------------------------+"
    read -p "=> " subchoice
    echo ""

    case "$subchoice" in
        1)
            create_systemd_service
            ;;
        2)
            show_systemd_service
            ;;
        3)
            delete_systemd_service
            ;;
        4)
            return
            ;;
        *)
            echo "Ungültige Auswahl."
            ;;
    esac
}
#------------------------------------------------------------------------------------------------------------------------------------------------
show_loaded_menu() {
    while true; do
        if is_driver_loaded; then

            show_status

            echo ""
            echo "+------------------------------------------------------------------------------------------+"
            echo "| 1) vtuner Module entladen                  5) systemd-Service (show, create, delete)     |"
            echo "| 2) Neu laden (Entladen + neue Devices)     6) vtuner/satip installieren oder prüfen      |"
            echo "| 3) SAT>IP-Verbindungen verwalten                                                         |"
            echo "| 4) VDR neu starten                         7) Abbrechen                                  |"
            echo "+------------------------------------------------------------------------------------------+"
            read -p "=> " choice
            echo ""

            case "$choice" in
                1)
                    unload_driver
                    return
                    ;;
                2)
                    unload_driver
                    load_driver
                    devices=$(count_loaded_devices)
                    configure_frontends "$devices"
                    show_status
                    restart_vdr
                    echo ""
                    read -p "🛠️  Soll ein systemd-Service für vtuner-satip erstellt werden? (j/N): " create_service
                    if [[ "$create_service" =~ ^[JjYy]$ ]]; then
                        create_systemd_service
                    else
                        echo "↩️  Kein systemd-Service erstellt."
                    fi
                    return
                    ;;
                3)
                    satip_connection_menu
                    ;;
                4)
                    restart_vdr
                    ;;
                5)
                    manage_systemd_service
                    ;;
                6)
                    install_vtuner_and_satip
                    ;;
                7)
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
            echo "| 3) VDR neu starten                          |"
            echo "| 4) Abbrechen                                |"
            echo "+---------------------------------------------+"
            read -p "=> " choice
            echo ""
            case "$choice" in
                1)
                    load_driver
                    devices=$(count_loaded_devices)
                    configure_frontends "$devices"
#                    show_status
                    restart_vdr
                    echo ""
                    read -p "🛠️  Soll ein systemd-Service für vtuner-satip erstellt werden? (j/N): " create_service
                    if [[ "$create_service" =~ ^[JjYy]$ ]]; then
                        create_systemd_service
                    else
                        echo "↩️  Kein systemd-Service erstellt."
                    fi
                    return
                    ;;
                2)
                    install_vtuner_and_satip
                    ;;
                3)
                    restart_vdr
                    ;;
                4)
                    return
                    ;;
                *)
                    echo "Ungültige Auswahl."
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
#	show_status
	show_loaded_menu

#------------------------------------------------------------------------------------------------------------------------------------------------

exit 0

#------------------------------------------------------------------------------------------------------------------------------------------------

# TODO vtuner Module (load, unload) auswahl opunkt um menu erweitern wie für sat ip verbidungen

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



