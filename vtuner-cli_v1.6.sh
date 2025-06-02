#!/bin/bash
# name          : vtuner-cli
# desciption    : manage vtuner and satip connections
# autor         : speefak ( itoss@gmx.de )
# licence       : (CC) BY-NC-SA
# version       : 1.6
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
load_vtuner_modules() {
    unload_vtuner_modules
    echo ""

    local devices
    devices=$(ls /dev/vtunerc* 2>/dev/null | wc -l)

    while true; do
        read -p " Wie viele virtuelle Tuner möchten Sie laden? " devices
        if [[ "$devices" =~ ^[1-9][0-9]*$ ]]; then
            break
        else
            echo " Bitte eine gültige Zahl eingeben."
        fi
    done

    printf "\r 📥 Lade vtunerc Modul mit $devices Devices..."
    sudo modprobe vtunerc devices=$devices && printf "\r 📥 Lade vtunerc mit $devices Devices $CheckMark     " || printf "\r 📥 Lade vtunerc mit $devices Devices $CrossMark     "
    echo ""

    while true; do
        read -e -p " 🛠️  SAT>IP-Verbindungen initialisieren? (j/N): " -i "j" choice
        if [[ "$choice" =~ ^[JjYy]$ ]]; then
            manage_satip_connections 1
            break
        elif [[ "$choice" =~ ^[Nn]$ ]]; then
            printf "\r ⚠️  SAT>IP-Verbindungen nicht initialisiert.\n"
            return 1
        else
            echo " ❌ Ungültige Eingabe. Bitte 'j' oder 'n' eingeben."
        fi
    done

    create_systemd_service
}
#------------------------------------------------------------------------------------------------------------------------------------------------
unload_vtuner_modules() {
    if ! lsmod | grep -q "^vtunerc"; then
        printf " vtunerc-Modul ist nicht geladen. $CheckMark\n"
        return
    fi

    if pgrep -f "$SatipBIN" > /dev/null; then
        if pkill -f "$SatipBIN"; then
            printf "\r Beende alle SAT>IP-Verbindungen $CheckMark %s\n"
        else
            printf "\r Beende alle SAT>IP-Verbindungen $CrossMark %s\n”"
        fi
    else
        printf "\r Keine aktiven SAT>IP-Verbindungen gefunden. $CheckMark\n"
    fi
    
    printf " 📤 Entlade vtunerc-Module ... "
    if sudo rmmod -f vtunerc ; then
        printf "\r Entlade vtunerc-Module $CheckMark     \n"
    else
        printf "\r Entlade vtunerc-Module $CrossMark     \n"
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
            unload_vtuner_modules
            ;;
        2)
            load_vtuner_modules
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
show_status () {
    vTunerModules=$(ls /dev/vtunerc* 2>/dev/null | tr " " "\n")
    SatIPProcesses=$(pgrep -fa "$SatipBIN" | grep -v "/bin/bash -c  $SatipBIN")
    vTunerUsed=
    vTunerUnUsed=
    
    echo ""
    echo "+------------------------------------------------------------------------------------------+"
    echo "| Aktive vtuner 📡 und SAT>IP-Verbindungen 🛰️                                               |"
    echo "+-------------+------------------+---------------------------------------------------------+"
    if is_driver_loaded; then
        for vtunerPath in $vTunerModules; do
            vtuner=$(basename "$vtunerPath")             # z.B. vtunerc0
            stuner=$(echo "$SatIPProcesses" | grep $vtunerPath | awk -F " -f" '{print $2}' )
            process=$(pgrep -fa "$SatipBIN" | grep -v "/bin/bash -c  $SatipBIN" | grep "$vtunerPath" <<< $SatIPProcesses)
            if [ -n "$process" ]; then
                echo "| 📡 $vtuner | 🛰️  SatIP tuner$stuner | $(echo "$process" | awk -F "$SatipBIN -s " '{print $2}' )  |"
                vTunerUsed+="$vtuner "
            else
                echo "| 📡 $vtuner | 🛑 no connection |                                                         |"
                vTunerUnUsed+="$vtuner "
            fi
        done
    else
        echo "| 📡 Keine vtunerc-Geräte gefunden. $CrossMark                                                      |"
   fi
   echo "+-------------+------------------+---------------------------------------------------------+"
}
#------------------------------------------------------------------------------------------------------------------------------------------------
manage_satip_connections() {
    # show status and load vars $vTunerUsed $vTunerUnUsed
    show_status

    local auto_choice="$1"  # Optionaler Parameter
    if [[ "$auto_choice" =~ ^[12xX]$ ]]; then
        satip_choice="$auto_choice"
    else
        echo ""
        echo "+------------------------------------------------------------------------------------------+"
        echo "| 📡 SAT>IP-Verbindungen                                                                   |"
        echo "+------------------------------------------------------------------------------------------+"
        echo "| 1) Neue Verbindung herstellen                                                            |"
        echo "| 2) Verbindung beenden                      x) Zurück                                     |"
        echo "+------------------------------------------------------------------------------------------+"
        read -p "=> " satip_choice
    fi

    case "$satip_choice" in
        1)
            for vTunerDevice in $vTunerUnUsed; do 
                vTunerNumber=$(sed 's/vtunerc//' <<<$vTunerDevice )
                vTunerDevicePath="/dev/vtunerc$vTunerNumber"
                SatIPServerDeviceNumber=$(($vTunerNumber+1))
                    while true; do
                        read -e -p " → vtuner $vTunerNumber | SatIP Server ($SatipServer) | Tuner (default: $SatIPServerDeviceNumber): " SatIPServerDevice
                        SatIPServerDevice=${SatIPServerDevice:-$SatIPServerDeviceNumber}
                        if [[ "$SatIPServerDevice" =~ ^[0-9]+$ ]]; then
                            printf "\r → Starte SAT>IP-Anbindung: /dev/vtuner $vTunerNumber ➤ $SatipServer ➤ Tuner $SatIPServerDevice\n"
                            $SatipBIN -s $SatipServer -p $SatipPORT -d "$vTunerDevicePath" -D DVBS,DVBS2 -f $SatIPServerDevice &
                            NewSatIPConnection=true
                            break
                        else
                            echo " Ungültige Eingabe. Bitte eine Zahl eingeben. $CrossMark"
                        fi
                    done
            done

            if [[ $NewSatIPConnection == true ]]; then
                echo ""
                echo " Neue Verbindungen wurden hergestellt. $CheckMark"
            else
                echo ""
                echo " Kein freier vtuner vorhanden. $CrossMark"
            fi
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
        echo " Keine aktiven satip-Verbindungen gefunden. $CrossMark "
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
ExecStop=/usr/bin/pkill -f $SatipBIN
ExecStopPost=/sbin/rmmod -f vtunerc

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable vtuner-satip.service
    echo " systemd-Service wurde erstellt und aktiviert. $CheckMark"
}
#------------------------------------------------------------------------------------------------------------------------------------------------
delete_systemd_service() {
    printf " 🗑️  Lösche vtuner systemd-service ..."

    if [[ -f "$SystemdServiceFile" ]]; then
        sudo systemctl stop vtuner-satip.service
        sudo systemctl disable vtuner-satip.service
        sudo rm -f "$SystemdServiceFile"
        sudo systemctl daemon-reload
        printf "\r Lösche vtuner systemd-service $CheckMark      \n"
        echo ""
    else
        printf "\r Lösche vtuner systemd-service $CrossMark (Datei nicht gefunden $SystemdServiceFile) \n"
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
#    echo ""
#    echo "+------------------------------------------------------------------------------------------+"
#    echo "+                                                                                          +"
#    echo "+------------------------------------------------------------------------------------------+"
#    echo ""
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
is_driver_loaded() {
    lsmod | grep -q "^vtunerc"
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
            echo "| 3) systemd-Service verwalten                |"
            echo "| 4) VDR neu starten                          |"
            echo "| x) Zurück                                   |"
            echo "+---------------------------------------------+"
            read -p "=> " choice
            echo ""
            case "$choice" in
                1)
                    load_vtuner_modules -s
                    ;;
                2)
                    install_vtuner_and_satip
                    ;;
                3)
                    manage_systemd_service
                    ;;
                4)
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





