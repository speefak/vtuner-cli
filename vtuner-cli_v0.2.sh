#!/bin/bash

# Funktion zum Laden des Treibers
load_driver() {
    read -p "Wie viele vtunerc devices sollen geladen werden? (Zahl): " devices
    if [[ "$devices" =~ ^[0-9]+$ ]]; then
        echo "Lade vtunerc mit $devices device(s)..."
        sudo modprobe vtunerc devices=$devices
    else
        echo "Ungültige Eingabe. Bitte nur eine Zahl eingeben."
    fi
}

# Funktion zum Entladen und Neuladen des Treibers
reload_driver() {
    echo "Entlade vtunerc..."
    sudo rmmod -f vtunerc
    load_driver
}

# Hauptdialog
echo "Was möchten Sie tun?"
select choice in "Laden" "Neu laden (Entladen + neue devices)" "Abbrechen"; do
    case $choice in
        "Laden")
            load_driver
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

