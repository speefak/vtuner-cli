#!/bin/bash

# Abhängigkeiten prüfen
if ! command -v dialog &> /dev/null; then
    echo "dialog ist nicht installiert. Bitte mit 'sudo apt install dialog' installieren."
    exit 1
fi

# Benutzer nach Anzahl der vtuners fragen
read -rp "Wie viele vtuner-Devices möchten Sie einrichten? " DEVICE_COUNT
if ! [[ "$DEVICE_COUNT" =~ ^[0-9]+$ ]]; then
    echo "Ungültige Eingabe: '$DEVICE_COUNT' ist keine Zahl."
    exit 1
fi

# vtunerc laden
sudo modprobe -r vtunerc 2>/dev/null
sudo modprobe vtunerc devices=$DEVICE_COUNT

# Mapping zwischen vtunerX und satip -fX festlegen
declare -A MAPPINGS
for ((i=0; i<DEVICE_COUNT; i++)); do
    OPTIONS=""
    for ((j=0; j<DEVICE_COUNT; j++)); do
        OPTIONS+=" $j \"-f $j für /dev/vtunerc$i\""
    done

    CHOICE=$(eval dialog --clear --stdout --title "Zuordnung für /dev/vtunerc$i" --menu \
        "Wähle das passende -f für /dev/vtunerc$i (Sat>IP Frontend):" 15 50 $DEVICE_COUNT $OPTIONS)

    if [ -z "$CHOICE" ]; then
        echo "Abgebrochen."
        clear
        exit 1
    fi

    MAPPINGS["$i"]="$CHOICE"
done

clear

# satip starten
for ((i=0; i<DEVICE_COUNT; i++)); do
    F_INDEX=${MAPPINGS[$i]}
    echo "Starte: /usr/local/bin/satip -s 192.168.1.9 -p 554 -d /dev/vtunerc$i -D DVBS2 -f $F_INDEX &"
    /usr/local/bin/satip -s 192.168.1.9 -p 554 -d /dev/vtunerc$i -D DVBS2 -f "$F_INDEX" &
done

# VDR neu starten
echo "Starte VDR neu ..."
sudo systemctl restart vdr

echo "Fertig. $DEVICE_COUNT vtuner(s) mit VDR gestartet."
