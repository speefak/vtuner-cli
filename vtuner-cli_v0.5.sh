#!/bin/bash

SATIP_SERVER="192.168.1.9"
SATIP_PORT=554
SATIP_BIN="/usr/local/bin/satip"

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
            echo "Fehler: Treiber konnte nicht geladen werden."
        fi
    else
        echo "Ungültige Eingabe. Bitte nur eine Zahl eingeben."
    fi
}

# Treiber entladen
unload_driver() {
    echo "Entlade vtunerc..."
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
}

# Zuordnung vtunercX → VDR-Frontend
configure_frontends() {
    local devices=$1
    echo ""
    echo "Starte Zuordnung der vtunerc-Devices zu VDR-Frontends:"
    for ((i=0; i<devices; i++)); do
        echo ""
        echo "→ /dev/vtunerc$i"

        while true; do
            read -p "  Welchem VDR-Frontend soll vtuner$i zugeordnet werden? (-f Nummer): " frontend
            if [[ "$frontend" =~ ^[0-9]+$ ]]; then
                echo "  → Starte SAT>IP-Anbindung für vtuner$i mit Frontend $frontend"
                $SATIP_BIN -s $SATIP_SERVER -p $SATIP_PORT -d /dev/vtunerc$i -D DVBS2 -f $frontend &
                break
            else
                echo "  Ungültige Eingabe. Bitte eine Zahl für das VDR-Frontend eingeben."
            fi
        done
    done
    echo ""
    echo "Alle Zuordnungen abgeschlossen."
}

# Menü: vtunerc geladen
show_loaded_menu() {
    while true; do
        echo ""
        echo "Der Treiber vtunerc ist geladen."
        echo "Was möchten Sie tun?"

        if is_satip_running; then
            select choice in "Entladen" "Neu laden (Entladen + neue devices)" "SAT>IP-Verbindungen beenden" "Abbrechen"; do
                case $choice in
                    "Entladen") unload_driver; return ;;
                    "Neu laden (Entladen + neue devices)") reload_driver; return ;;
                    "SAT>IP-Verbindungen beenden") stop_satip_processes; break ;;
                    "Abbrechen") echo "Abgebrochen."; return ;;
                    *) echo "Bitte eine gültige Option wählen (1–4)." ;;
                esac
            done
        else
            select choice in "Frontend-Zuordnung starten" "Entladen" "Neu laden" "Abbrechen"; do
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
                    "Abbrechen") echo "Abgebrochen."; return ;;
                    *) echo "Bitte eine gültige Option wählen (1–4)." ;;
                esac
            done
        fi
    done
}

# Menü: vtunerc nicht geladen
show_unloaded_menu() {
    echo "Der Treiber vtunerc ist derzeit **nicht** geladen."
    select choice in "Laden" "Abbrechen"; do
        case $choice in
            "Laden") load_driver; break ;;
            "Abbrechen") echo "Abgebrochen."; break ;;
            *) echo "Bitte eine gültige Option wählen (1–2)." ;;
        esac
    done
}

# Hauptlogik
if is_driver_loaded; then
    show_loaded_menu
else
    show_unloaded_menu
fi
