#!/bin/bash

SATIP_SERVER="192.168.1.9"
SATIP_PORT=554
SATIP_BIN="/usr/local/bin/satip"

# Prüfen, ob vtunerc geladen ist
is_driver_loaded() {
    lsmod | grep -q "^vtunerc"
}

# Treiber laden
load_driver() {
    read -p "Wie viele vtunerc devices sollen geladen werden? (Zahl): " devices
    if [[ "$devices" =~ ^[0-9]+$ ]]; then
        echo "Lade vtunerc mit $devices device(s)..."
        sudo modprobe vtunerc devices=$devices
        sleep 1  # kurz warten, damit /dev/vtunercX verfügbar ist
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

# Zuordnung vtunercX → VDR-Frontend
configure_frontends() {
    local devices=$1
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

# Hauptmenü
if is_driver_loaded; then
    echo "Der Treiber vtunerc ist derzeit geladen."
    echo "Was möchten Sie tun?"
    select choice in "Entladen" "Neu laden (Entladen + neue devices)" "Abbrechen"; do
        case $choice in
            "Entladen")
                unload_driver
                break
                ;;
            "Neu laden (Entladen + neue devices)")
                reload_driver
                break
                ;;
            "Abbrechen")
                echo "Abgebrochen."
                break
                ;;
            *)
                echo "Bitte eine gültige Option wählen (1–3)."
                ;;
        esac
    done
else
    echo "Der Treiber vtunerc ist derzeit **nicht** geladen."
    echo "Was möchten Sie tun?"
    select choice in "Laden" "Abbrechen"; do
        case $choice in
            "Laden")
                load_driver
                break
                ;;
            "Abbrechen")
                echo "Abgebrochen."
                break
                ;;
            *)
                echo "Bitte eine gültige Option wählen (1–2)."
                ;;
        esac
    done
fi
