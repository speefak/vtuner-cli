#!/bin/bash
# name          : vtuner-cli
# desciption    : manage vtuner and satip connections
# autor         : speefak ( itoss@gmx.de )
# licence       : (CC) BY-NC-SA
# version 	: 0.9
# notice 	:
# infosource	: ChatGPT
#
#------------------------------------------------------------------------------------------------------------------------------------------------
############################################################################################################
#######################################   define global variables   ########################################
############################################################################################################
#------------------------------------------------------------------------------------------------------------------------------------------------#!/bin/bash

SATIP_BIN="/usr/local/bin/satip"
SATIP_SERVER="192.168.1.9"
SATIP_PORT="554"

#------------------------------------------------------------------------------------------------------------------------------------------------
############################################################################################################
###########################################   define functions   ###########################################
############################################################################################################
#------------------------------------------------------------------------------------------------------------------------------------------------
show_status() {
    # vtuner-Geräte zählen und anzeigen

    vtunerdevs=( /dev/vtunerc* )
    processes=$(pgrep -af "$SATIP_BIN")
    processcount=$(wc -l <<< $processes)
    # echo-Zeile für mapcount nach while nicht möglich (Subshell!) → separat zählen
    maps=$(echo "$processes" | grep -oP '/dev/vtunerc\d+.*?-f \d+' | wc -l)

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

    # Laufende SAT>IP-Prozesse anzeigen und zählen
    echo ""
    echo -en "🛰️  Laufende SAT>IP-Verbindungen: $processcount \n"
    if [[ -z "$processes" ]]; then
        echo "0"
        echo "  Keine satip-Prozesse aktiv."
    else
        satipcount=$(wc -l <<< "$processes")
        echo -n "$satipcount"
        echo "$processes"
    fi

    # Zuordnungen zählen
    echo ""
    echo -en "📋 Aktuelle Zuordnung (vtuner → frontend): $maps\n"
    if [[ -z "$processes" ]]; then
        echo "0"
        echo "  Keine aktive Zuordnung vorhanden."
    else
        mapcount=0
        echo "$processes" | while read -r _pid cmdline; do
            dev=$(echo "$cmdline" | grep -oP '/dev/vtunerc\d+')
            frontend=$(echo "$cmdline" | grep -oP '(?<=-f )\d+')
            if [[ -n "$dev" && -n "$frontend" ]]; then
                echo "  ${dev##*/} → frontend $frontend"
                ((mapcount++))
            fi
        done

    fi
    echo ""
}
#------------------------------------------------------------------------------------------------------------------------------------------------
stop_satip_processes() {
    echo "Beende alle SAT>IP-Verbindungen..."
    pkill -f "$SATIP_BIN"
}
#------------------------------------------------------------------------------------------------------------------------------------------------
unload_driver() {
    echo "🛑 Beende alle SAT>IP-Verbindungen..."
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
    echo "Lade vtunerc mit $devices Devices..."
    sudo modprobe vtunerc devices=$devices
}
#------------------------------------------------------------------------------------------------------------------------------------------------
configure_frontends() {
    local devices=$1
    echo ""
    echo "🎛️  Starte Zuordnung der vtunerc-Devices zu VDR-Frontends:"
    for ((i=0; i<devices; i++)); do
        echo ""
        echo "→ /dev/vtunerc$i"

        local default_frontend=$((i+1))
        while true; do
            read -e -p "  Welchem VDR-Frontend soll vtuner$i zugeordnet werden? (-f Nummer) [${default_frontend}]: " frontend
            frontend=${frontend:-$default_frontend}
            if [[ "$frontend" =~ ^[0-9]+$ ]]; then
                echo "  → Starte SAT>IP-Anbindung für vtuner$i mit Frontend $frontend"
                $SATIP_BIN -s $SATIP_SERVER -p $SATIP_PORT -d /dev/vtunerc$i -D DVBS2 -f $frontend &
                break
            else
                echo "  ❌ Ungültige Eingabe. Bitte eine Zahl für das VDR-Frontend eingeben."
            fi
        done
    done
    echo ""
    echo "✅ Alle Zuordnungen abgeschlossen."
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
show_loaded_menu() {
    while true; do
        if is_driver_loaded; then
            echo ""
            echo "⚙️  Der Treiber vtunerc ist geladen."
            echo "1) Entladen"
            echo "2) Neu laden (Entladen + neue devices)"
            echo "3) SAT>IP-Verbindungen beenden"
            echo "4) Alle vtuner/SAT>IP anzeigen"
            echo "5) Abbrechen"
            read -p "#? " choice
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
                    return
                    ;;
                3)
                    stop_satip_processes
                    ;;
                4)
                    show_status
                    ;;
                5)
                    return
                    ;;
                *)
                    echo "Ungültige Auswahl."
                    ;;
            esac
        else
            echo ""
            echo "⚙️  Der Treiber vtunerc ist nicht geladen."
            echo "1) Laden"
            echo "2) Abbrechen"
            read -p "#? " choice
            case "$choice" in
                1)
                    load_driver
                    devices=$(count_loaded_devices)
                    configure_frontends "$devices"
                    show_status
                    return
                    ;;
                2)
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

	# show script information
	if [[ $1 == "-si" ]]; then
		script_information
	fi

#------------------------------------------------------------------------------------------------------------------------------------------------

	# check for root permission
	if [ "$(whoami)" = "root" ]; then echo "";else echo "Are you root ?";exit 1;fi

#------------------------------------------------------------------------------------------------------------------------------------------------

	# Main Script
	show_status
	show_loaded_menu

#------------------------------------------------------------------------------------------------------------------------------------------------

exit 0

#------------------------------------------------------------------------------------------------------------------------------------------------
#
# notice


# TODO
# install function:
install_vtuner_and_satip () {
# load, build, compile and install vtuner modules
sudo apt update
sudo apt install git build-essential linux-headers-$(uname -r) libcap-dev
cd /tmp
git clone https://github.com/joed74/vtuner-ng.git
cd vtuner-ng
sudo mkdir -p /usr/src/vtuner-ng-0.0.1
sudo cp -r . /usr/src/vtuner-ng-0.0.1
sudo dkms add -m vtuner-ng -v 0.0.1
sudo dkms build -m vtuner-ng -v 0.0.1
sudo dkms install -m vtuner-ng -v 0.0.1

# build and install satip tool
cd satip
make
make install
}
