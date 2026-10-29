#!/usr/bin/env bash

# ==============================================================================
# Script Name: restore.sh
# Description: Automated system restoration script for Arch/CachyOS.
#              Restores packages, AUR packages, user home, system configs,
#              and applies shell/dotfile configurations.
# Author: thefool
# ==============================================================================

# Exit immediately if a command exits with a non-zero status.
# Treat unset variables as an error.
set -euo pipefail

# --- Configuration ---
BACKUP_DIR="/run/media/thefool/New Volume/backup-archlinux"
REAL_USER="${SUDO_USER:-$USER}"

# --- Helper Functions ---
log_info() {
    echo -e "\e[34m[INFO]\e[0m $1"
}

log_success() {
    echo -e "\e[32m[SUCCESS]\e[0m $1"
}

log_warning() {
    echo -e "\e[33m[WARNING]\e[0m $1"
}

# --- Pre-flight Checks ---
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run with root privileges (sudo ./restore.sh)." 
   exit 1
fi

if [[ ! -d "$BACKUP_DIR" ]]; then
    echo "Error: Backup directory not found at $BACKUP_DIR."
    echo "Please ensure the external drive is mounted."
    exit 1
fi

log_info "Starting system restoration for user: $REAL_USER"

# --- 1. Install Essential Dependencies ---
log_info "Installing essential dependencies (base-devel, git, zstd)..."
pacman -S --needed --noconfirm base-devel git zstd

# --- 2. Restore Official Packages ---
log_info "Restoring official Arch packages from backup..."
if [[ -f "$BACKUP_DIR/pkglist/native.txt" ]]; then
    pacman -S --needed --noconfirm - < "$BACKUP_DIR/pkglist/native.txt" || log_warning "Some native packages failed to install."
else
    log_warning "native.txt not found. Skipping official packages."
fi

# --- 3. Install AUR Helper (yay) ---
if ! command -v yay &> /dev/null; then
    log_info "Installing AUR helper (yay-bin)..."
    sudo -u "$REAL_USER" bash -c '
        cd /tmp
        rm -rf yay-bin
        git clone https://aur.archlinux.org/yay-bin.git
        cd yay-bin
        makepkg -si --noconfirm
        cd /tmp
        rm -rf yay-bin
    '
else
    log_info "AUR helper (yay) is already installed."
fi

# --- 4. Restore AUR Packages ---
log_info "Restoring AUR packages from backup..."
if [[ -f "$BACKUP_DIR/pkglist/aur.txt" ]]; then
    sudo -u "$REAL_USER" yay -S --needed --noconfirm - < "$BACKUP_DIR/pkglist/aur.txt" || log_warning "Some AUR packages failed to install."
else
    log_warning "aur.txt not found. Skipping AUR packages."
fi

# --- 5. Restore User Home Directory (Includes Dotfiles) ---
log_info "Restoring /home/$REAL_USER (this may take a while)..."
if [[ -f "$BACKUP_DIR/home-full.tar.zst" ]]; then
    # The -p flag preserves permissions, and this extracts .zshrc, .config, etc.
    tar --zstd -xpf "$BACKUP_DIR/home-full.tar.zst" -C /
    log_success "User home directory and dotfiles restored."
else
    log_warning "home-full.tar.zst not found. Skipping user home restoration."
fi

# --- 6. Restore System Configurations (/etc) ---
log_info "Restoring system configurations (/etc)..."
if [[ -f "$BACKUP_DIR/etc.tar.gz" ]]; then
    mv /etc /etc.bak.$(date +%Y%m%d%H%M%S)
    tar -xzpf "$BACKUP_DIR/etc.tar.gz" -C /
    log_success "System configurations restored. Previous /etc backed up."
else
    log_warning "etc.tar.gz not found. Skipping system configuration restoration."
fi

# --- 7. Enable Essential Services ---
log_info "Enabling essential services..."
systemctl enable NetworkManager.service
systemctl enable bluetooth.service 2>/dev/null || log_warning "Bluetooth service not found."

# --- 8. Set Zsh as Default Shell & Verify Dotfiles ---
log_info "Configuring shell and verifying dotfiles..."
if command -v zsh &> /dev/null; then
    # Change the default shell to zsh for the user
    chsh -s /usr/bin/zsh "$REAL_USER"
    log_success "Default shell changed to Zsh."
    
    # Verify critical dotfiles exist
    if [[ -f "/home/$REAL_USER/.zshrc" ]] && [[ -d "/home/$REAL_USER/.config/kitty" ]]; then
        log_success "Dotfiles (.zshrc, Kitty, p10k) successfully verified in home directory."
    else
        log_warning "Some dotfiles (like .zshrc or kitty) were not found. Please check manually."
    fi
else
    log_warning "Zsh is not installed. Skipping shell change."
fi

log_success "Restoration complete! Please reboot your system to apply all changes."