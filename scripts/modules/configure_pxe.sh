#!/bin/bash
#===============================================================================
# Module: configure_pxe.sh
# Description: Configuration du menu PXE pour le boot réseau
#===============================================================================

configure_pxe_menu() {
    log INFO "Configuration du menu PXE..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "[DRY-RUN] Configuration menu PXE"
        return
    fi
    
    local bastion_ip=$(yq e '.nodes.bastion.ip' "$CONFIG_FILE")
    local cluster_name=$(yq e '.cluster.name' "$CONFIG_FILE")
    local base_domain=$(yq e '.cluster.baseDomain' "$CONFIG_FILE")
    
    # Menu PXE par défaut (BIOS)
    cat > /var/lib/tftpboot/pxelinux.cfg/default << EOF
UI vesamenu.c32
MENU TITLE OpenShift 4 Installation - ${cluster_name}.${base_domain}
MENU BACKGROUND bg.png
MENU COLOR sel 4 #ffffff std
MENU COLOR title 1 #ffffff
MENU COLOR border 1 #ffffff
MENU COLOR tabmsg 1 #ffffff
TIMEOUT 200
PROMPT 0

LABEL local
    MENU LABEL ^1) Boot from local disk
    MENU DEFAULT
    localboot 0

LABEL bootstrap
    MENU LABEL ^2) Install OpenShift Bootstrap Node
    KERNEL http://${bastion_ip}:8080/rhcos/rhcos-kernel
    APPEND initrd=http://${bastion_ip}:8080/rhcos/rhcos-initramfs.img coreos.live.rootfs_url=http://${bastion_ip}:8080/rhcos/rhcos-rootfs.img coreos.inst.install_dev=/dev/sda coreos.inst.ignition_url=http://${bastion_ip}:8080/ignition/bootstrap.ign ip=dhcp rd.neednet=1

LABEL master
    MENU LABEL ^3) Install OpenShift Master Node
    KERNEL http://${bastion_ip}:8080/rhcos/rhcos-kernel
    APPEND initrd=http://${bastion_ip}:8080/rhcos/rhcos-initramfs.img coreos.live.rootfs_url=http://${bastion_ip}:8080/rhcos/rhcos-rootfs.img coreos.inst.install_dev=/dev/sda coreos.inst.ignition_url=http://${bastion_ip}:8080/ignition/master.ign ip=dhcp rd.neednet=1

LABEL worker
    MENU LABEL ^4) Install OpenShift Worker Node
    KERNEL http://${bastion_ip}:8080/rhcos/rhcos-kernel
    APPEND initrd=http://${bastion_ip}:8080/rhcos/rhcos-initramfs.img coreos.live.rootfs_url=http://${bastion_ip}:8080/rhcos/rhcos-rootfs.img coreos.inst.install_dev=/dev/sda coreos.inst.ignition_url=http://${bastion_ip}:8080/ignition/worker.ign ip=dhcp rd.neednet=1
EOF

    # Menu GRUB pour UEFI
    mkdir -p /var/lib/tftpboot/uefi
    cat > /var/lib/tftpboot/uefi/grub.cfg << EOF
set timeout=20
set default=0

menuentry 'Boot from local disk' {
    exit
}

menuentry 'Install OpenShift Bootstrap Node' {
    linux http://${bastion_ip}:8080/rhcos/rhcos-kernel coreos.live.rootfs_url=http://${bastion_ip}:8080/rhcos/rhcos-rootfs.img coreos.inst.install_dev=/dev/sda coreos.inst.ignition_url=http://${bastion_ip}:8080/ignition/bootstrap.ign ip=dhcp rd.neednet=1
    initrd http://${bastion_ip}:8080/rhcos/rhcos-initramfs.img
}

menuentry 'Install OpenShift Master Node' {
    linux http://${bastion_ip}:8080/rhcos/rhcos-kernel coreos.live.rootfs_url=http://${bastion_ip}:8080/rhcos/rhcos-rootfs.img coreos.inst.install_dev=/dev/sda coreos.inst.ignition_url=http://${bastion_ip}:8080/ignition/master.ign ip=dhcp rd.neednet=1
    initrd http://${bastion_ip}:8080/rhcos/rhcos-initramfs.img
}

