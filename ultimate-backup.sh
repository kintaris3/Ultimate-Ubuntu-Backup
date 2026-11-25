#!/usr/bin/env bash

# Colors for terminal readability
BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_banner() {
    clear
    cat << "BANNER_EOF"
 _   _ _ _   _                 _       
| | | | | |_(_)_ __ ___   __ _| |_ ___ 
| | | | | __| | '_ ` _ \ / _` | __/ _ \
| |_| | | |_| | | | | | | (_| | ||  __/
 \___/|_|\__|_|_| |_| |_|\__,_|\__\___|
  _   _ _                 _         ____             _                
 | | | | |__  _   _ _ __ | |_ _   _| __ )  __ _  ___| | ___   _ _ __  
 | | | | '_ \| | | | '_ \| __| | | |  _ \ / _` |/ __| |/ / | | | '_ \ 
 | |_| | |_) | |_| | | | | |_| |_| | |_) | (_| | (__|   <| |_| | |_) |
  \___/|_.__/ \__,_|_| |_|\__|\__,_|____/ \__,_|\___|_|\_\\__,_| .__/ 
                                                               |_|    
        /\_/\
       ( o.o )   "Better safe than sorry—let's lock your data down!"
        > ^ <

        Code written by Christopher G. Pitts Jr.
BANNER_EOF
    echo ""
}

pause_prompt() {
    echo ""
    read -p "Press Enter to return to the Backup Menu..."
}

# Helper: Choose destination folder (Home or detected USB drive)
select_destination() {
    echo -e "${BOLD}${CYAN}Where would you like to save this backup?${NC}"
    echo "  1) Home Folder ($HOME)"

    USB_DRIVES=()
    if [ -d "/media/$USER" ]; then
        while IFS= read -r -d '' dir; do
            USB_DRIVES+=("$dir")
        done < <(find "/media/$USER" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
    fi

    IDX=2
    for drive in "${USB_DRIVES[@]}"; do
        echo "  $IDX) External / USB Drive ($drive)"
        ((IDX++))
    done
    echo "  $IDX) Enter a custom path manually"
    echo ""

    read -p "Select destination [1-$IDX]: " DEST_CHOICE
    if [[ "$DEST_CHOICE" == "1" ]] || [[ -z "$DEST_CHOICE" ]]; then
        DEST_ROOT="$HOME"
    elif [[ "$DEST_CHOICE" -ge 2 ]] && [[ "$DEST_CHOICE" -lt "$IDX" ]]; then
        DEST_ROOT="${USB_DRIVES[$((DEST_CHOICE-2))]}"
    else
        read -p "Enter full destination path: " CUSTOM_PATH
        DEST_ROOT="${CUSTOM_PATH:-$HOME}"
    fi

    TIMESTAMP=$(date +"%Y-%m-%d_%H-%M")
    BACKUP_DIR="$DEST_ROOT/Ubuntu-Backup-$TIMESTAMP"
    mkdir -p "$BACKUP_DIR"
    echo -e "${GREEN}Backup folder prepared: $BACKUP_DIR${NC}\n"
}

# --- MODULE 1: SYSTEM SNAPSHOT (TIMESHIFT) ---
system_snapshot() {
    print_banner
    echo -e "${BOLD}${CYAN}=== [1] System Snapshot (Timeshift) ===${NC}"
    echo "Think of a System Snapshot like a 'Save Point' for your operating system."
    echo "It backs up system files and settings (not your personal Downloads/Documents)"
    echo "so you can roll back your PC if an update or tweak ever breaks something."
    echo ""
    echo "  1) Quick Terminal Snapshot (Creates an immediate RSYNC restore point right now)"
    echo "     -> Best if Timeshift is already set up and you want a fast save point."
    echo ""
    echo "  2) Open Timeshift Setup Wizard (Graphical Interface)"
    echo "     -> Best for first-timers! Lets you visually pick your backup drive,"
    echo "        set automatic schedules, or browse/restore existing snapshots."
    echo ""
    echo "  3) Return to Main Menu"
    echo ""
    read -p "Choose an option [1-3]: " TS_CHOICE

    case $TS_CHOICE in
        1)
            sudo -v
            if ! command -v timeshift &> /dev/null; then
                echo -e "\n${CYAN}--> Installing Timeshift...${NC}"
                sudo apt update && sudo apt install -y timeshift
            fi
            echo -e "\n${CYAN}--> Creating on-demand RSYNC system snapshot...${NC}"
            sudo timeshift --create --comments "Ultimate Ubuntu Backup - Manual Snapshot" --tags O
            echo -e "\n${GREEN}System snapshot complete!${NC}"
            ;;
        2)
            sudo -v
            if ! command -v timeshift &> /dev/null; then
                echo -e "\n${CYAN}--> Installing Timeshift...${NC}"
                sudo apt update && sudo apt install -y timeshift
            fi
            echo -e "\n${CYAN}--> Launching Timeshift GUI...${NC}"
            sudo timeshift-gtk &
            ;;
        *)
            return 0
            ;;
    esac
}

# --- MODULE 2: EXPORT INSTALLED APPS ---
export_apps() {
    local TARGET_DIR="$1"
    echo -e "${CYAN}--> Exporting installed software lists & generating restore script...${NC}"

    # Export manually installed APT apps (excludes core OS libraries)
    apt-mark showmanual | sort > "$TARGET_DIR/apt-manual-packages.txt"

    # Export Flatpak apps if installed
    if command -v flatpak &> /dev/null; then
        flatpak list --app --columns=application > "$TARGET_DIR/flatpak-apps.txt"
    fi

    # Export Snap apps if installed
    if command -v snap &> /dev/null; then
        snap list | awk 'NR>1 {print $1}' > "$TARGET_DIR/snap-apps.txt"
    fi

    # Generate standalone restore-apps.sh inside the backup bundle
    cat << 'RESTORE_EOF' > "$TARGET_DIR/restore-apps.sh"
#!/usr/bin/env bash
echo "=== Restoring Applications from Backup ==="
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/apt-manual-packages.txt" ]; then
    echo "--> Reinstalling APT packages..."
    sudo apt update
    xargs -a "$SCRIPT_DIR/apt-manual-packages.txt" sudo apt install -y --ignore-missing
fi

if [ -f "$SCRIPT_DIR/flatpak-apps.txt" ] && command -v flatpak &> /dev/null; then
    echo "--> Reinstalling Flatpak apps..."
    while read -r app; do
        [ -n "$app" ] && flatpak install -y flathub "$app"
    done < "$SCRIPT_DIR/flatpak-apps.txt"
fi

if [ -f "$SCRIPT_DIR/snap-apps.txt" ] && command -v snap &> /dev/null; then
    echo "--> Reinstalling Snap apps..."
    while read -r snapapp; do
        [ -n "$snapapp" ] && sudo snap install "$snapapp"
    done < "$SCRIPT_DIR/snap-apps.txt"
fi

echo "=== App Restoration Complete! ==="
RESTORE_EOF
    chmod +x "$TARGET_DIR/restore-apps.sh"
    echo -e "${GREEN}Software manifest and 'restore-apps.sh' saved!${NC}"
}

# --- MODULE 3: BACKUP PERSONAL FILES & CONFIGS ---
backup_personal() {
    local TARGET_DIR="$1"

    echo -e "${BOLD}${YELLOW}Personal Files & Settings Selection:${NC}"
    echo "By default, we back up your desktop layout, keybindings, custom scripts,"
    echo "and app shortcuts (this is tiny and takes just a few seconds)."
    echo ""

    read -p "Include your ~/Documents folder? [Y/n]: " INC_DOCS
    INC_DOCS=${INC_DOCS:-Y}

    echo ""
    echo -e "${YELLOW}Note:${NC} Your ~/Downloads folder often holds large ISO files, videos, or archives."
    echo "Including it is great for a full migration, but it will increase the backup size"
    echo "and may take a little while to finish depending on how much is inside."
    read -p "Include your ~/Downloads folder? [y/N]: " INC_DOWNLOADS
    INC_DOWNLOADS=${INC_DOWNLOADS:-N}

    echo -e "\n${CYAN}--> Saving GNOME desktop settings & keybindings...${NC}"
    dconf dump / > "$TARGET_DIR/gnome-settings.dconf" 2>/dev/null || true

    # Build list of existing paths to archive safely
    PATHS_TO_ARCHIVE=()
    for item in ".local/bin" ".local/share/applications" ".bashrc" ".profile" ".ssh"; do
        [ -e "$HOME/$item" ] && PATHS_TO_ARCHIVE+=("$item")
    done

    [[ "$INC_DOCS" =~ ^[Yy]$ ]] && [ -d "$HOME/Documents" ] && PATHS_TO_ARCHIVE+=("Documents")
    [[ "$INC_DOWNLOADS" =~ ^[Yy]$ ]] && [ -d "$HOME/Downloads" ] && PATHS_TO_ARCHIVE+=("Downloads")

    echo -e "${CYAN}--> Compressing files into personal-backup.tar.gz (please wait)...${NC}"
    tar -czf "$TARGET_DIR/personal-backup.tar.gz" -C "$HOME" "${PATHS_TO_ARCHIVE[@]}" 2>/dev/null

    ARCHIVE_SIZE=$(du -sh "$TARGET_DIR/personal-backup.tar.gz" | awk '{print $1}')
    echo -e "${GREEN}Personal backup complete! Archive size: ${BOLD}${ARCHIVE_SIZE}${NC}"
}

# --- MODULE 5: RESTORE FROM BACKUP BUNDLE ---
restore_backup() {
    print_banner
    echo -e "${BOLD}${CYAN}=== [5] Restore from a Backup Bundle ===${NC}"
    echo "Don't worry—nothing will be overwritten until you confirm each step."
    echo "Look for a folder named 'Ubuntu-Backup-YYYY-MM-DD_HH-MM' on your drive or USB."
    echo ""
    read -p "Enter the full path to your Ubuntu-Backup folder: " RESTORE_PATH

    if [ ! -d "$RESTORE_PATH" ]; then
        echo -e "${RED}Folder not found: $RESTORE_PATH${NC}"
        echo "Tip: You can drag and drop the backup folder directly into this terminal window!"
        return 1
    fi

    echo -e "\n${GREEN}Backup folder verified!${NC}"

    if [ -f "$RESTORE_PATH/personal-backup.tar.gz" ]; then
        read -p "Restore personal files, Documents/Downloads, and custom scripts? [Y/n]: " RES_FILES
        RES_FILES=${RES_FILES:-Y}
        if [[ "$RES_FILES" =~ ^[Yy]$ ]]; then
            echo -e "${CYAN}--> Extracting files into $HOME...${NC}"
            tar -xzf "$RESTORE_PATH/personal-backup.tar.gz" -C "$HOME"
            echo -e "${GREEN}Files restored!${NC}"
        fi
    fi

    if [ -f "$RESTORE_PATH/gnome-settings.dconf" ]; then
        read -p "Restore GNOME desktop settings & shortcuts? [Y/n]: " RES_GNOME
        RES_GNOME=${RES_GNOME:-Y}
        if [[ "$RES_GNOME" =~ ^[Yy]$ ]]; then
            echo -e "${CYAN}--> Loading GNOME settings...${NC}"
            dconf load / < "$RESTORE_PATH/gnome-settings.dconf"
            echo -e "${GREEN}GNOME settings restored!${NC}"
        fi
    fi

    if [ -f "$RESTORE_PATH/restore-apps.sh" ]; then
        read -p "Reinstall all your saved APT, Flatpak, and Snap apps now? [y/N]: " RES_APPS
        if [[ "$RES_APPS" =~ ^[Yy]$ ]]; then
            bash "$RESTORE_PATH/restore-apps.sh"
        fi
    fi

    echo -e "\n${GREEN}${BOLD}=== Restore Process Complete! A logout or reboot is recommended. ===${NC}"
}

# --- MAIN MENU LOOP ---
while true; do
    print_banner
    echo -e "${BOLD}${CYAN}Select a Backup or Restore Operation:${NC}"
    echo "  1) System Snapshot (Timeshift — Roll back OS updates/tweaks)"
    echo "  2) Export Installed Software List (Creates a 1-click app reinstaller)"
    echo "  3) Backup Personal Files & Settings (Configs, Scripts, Documents/Downloads)"
    echo "  4) Complete Migration Bundle (Runs Options 2 & 3 -> Saves to PC or USB)"
    echo "  5) Restore from an Existing Backup Bundle"
    echo "  6) Exit"
    echo ""
    read -p "Enter your choice [1-6]: " CHOICE

    case $CHOICE in
        1)
            system_snapshot
            pause_prompt
            ;;
        2)
            print_banner
            select_destination
            export_apps "$BACKUP_DIR"
            pause_prompt
            ;;
        3)
            print_banner
            select_destination
            backup_personal "$BACKUP_DIR"
            pause_prompt
            ;;
        4)
            print_banner
            echo -e "${BOLD}${CYAN}=== [4] Complete Migration Bundle ===${NC}"
            echo "This creates a self-contained folder with your installed apps list,"
            echo "desktop settings, scripts, and personal files—ready for a USB stick."
            echo ""
            select_destination
            export_apps "$BACKUP_DIR"
            echo ""
            backup_personal "$BACKUP_DIR"
            echo -e "\n${GREEN}${BOLD}=== Full Backup Bundle Ready at: $BACKUP_DIR ===${NC}"
            pause_prompt
            ;;
        5)
            restore_backup
            pause_prompt
            ;;
        6)
            echo "Exiting Ultimate Ubuntu Backup. Your data is in good hands!"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option. Please enter 1-6.${NC}"
            sleep 1
            ;;
    esac
done
