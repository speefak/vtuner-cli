#!/bin/bash
# name          : vtuner-cli
# desciption    : manage vtuner and satip connections
# autor         : speefak ( itoss@gmx.de )
# licence       : (CC) BY-NC-SA
# version       : 1.0
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

 CheckMark=$'\033[0;32m✔\033[0m'   # Grün ✔
 CrossMark=$'\033[0;31m✖\033[0m'   # Rot ✖

#------------------------------------------------------------------------------------------------------------------------------------------------
############################################################################################################
###########################################   define functions   ###########################################
############################################################################################################
#------------------------------------------------------------------------------------------------------------------------------------------------
show_status() {
    vtunerdevs=( /dev/vtunerc* )
    processes=$(pgrep -af "$SATIP_BIN")
    processcount=$(grep -c . <<< "$processes")
    maps=$(echo "$processes" | grep -oP '/dev/vtunerc\d+.*?-f \d+' | grep -c .)

    if [[ -e "${vtunerdevs[0]}" ]]; then
        vtunercount=${#vtunerdevs[@]}
        echo ""
        echo "📡 Aktive vtunerc-Geräte: $vtunercount"
        printf '%s ' "${vtunerdevs[@]}"
        echo ""
    else
        vtunercount=0
        echo ""
        echo "📡 Aktive vtunerc-Geräte: 0"
        echo "  Keine vtunerc-Geräte gefunden."
    fi

    echo ""
    echo "🛰️  Laufende SAT>IP-Verbindungen: $processcount"
    if [[ -z "$processes" ]]; then
        echo "  Keine satip-Prozesse aktiv."
    else
        echo "$processes"
    fi

    echo ""
    echo "📋 Aktuelle Zuordnung (vtuner → frontend): $maps"
    if [[ -z "$processes" ]]; then
        echo "  Keine aktive Zuordnung vorhanden."
    else
        echo "$processes" | while read -r _pid cmdline; do
            dev=$(echo "$cmdline" | grep -oP '/dev/vtunerc\d+')
            frontend=$(echo "$cmdline" | grep -oP '(?<=-f )\d+')
            if [[ -n "$dev" && -n "$frontend" ]]; then
                echo "  ${dev##*/} → frontend $frontend"
            fi
        done
    fi
    echo ""
}
#------------------------------------------------------------------------------------------------------------------------------------------------
stop_satip_processes() {
    echo "🛑 Beende alle SAT>IP-Verbindungen..."
    pkill -f "$SATIP_BIN"
}
#------------------------------------------------------------------------------------------------------------------------------------------------
unload_driver() {
    stop_satip_processes
    echo "📤 Entlade vtunerc-Treiber..."
    sudo rmmod -f vtunerc
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
configure_frontends() {
    local devices=$1
    echo ""
    echo "🎛️  Starte Zuordnung der vtunerc-Devices zu VDR-Frontends:"
    for ((i=0; i<devices; i++)); do
        echo ""
        printf " → /dev/vtunerc$i"
        local default_frontend=$((i+1))
        while true; do
            read -e -p " | VDR Frontend für vtuner$i (default: ${default_frontend}): " frontend
            frontend=${frontend:-$default_frontend}
            if [[ "$frontend" =~ ^[0-9]+$ ]]; then
                echo " → Starte SAT>IP-Anbindung für vtuner$i mit Frontend $frontend"
                $SATIP_BIN -s $SATIP_SERVER -p $SATIP_PORT -d /dev/vtunerc$i -D DVBS2 -f $frontend &
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
install_vtuner_and_satip() {
    echo " 🔍 Prüfe, ob vtunerc-Modul installiert ist ..."
    if modinfo vtunerc &>/dev/null; then
        echo " $CheckMark vtunerc ist bereits installiert."
    else
        echo " ⬇️  Installiere vtunerc-Modul über DKMS ..."

        set -e

        sudo apt update
        sudo apt install -y dkms git build-essential linux-headers-$(uname -r) libcap-dev psmisc

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
#        cd /usr/src/vtuner-ng-0.0.1
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
show_loaded_menu() {
    while true; do
        if is_driver_loaded; then
            echo ""
            echo "+---------------------------------------------+"
            echo "| $CheckMark  Das Modul vtunerc ist geladen.           |"
            echo "+---------------------------------------------+"
            echo "|1) Entladen                                  |"
            echo "|2) Neu laden (Entladen + neue devices)       |"
            echo "|3) SAT>IP-Verbindungen beenden               |"
            echo "|4) Alle vtuner/SAT>IP anzeigen               |"
            echo "|5) vtuner/satip installieren oder prüfenv    |"
            echo "|6) Abbrechen                                 |"
            echo "+---------------------------------------------+"
            read -p "=> " choice
            echo ""

            case "$choice" in
                1)
                    unload_driver
                    show_status
                    return
                    ;;
                2)
                    unload_driver
                    load_driver
                    devices=$(count_loaded_devices)
                    configure_frontends "$devices"
                    show_status
                    return
                    ;;
                3)
                    stop_satip_processes
                    show_status
                    ;;
                4)
                    show_status
                    ;;
                5)
                    install_vtuner_and_satip
                    ;;
                6)
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
            echo "| 1) Laden                                    |"
            echo "| 2) vtuner/satip installieren oder prüfen    |"
            echo "| 3) Abbrechen                                |"
            echo "+---------------------------------------------+"
            read -p "=> " choice
            echo ""
            case "$choice" in
                1)
                    load_driver
                    devices=$(count_loaded_devices)
                    configure_frontends "$devices"
                    show_status
                    return
                    ;;
                2)
                    install_vtuner_and_satip
                    ;;
                3)
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
	show_status
	show_loaded_menu

#------------------------------------------------------------------------------------------------------------------------------------------------

exit 0

#------------------------------------------------------------------------------------------------------------------------------------------------
#
# notice

# TODO create function: save conf datei
# save config in /root/.vtuner-cli.conf (conf datei)
# config dialog for global variables | satip server ip =< save config in conf datei
# save vtuner count in conf datei
# save vtuner - frontend zuornung in conf datei

# TODO create function: load conf datei

# TODO create systemctl load file

# TODO prüfe doppelte vtuner => frontend zuornung