menuentry 'Install OpenShift Worker Node' {
    linux http://${bastion_ip}:8080/rhcos/rhcos-kernel coreos.live.rootfs_url=http://${bastion_ip}:8080/rhcos/rhcos-rootfs.img coreos.inst.install_dev=/dev/sda coreos.inst.ignition_url=http://${bastion_ip}:8080/ignition/worker.ign ip=dhcp rd.neednet=1
    initrd http://${bastion_ip}:8080/rhcos/rhcos-initramfs.img
}
EOF

    # Permissions
    chmod 644 /var/lib/tftpboot/pxelinux.cfg/default
    chmod 644 /var/lib/tftpboot/uefi/grub.cfg
    restorecon -RFv /var/lib/tftpboot/
    
    log SUCCESS "Menu PXE configuré"
}

# Configuration PXE spécifique par MAC address
configure_pxe_per_host() {
    log INFO "Configuration PXE par hôte..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "[DRY-RUN] Configuration PXE par hôte"
        return
    fi
    
    local bastion_ip=$(yq e '.nodes.bastion.ip' "$CONFIG_FILE")
    
    # Bootstrap
    local bootstrap_mac=$(yq e '.nodes.bootstrap.mac' "$CONFIG_FILE" | tr ':' '-' | tr '[:upper:]' '[:lower:]')
    cat > "/var/lib/tftpboot/pxelinux.cfg/01-${bootstrap_mac}" << EOF
DEFAULT bootstrap
LABEL bootstrap
    KERNEL http://${bastion_ip}:8080/rhcos/rhcos-kernel
    APPEND initrd=http://${bastion_ip}:8080/rhcos/rhcos-initramfs.img coreos.live.rootfs_url=http://${bastion_ip}:8080/rhcos/rhcos-rootfs.img coreos.inst.install_dev=/dev/sda coreos.inst.ignition_url=http://${bastion_ip}:8080/ignition/bootstrap.ign ip=dhcp rd.neednet=1
EOF

    # Masters
    local master_count=$(yq e '.nodes.masters | length' "$CONFIG_FILE")
    for ((i=0; i<master_count; i++)); do
        local master_mac=$(yq e ".nodes.masters[$i].mac" "$CONFIG_FILE" | tr ':' '-' | tr '[:upper:]' '[:lower:]')
        cat > "/var/lib/tftpboot/pxelinux.cfg/01-${master_mac}" << EOF
DEFAULT master
LABEL master
    KERNEL http://${bastion_ip}:8080/rhcos/rhcos-kernel
    APPEND initrd=http://${bastion_ip}:8080/rhcos/rhcos-initramfs.img coreos.live.rootfs_url=http://${bastion_ip}:8080/rhcos/rhcos-rootfs.img coreos.inst.install_dev=/dev/sda coreos.inst.ignition_url=http://${bastion_ip}:8080/ignition/master.ign ip=dhcp rd.neednet=1
EOF
    done
    
    # Workers
    local worker_count=$(yq e '.nodes.workers | length' "$CONFIG_FILE")
    for ((i=0; i<worker_count; i++)); do
        local worker_mac=$(yq e ".nodes.workers[$i].mac" "$CONFIG_FILE" | tr ':' '-' | tr '[:upper:]' '[:lower:]')
        cat > "/var/lib/tftpboot/pxelinux.cfg/01-${worker_mac}" << EOF
DEFAULT worker
LABEL worker
    KERNEL http://${bastion_ip}:8080/rhcos/rhcos-kernel
    APPEND initrd=http://${bastion_ip}:8080/rhcos/rhcos-initramfs.img coreos.live.rootfs_url=http://${bastion_ip}:8080/rhcos/rhcos-rootfs.img coreos.inst.install_dev=/dev/sda coreos.inst.ignition_url=http://${bastion_ip}:8080/ignition/worker.ign ip=dhcp rd.neednet=1
EOF
    done
    
    restorecon -RFv /var/lib/tftpboot/pxelinux.cfg/
    
    log SUCCESS "Configuration PXE par hôte terminée"
}
