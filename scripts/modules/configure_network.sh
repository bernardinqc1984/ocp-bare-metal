#!/bin/bash
#===============================================================================
# Module: configure_network.sh
# Description: Configuration des interfaces réseau du bastion
#===============================================================================

configure_bastion_network() {
    log INFO "Configuration de l'interface baremetal..."
    
    local baremetal_iface=$(yq e '.nodes.bastion.interfaces.baremetal' "$CONFIG_FILE")
    local bastion_ip=$(yq e '.nodes.bastion.ip' "$CONFIG_FILE")
    local gateway=$(yq e '.network.baremetal.gateway' "$CONFIG_FILE")
    local dns=$(yq e '.network.dns.servers[0]' "$CONFIG_FILE")
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "[DRY-RUN] Configuration de $baremetal_iface avec IP $bastion_ip"
    else
        nmcli con mod "$baremetal_iface" ipv4.addresses "${bastion_ip}/24"
        nmcli con mod "$baremetal_iface" ipv4.gateway "$gateway"
        nmcli con mod "$baremetal_iface" ipv4.dns "$dns"
        nmcli con mod "$baremetal_iface" ipv4.method manual
        nmcli con up "$baremetal_iface"
    fi
    
    log INFO "Configuration de l'interface provisioning..."
    
    local prov_iface=$(yq e '.nodes.bastion.interfaces.provisioning' "$CONFIG_FILE")
    local prov_ip=$(yq e '.nodes.bastion.provisioningIp' "$CONFIG_FILE")
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "[DRY-RUN] Configuration de $prov_iface avec IP $prov_ip"
    else
        nmcli con mod "$prov_iface" ipv4.addresses "${prov_ip}/24"
        nmcli con mod "$prov_iface" ipv4.method manual
        nmcli con up "$prov_iface"
    fi
    
    log SUCCESS "Interfaces réseau configurées"
}
