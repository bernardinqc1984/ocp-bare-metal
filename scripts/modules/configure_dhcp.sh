#!/bin/bash
#===============================================================================
# Module: configure_dhcp.sh
# Description: Configuration du serveur DHCP pour le provisionnement PXE
#===============================================================================

configure_dhcp_server() {
    log INFO "Génération de la configuration DHCP..."
    
    local prov_subnet=$(yq e '.network.provisioning.subnet' "$CONFIG_FILE" | cut -d'/' -f1)
    local prov_netmask="255.255.255.0"
    local bastion_prov_ip=$(yq e '.nodes.bastion.provisioningIp' "$CONFIG_FILE")
    local bastion_ip=$(yq e '.nodes.bastion.ip' "$CONFIG_FILE")
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "[DRY-RUN] Configuration DHCP pour subnet $prov_subnet"
        return
    fi
    
    # Génération du fichier dhcpd.conf
    cat > /etc/dhcp/dhcpd.conf << EOF
# Configuration DHCP pour OpenShift Bare Metal
# Généré automatiquement par le script d'installation

option space pxelinux;
option pxelinux.magic code 208 = string;
option pxelinux.configfile code 209 = text;
option pxelinux.pathprefix code 210 = text;
option pxelinux.reboottime code 211 = unsigned integer 32;
option architecture-type code 93 = unsigned integer 16;

# Subnet de provisionnement
subnet ${prov_subnet} netmask ${prov_netmask} {
    option routers ${bastion_prov_ip};
    option domain-name-servers ${bastion_ip};
    option broadcast-address $(echo $prov_subnet | sed 's/\.0$/.255/');
    
    range $(echo $prov_subnet | sed 's/\.0$/.50/') $(echo $prov_subnet | sed 's/\.0$/.250/');
    default-lease-time 600;
    max-lease-time 7200;
    
    next-server ${bastion_prov_ip};
    
    # Boot BIOS/UEFI
    if exists user-class and option user-class = "iPXE" {
        filename "http://${bastion_ip}:8080/boot.ipxe";
    } else {
        filename "pxelinux.0";
    }
    
    class "pxeclients" {
        match if substring (option vendor-class-identifier, 0, 9) = "PXEClient";
        if option architecture-type = 00:07 {
            filename "uefi/shimx64.efi";
        } else {
            filename "pxelinux.0";
        }
    }
}

# Réservations DHCP pour les nœuds
EOF

    # Ajout des réservations pour chaque nœud
    local node_types=("bootstrap" "masters" "workers" "infras")
    
    for node_type in "${node_types[@]}"; do
        if [[ "$node_type" == "bootstrap" ]]; then
            local hostname=$(yq e '.nodes.bootstrap.hostname' "$CONFIG_FILE")
            local mac=$(yq e '.nodes.bootstrap.mac' "$CONFIG_FILE")
            local ip=$(yq e '.nodes.bootstrap.provisioningIp' "$CONFIG_FILE")
            
            cat >> /etc/dhcp/dhcpd.conf << EOF

host bootstrap {
    hardware ethernet ${mac};
    fixed-address ${ip};
    option host-name "${hostname}";
}
EOF
        else
            local count=$(yq e ".nodes.${node_type} | length" "$CONFIG_FILE")
            for ((i=0; i<count; i++)); do
                local hostname=$(yq e ".nodes.${node_type}[$i].hostname" "$CONFIG_FILE")
                local mac=$(yq e ".nodes.${node_type}[$i].mac" "$CONFIG_FILE")
                local ip=$(yq e ".nodes.${node_type}[$i].provisioningIp" "$CONFIG_FILE")
                
                cat >> /etc/dhcp/dhcpd.conf << EOF

host ${hostname%%.*} {
    hardware ethernet ${mac};
    fixed-address ${ip};
    option host-name "${hostname}";
}
EOF
            done
        fi
    done
    
    # Configuration de l'interface d'écoute
    local prov_iface=$(yq e '.nodes.bastion.interfaces.provisioning' "$CONFIG_FILE")
    echo "INTERFACESv4=\"${prov_iface}\"" > /etc/sysconfig/dhcpd
    
    # Activation du service
    systemctl enable dhcpd
    systemctl restart dhcpd
    
    log SUCCESS "Serveur DHCP configuré et démarré"
}
