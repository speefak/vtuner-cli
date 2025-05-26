#!/bin/bash

# Funktion: Prüft, ob der vtunerc-Treiber geladen ist
is_driver_loaded() {
    lsmod | grep -q "^vtunerc"
}

# Funktion: Lädt den Treiber mit Benutzerangabe für devices
load_driver() {
    read -p "Wie viele vtunerc devices sollen geladen werden? (Zahl): " devices
    if [[ "$devices" =~ ^[0-9]+$ ]]; then
        echo "Lade vtunerc mit $devices device(s)..."
        sudo modprobe vtunerc devices=$devices
    else
        echo "Ungültige Eingabe. Bitte nur eine Zahl eingeben."
    fi
}

# Funktion: Entlädt den Treiber
unload_driver() {
    echo "Entlade vtunerc..."
    sudo rmmod -f vtunerc
}

# Funktion: Entladen + neu Laden mit neuer devices-Zahl
reload_driver() {
    unload_driver
    load_driver
}

# Menüanzeige basierend auf Treiberstatus
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
