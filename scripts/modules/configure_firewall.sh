#!/bin/bash
#===============================================================================
# Module: configure_firewall.sh
# Description: Configuration du firewall pour OpenShift
#===============================================================================

configure_firewall() {
    log INFO "Configuration des règles firewall..."
    
    local ports=(
        "dhcp"
        "tftp"
        "http"
        "https"
        "dns"
    )
    
    local tcp_ports=(
        "6443"   # Kubernetes API
        "22623"  # Machine Config Server
        "8080"   # HTTP alternatif
        "9000"   # HAProxy stats
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "[DRY-RUN] Ajout des services: ${ports[*]}"
        log DEBUG "[DRY-RUN] Ajout des ports TCP: ${tcp_ports[*]}"
    else
        # Activation du firewall
        systemctl enable --now firewalld
        
        # Services
        for svc in "${ports[@]}"; do
            firewall-cmd --permanent --add-service="$svc"
        done
        
        # Ports TCP
        for port in "${tcp_ports[@]}"; do
            firewall-cmd --permanent --add-port="${port}/tcp"
        done
        
        # Rechargement
        firewall-cmd --reload
    fi
    
    log SUCCESS "Firewall configuré"
}
