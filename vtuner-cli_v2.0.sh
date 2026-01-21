#!/bin/bash
# name          : vtuner-cli
# desciption    : manage vtuner and satip connections
# autor         : speefak ( itoss@gmx.de )
# licence       : (CC) BY-NC-SA
# version       : 2.0
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
        prompt_cursor true
        read -e -p " Anzahl der zu ladenen vTuner: " -i "2" devices
        prompt_cursor false
        if [[ "$devices" =~ ^[1-9][0-9]*$ ]]; then
            break
        else
            echo " Bitte eine gültige Zahl eingeben."
        fi
    done
    echo -ne "\033[1A\r\033[K"

    printf "\r 📥 Lade vtuner Modul mit $devices Devices ..."
    if sudo modprobe vtunerc devices=$devices; then
        printf "\r 📥 Lade vtunerc mit $devices Devices $CheckMark       \n"
    else
        printf "\r 📥 Lade vtunerc mit $devices Devices $CrossMark       \n"
        exit 1
    fi

    while true; do
        prompt_cursor true
        read -e -p " 🛠️  SAT>IP-Verbindungen initialisieren? (j/N): " -i "j" choice
        echo -ne "\033[1A\r\033[K"
        prompt_cursor false
        if [[ "$choice" =~ ^[JjYy]$ ]]; then
            manage_satip_connections 1
            break
        elif [[ "$choice" =~ ^[Nn]$ || -z $choice ]]; then
            printf "\r ⚠️  SAT>IP-Verbindungen nicht initialisiert.\n"
            return 1
        else
            echo " ❌ Ungültige Eingabe. Bitte 'j' oder 'n' eingeben."
        fi
    done

    while true; do
        prompt_cursor true
        read -e -p " 🛠️  Soll ein systemd-Service für vtuner-satip erstellt werden? (j/N): " -i "j" choice
        echo -ne "\033[1A\r\033[K"
        prompt_cursor false
        if [[ "$choice" =~ ^[JjYy]$ ]]; then
            create_systemd_service
            break
        elif [[ "$choice" =~ ^[Nn]$ || -z $choice ]]; then
            printf "\r ⚠️  Kein systemd-Service erstellt.\n"
            return 1
        else
            echo " ❌ Ungültige Eingabe. Bitte 'j' oder 'n' eingeben."
        fi
    done
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
    echo "| 📡 vtuner Module verwalten                                                               |"
    echo "+------------------------------------------------------------------------------------------+"
    echo "| 1) vtuner Module entladen                  x) Zurück                                     |"
    echo "| 2) vtuner Module neu erstellen                                                           |"
    echo "+------------------------------------------------------------------------------------------+"
    read -s -n 1 choice
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
    show_status
    local auto_choice="$1" 
    if [[ "$auto_choice" =~ ^[12xX]$ ]]; then
        satip_choice="$auto_choice"
    else
        echo ""
        echo "+------------------------------------------------------------------------------------------+"
        echo "| 📡 SAT>IP-Verbindungen verwalten                                                         |"
        echo "+------------------------------------------------------------------------------------------+"
        echo "| 1) Neue Verbindung herstellen              x) Zurück                                     |"
        echo "| 2) Verbindung trennen                                                                    |"
        echo "+------------------------------------------------------------------------------------------+"
        read -s -n 1 satip_choice
    fi


    case "$satip_choice" in
        1)
            if [[ -z $vTunerUnUsed ]]; then
                echo " Kein freier vtuner vorhanden $CrossMark"
            fi

            for vTunerDevice in $vTunerUnUsed; do 
                vTunerNumber=$(sed 's/vtunerc//' <<<$vTunerDevice )
                vTunerDevicePath="/dev/vtunerc$vTunerNumber"
                SatIPServerTunerNumber=$(($vTunerNumber+1))

                while true; do
                    prompt_cursor true
                    read -e -p " → vtuner $vTunerNumber | SatIP Server ($SatipServer) | Tuner (default: $SatIPServerTunerNumber): " SatIPServerDevice
                    prompt_cursor false
                    echo -ne "\033[1A\r\033[K"
                    SatIPServerDevice=${SatIPServerDevice:-$SatIPServerTunerNumber}
                    if [[ "$SatIPServerDevice" =~ ^[0-9]+$ ]]; then
                        printf "\r → Starte SAT>IP-Anbindung: /dev/vtuner $vTunerNumber ➤ $SatipServer ➤ Tuner $SatIPServerDevice"
                        $SatipBIN -s $SatipServer -p $SatipPORT -d "$vTunerDevicePath" -D DVBS,DVBS2 -f $SatIPServerDevice &
                        sleep 0.3  
                        if pgrep -fa "$SatipBIN" | grep -q "$vTunerDevicePath"; then
                            printf " $CheckMark\n"
                        else
                            printf " $CrossMark\n"
                        fi
                        break
                    else
                        echo " Ungültige Eingabe. Bitte eine Zahl eingeben. $CrossMark"
                    fi
                done
            done
            ;;
        2)
            # In Array umwandeln und Duplikate entfernen
            local unique_used=($(echo "$vTunerUsed" | tr ' ' '\n' | sort -u))

            if [ ${#unique_used[@]} -eq 0 ]; then
                echo " Keine aktiven SAT>IP Verbindungen gefunden. $CrossMark"
                return 1
            fi

            local i=1
            declare -A index_to_vtuner
            declare -A vtuner_lines

            # Extrahiere nur vtuner-Zeilen aus show_status-Ausgabe
            mapfile -t vtuner_output < <(show_status | grep "/dev/vtunerc" )

            for vtuner in "${unique_used[@]}"; do
                # Finde passende Zeile aus der Ausgabe
                line=$(printf '%s\n' "${vtuner_output[@]}" | grep -m1 "$vtuner" | sed 's/^| //; s/|$//')
                if [ -n "$line" ]; then
                    echo " $i) $line"
                    index_to_vtuner[$i]=$vtuner
                    vtuner_lines[$i]="$line"
                    ((i++))
                fi
            done
            echo ""

            prompt_cursor true
            read -p "   Trenne SAT>IP Verbindungen: (1 3 5 |a|x): " selection
            prompt_cursor false

            if [[ "$selection" == "x" ]]; then
                echo " ↩️  Zurück"
                return
            fi

            selected_vtuners=()
            if [[ "$selection" == "a" ]]; then
                selected_vtuners=("${unique_used[@]}")
            else
                for num in $selection; do
                    if [[ "$num" =~ ^[0-9]+$ ]] && [[ -n "${index_to_vtuner[$num]}" ]]; then
                        selected_vtuners+=("${index_to_vtuner[$num]}")
                    fi
                done
            fi
            
            if [ ${#selected_vtuners[@]} -eq 0 ]; then
                echo -ne "\033[1A\r\033[K"
                printf "\r ❌ Ungültige SAT>IP-Verbindungen ausgewählt: $selection\n"
                manage_satip_connections 2
                return 1
            fi

            for tuner in "${selected_vtuners[@]}"; do
                SatIPConnectionPID=$(pgrep -fa "$SatipBIN" | grep -v "/bin/bash -c  $SatipBIN"| grep $tuner | cut -d " " -f1)
                printf " Disconnect $(grep $tuner <<< $(show_status) | sed 's/-p.*//')"
                kill $SatIPConnectionPID &>/dev/null || kill -9 $SatIPConnectionPID &>/dev/null && printf "$CheckMark\n" || printf "$CrossMark\n"
            done
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
    local SystemdServiceFile="/etc/systemd/system/vtuner-satip.service"

    # Prüfen, ob überhaupt vtunerc-Geräte existieren
    local vtunerdevs=( /dev/vtunerc* )
    if [[ ! -e "${vtunerdevs[0]}" ]]; then
        echo " ❌ Keine vtunerc-Geräte gefunden! $CrossMark"
        return 1
    fi

    local num_devices=${#vtunerdevs[@]}
    echo " 📡 Gefundene vtunerc-Geräte: $num_devices"

    printf " 📄 Erstelle/aktualisiere systemd-Service: $SystemdServiceFile ..."

    sudo tee "$SystemdServiceFile" > /dev/null <<EOF
[Unit]
Description=Start vtuner → satip Bindings
After=network.target

[Service]
Type=simple
RemainAfterExit=no
ExecStartPre=/sbin/modprobe vtunerc devices=$num_devices

ExecStart=/bin/bash -c '\\
EOF

    # Für jedes vtunerc-Gerät eine satip-Zeile erzeugen
    for dev in "${vtunerdevs[@]}"; do
        # vtunerc0 → Nummer 0 → Frontend-Nummer = Nummer + 1 (also 1,2,3,...)
        local devnum=$(echo "$dev" | grep -o '[0-9]\+$')
        local frontend=$((devnum + 1))

        sudo tee -a "$SystemdServiceFile" > /dev/null <<EOF
  $SatipBIN -s $SatipServer -p $SatipPORT -d $dev -D DVBS,DVBS2 -f $frontend & \\
EOF
    done

    # Abschluss der bash -c Zeile + wait
    sudo tee -a "$SystemdServiceFile" > /dev/null <<EOF
  wait'

ExecStartPost=/bin/systemctl restart vdr
ExecStopPost=/sbin/rmmod -f vtunerc

KillMode=control-group
KillSignal=SIGTERM
TimeoutStopSec=10
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # Systemd neu laden und Service aktivieren
    systemctl daemon-reload

    if systemctl enable vtuner-satip.service &>/dev/null; then
        printf " $CheckMark\n"
        echo "   → Service erfolgreich erstellt und aktiviert."
    else
        printf " $CrossMark\n"
        echo " Fehler beim Aktivieren des Services:"
        systemctl enable vtuner-satip.service
    fi

    echo ""
    echo " Du kannst den Service jetzt starten mit:"
    echo "   sudo systemctl start vtuner-satip.service"
    echo "   sudo systemctl status vtuner-satip.service -l"
}
#------------------------------------------------------------------------------------------------------------------------------------------------
delete_systemd_service() {
    printf " 🗑️  Lösche vtuner systemd-service ..."

    if [[ -f "$SystemdServiceFile" ]]; then
        sudo systemctl stop vtuner-satip.service
        sudo systemctl disable vtuner-satip.service
        sudo rm -f "$SystemdServiceFile"
        sudo systemctl daemon-reload
        printf "\r Lösche vtuner systemd-service $CheckMark     \n"
        echo ""
    else
        printf "\r Lösche vtuner systemd-service $CrossMark     \n (Datei nicht gefunden $SystemdServiceFile) \n"
    fi
}
#------------------------------------------------------------------------------------------------------------------------------------------------
show_systemd_service() {
    if [[ ! -f "$SystemdServiceFile" || ! -r "$SystemdServiceFile" ]]; then
        echo ""
        echo " Zeige vtuner systemd-service $CrossMark "
        echo " (Datei nicht gefunden $SystemdServiceFile)"
        echo ""
        return 1
    fi

    echo ""
    echo "+------------------------------------------------------------------------------------------+"
    echo "| systemd service file ($SystemdServiceFile)                                               |"
    echo "+------------------------------------------------------------------------------------------+"
    echo ""
    cat "$SystemdServiceFile"
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
    read -s -n 1 subchoice
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
        if sudo timeout 30 systemctl restart vdr; then
            echo " VDR Neustart $CheckMark    "
        else
            echo " VDR Neustart $CrossMark    "
            #journalctl -u vdr -xe --no-pager --since "1min ago" | grep -iE "fail|error|timeout"
            journalctl -u vdr -xe
        fi
    fi
}
#------------------------------------------------------------------------------------------------------------------------------------------------
prompt_cursor() {
    trap "tput cnorm; exit" INT TERM EXIT
    if   [[ $1 == true ]]; then
        tput cnorm
    elif [[ $1 == false ]]; then
        tput civis
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
            read -s -n 1 choice

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
            read -s -n 1 choice
            echo ""
            case "$choice" in
                1)
                    load_vtuner_modules
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

	# hide prompt cursor
	prompt_cursor false

#------------------------------------------------------------------------------------------------------------------------------------------------

	# Main Script
	show_main_menu

#------------------------------------------------------------------------------------------------------------------------------------------------

exit 0

#------------------------------------------------------------------------------------------------------------------------------------------------


#TODO !!!!!! => system hängt beim herunterfgahren, kill $(pgrep satip) bevor system herunterfährt bzw in systemd deinste einbauen wenn vtuiner systemd dienst beendet wird


# TODO create function: save conf datei
# save config in /root/.vtuner-cli.conf (conf datei)
# config dialog for global variables | satip server ip =< save config in conf datei
# save vtuner count in conf datei
# save vtuner - frontend zuornung in conf datei

# TODO create function: load conf datei

# TODO create new channels.conf
# systemctl stop vdr
# w_scan -fs -s S19E2 > raw.conf

#------------------------------------------------------------------------------------------------------------------------------------------------
#
# notice


exit
echo "🔍 Suche nach SAT>IP-Servern im LAN (192.168.1.x)..."

for ip in {1..254}; do
    host="192.168.1.$ip"
    (
        echo -ne "OPTIONS rtsp://$host:554/ RTSP/1.0\r\nCSeq: 1\r\n\r\n" \
        | timeout 1 nc -w 1 $host 554 2>/dev/null \
        | grep -qi "RTSP/1.0" && echo "$host"
    ) &
done
wait

#------------------------------------------------------------------------------------------------------------------------------------------------



