#!/bin/bash
#===============================================================================
# Module: download_rhcos.sh
# Description: Téléchargement des images RHCOS
#===============================================================================

download_rhcos_images() {
    log INFO "Récupération des URLs des images RHCOS..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "[DRY-RUN] Téléchargement des images RHCOS"
        return
    fi
    
    local rhcos_dir="/var/www/html/rhcos"
    mkdir -p "$rhcos_dir"
    cd "$rhcos_dir"
    
    # Extraction des URLs depuis openshift-install
    log DEBUG "Extraction des URLs depuis openshift-install..."
    
    local stream_json=$(openshift-install coreos print-stream-json)
    
    # URL du kernel
    local kernel_url=$(echo "$stream_json" | jq -r '.architectures.x86_64.artifacts.metal.formats.pxe.kernel.location')
    
    # URL de l'initramfs
    local initramfs_url=$(echo "$stream_json" | jq -r '.architectures.x86_64.artifacts.metal.formats.pxe.initramfs.location')
    
    # URL du rootfs
    local rootfs_url=$(echo "$stream_json" | jq -r '.architectures.x86_64.artifacts.metal.formats.pxe.rootfs.location')
    
    log INFO "Téléchargement du kernel..."
    wget -q --show-progress -O rhcos-kernel "$kernel_url"
    
    log INFO "Téléchargement de l'initramfs..."
    wget -q --show-progress -O rhcos-initramfs.img "$initramfs_url"
    
    log INFO "Téléchargement du rootfs..."
    wget -q --show-progress -O rhcos-rootfs.img "$rootfs_url"
    
    # Copie vers TFTP
    log DEBUG "Copie des fichiers vers TFTP..."
    cp rhcos-kernel rhcos-initramfs.img /var/lib/tftpboot/rhcos/
    
    # Vérification des fichiers
    log DEBUG "Vérification des fichiers téléchargés..."
    ls -lh "$rhcos_dir/"
    
    # Permissions
    chmod 644 "$rhcos_dir/"*
    chmod 644 /var/lib/tftpboot/rhcos/*
    restorecon -RFv "$rhcos_dir/"
    restorecon -RFv /var/lib/tftpboot/rhcos/
    
    log SUCCESS "Images RHCOS téléchargées et déployées"
}
