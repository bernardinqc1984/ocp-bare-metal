#!/bin/bash
#===============================================================================
# Module: configure_tftp.sh
# Description: Configuration du serveur TFTP pour le boot PXE
#===============================================================================

configure_tftp_server() {
    log INFO "Configuration du serveur TFTP..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "[DRY-RUN] Configuration TFTP"
        return
    fi
    
    # Création des répertoires
    mkdir -p /var/lib/tftpboot/{pxelinux.cfg,rhcos,uefi}
    
    # Copie des fichiers syslinux pour BIOS
    local syslinux_files=(
        "pxelinux.0"
        "menu.c32"
        "vesamenu.c32"
        "ldlinux.c32"
        "libcom32.c32"
        "libutil.c32"
    )
    
    for file in "${syslinux_files[@]}"; do
        if [[ -f "/usr/share/syslinux/${file}" ]]; then
            cp -v "/usr/share/syslinux/${file}" /var/lib/tftpboot/
        fi
    done
    
    # Configuration pour UEFI (si disponible)
    if [[ -f /boot/efi/EFI/redhat/shimx64.efi ]]; then
        cp /boot/efi/EFI/redhat/shimx64.efi /var/lib/tftpboot/uefi/
        cp /boot/efi/EFI/redhat/grubx64.efi /var/lib/tftpboot/uefi/
    fi
    
    # Permissions
    chmod -R 755 /var/lib/tftpboot/
    restorecon -RFv /var/lib/tftpboot/
    
    # Activation du service TFTP
    systemctl enable tftp.socket
    systemctl start tftp.socket
    
    log SUCCESS "Serveur TFTP configuré et démarré"
}
