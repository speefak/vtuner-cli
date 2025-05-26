#!/bin/bash

SATIP_SERVER="192.168.1.9"
SATIP_PORT=554
SATIP_BIN="/usr/local/bin/satip"
MAPPING_FILE="/tmp/vtuner_map.txt"

# Prüfen, ob vtunerc geladen ist
is_driver_loaded() {
    lsmod | grep -q "^vtunerc"
}

# Prüfen, ob satip-Prozesse laufen
is_satip_running() {
    pgrep -f "$SATIP_BIN" > /dev/null
}

# Treiber laden
load_driver() {
    read -p "Wie viele vtunerc devices sollen geladen werden? (Zahl): " devices
    if [[ "$devices" =~ ^[0-9]+$ ]]; then
        echo "Lade vtunerc mit $devices device(s)..."
        sudo modprobe vtunerc devices=$devices
        sleep 1
        if is_driver_loaded; then
            configure_frontends "$devices"
        else
            echo "❌ Fehler: Treiber konnte nicht geladen werden."
        fi
    else
        echo "❌ Ungültige Eingabe. Bitte nur eine Zahl eingeben."
    fi
}

# Treiber entladen
unload_driver() {
    echo "🛑 Beende alle SAT>IP-Verbindungen..."
    stop_satip_processes

    echo "📤 Entlade vtunerc-Treiber..."
    sudo rmmod -f vtunerc
}

# Neu laden
reload_driver() {
    unload_driver
    load_driver
}

# SAT>IP-Prozesse beenden
stop_satip_processes() {
    echo "Beende alle SAT>IP-Verbindungen..."
    pkill -f "$SATIP_BIN"
    echo "SAT>IP-Prozesse beendet."
    rm -f "$MAPPING_FILE"
}

# Zuordnung vtunercX → VDR-Frontend
configure_frontends() {
    local devices=$1
    echo "" > "$MAPPING_FILE"
    echo ""
    echo "🎛️  Starte Zuordnung der vtunerc-Devices zu VDR-Frontends:"
    for ((i=0; i<devices; i++)); do
        echo ""
        echo "→ /dev/vtunerc$i"

        while true; do
            read -e -p "  Welchem VDR-Frontend soll vtuner$i zugeordnet werden? (-f Nummer): " -i "$(($i+1))" frontend
            if [[ "$frontend" =~ ^[0-9]+$ ]]; then
                echo "  → Starte SAT>IP-Anbindung für vtuner$i mit Frontend $frontend"
                $SATIP_BIN -s $SATIP_SERVER -p $SATIP_PORT -d /dev/vtunerc$i -D DVBS2 -f $frontend &
                echo "vtuner$i → frontend $frontend" >> "$MAPPING_FILE"
                break
            else
                echo "  ❌ Ungültige Eingabe. Bitte eine Zahl für das VDR-Frontend eingeben."
            fi
        done
    done
    echo ""
    echo "✅ Alle Zuordnungen abgeschlossen."
}



# Status anzeigen
show_status() {
    echo ""
    echo "📡 Aktive vtunerc-Geräte:"
    ls /dev/vtunerc* 2>/dev/null || echo "  Keine vtunerc-Geräte gefunden."

    echo ""
    echo "🛰️  Laufende SAT>IP-Verbindungen:"
    local processes
    processes=$(pgrep -af "$SATIP_BIN")
    if [[ -z "$processes" ]]; then
        echo "  Keine satip-Prozesse aktiv."
    else
        echo "$processes"
    fi

    echo ""
    echo "📋 Aktuelle Zuordnung (vtuner → frontend):"
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

# Menü wenn vtunerc geladen ist
show_loaded_menu() {
    while true; do
        echo ""
        echo "⚙️  Der Treiber vtunerc ist geladen."
        if is_satip_running; then
            select choice in "Entladen" "Neu laden (Entladen + neue devices)" "SAT>IP-Verbindungen beenden" "Alle vtuner/SAT>IP anzeigen" "Abbrechen"; do
                case $choice in
                    "Entladen") unload_driver; return ;;
                    "Neu laden (Entladen + neue devices)") reload_driver; return ;;
                    "SAT>IP-Verbindungen beenden") stop_satip_processes; break ;;
                    "Alle vtuner/SAT>IP anzeigen") show_status; break ;;
                    "Abbrechen") echo "Abgebrochen."; return ;;
                    *) echo "❗ Bitte eine gültige Option wählen (1–5)." ;;
                esac
            done
        else
            select choice in "Frontend-Zuordnung starten" "Entladen" "Neu laden" "Alle vtuner/SAT>IP anzeigen" "Abbrechen"; do
                case $choice in
                    "Frontend-Zuordnung starten")
                        count=$(ls /dev/vtunerc* 2>/dev/null | wc -l)
                        if [[ $count -gt 0 ]]; then
                            configure_frontends "$count"
                        else
                            echo "Keine /dev/vtunerc-Geräte gefunden."
                        fi
                        break ;;
                    "Entladen") unload_driver; return ;;
                    "Neu laden") reload_driver; return ;;
                    "Alle vtuner/SAT>IP anzeigen") show_status; break ;;
                    "Abbrechen") echo "Abgebrochen."; return ;;
                    *) echo "❗ Bitte eine gültige Option wählen (1–5)." ;;
                esac
            done
        fi
    done
}

# Menü wenn vtunerc NICHT geladen ist
show_unloaded_menu() {
    echo "ℹ️  Der Treiber vtunerc ist derzeit NICHT geladen."
    select choice in "Laden" "Abbrechen"; do
        case $choice in
            "Laden") load_driver; break ;;
            "Abbrechen") echo "Abgebrochen."; break ;;
            *) echo "❗ Bitte eine gültige Option wählen (1–2)." ;;
        esac
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
	if [ ! "$(whoami)" = "root" ]; then echo "";else echo "You are Root !";exit 1;fi

#------------------------------------------------------------------------------------------------------------------------------------------------

	# Main Script
	if is_driver_loaded; then
		show_loaded_menu
	else
		show_unloaded_menu
	fi

#------------------------------------------------------------------------------------------------------------------------------------------------

exit 0

#------------------------------------------------------------------------------------------------------------------------------------------------
#
# notice
