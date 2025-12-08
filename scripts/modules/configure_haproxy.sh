#!/bin/bash
#===============================================================================
# Module: configure_haproxy.sh
# Description: Configuration du load balancer HAProxy
#===============================================================================

configure_haproxy() {
    log INFO "Génération de la configuration HAProxy..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "[DRY-RUN] Configuration HAProxy"
        return
    fi
    
    local bastion_ip=$(yq e '.nodes.bastion.ip' "$CONFIG_FILE")
    local bootstrap_ip=$(yq e '.nodes.bootstrap.ip' "$CONFIG_FILE")
    
    # Début de la configuration
    cat > /etc/haproxy/haproxy.cfg << 'EOF'
#---------------------------------------------------------------------
# HAProxy Configuration for OpenShift Bare Metal
# Generated automatically by installation script
#---------------------------------------------------------------------

global
    log         127.0.0.1 local2
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     4000
    user        haproxy
    group       haproxy
    daemon
    stats socket /var/lib/haproxy/stats

defaults
    mode                    http
    log                     global
    option                  httplog
    option                  dontlognull
    option http-server-close
    option forwardfor       except 127.0.0.0/8
    option                  redispatch
    retries                 3
    timeout http-request    10s
    timeout queue           1m
    timeout connect         10s
    timeout client          1m
    timeout server          1m
    timeout http-keep-alive 10s
    timeout check           10s
    maxconn                 3000

#---------------------------------------------------------------------
# Stats Page
#---------------------------------------------------------------------
listen stats
    bind *:9000
    mode http
    stats enable
    stats uri /stats
    stats refresh 10s
    stats admin if LOCALHOST

#---------------------------------------------------------------------
# Kubernetes API Frontend (6443)
#---------------------------------------------------------------------
frontend api_frontend
    bind *:6443
    mode tcp
    option tcplog
    default_backend api_backend

backend api_backend
    mode tcp
    balance roundrobin
    option tcp-check
EOF

    # Ajout du bootstrap
    echo "    server bootstrap ${bootstrap_ip}:6443 check" >> /etc/haproxy/haproxy.cfg
    
    # Ajout des masters
    local master_count=$(yq e '.nodes.masters | length' "$CONFIG_FILE")
    for ((i=0; i<master_count; i++)); do
        local master_name=$(yq e ".nodes.masters[$i].hostname" "$CONFIG_FILE" | cut -d'.' -f1)
        local master_ip=$(yq e ".nodes.masters[$i].ip" "$CONFIG_FILE")
        echo "    server ${master_name} ${master_ip}:6443 check" >> /etc/haproxy/haproxy.cfg
    done
    
    # Machine Config Server
    cat >> /etc/haproxy/haproxy.cfg << 'EOF'

#---------------------------------------------------------------------
# Machine Config Server (22623)
#---------------------------------------------------------------------
frontend machine_config_frontend
    bind *:22623
    mode tcp
    option tcplog
    default_backend machine_config_backend

backend machine_config_backend
    mode tcp
    balance roundrobin
EOF

    echo "    server bootstrap ${bootstrap_ip}:22623 check" >> /etc/haproxy/haproxy.cfg
    
    for ((i=0; i<master_count; i++)); do
        local master_name=$(yq e ".nodes.masters[$i].hostname" "$CONFIG_FILE" | cut -d'.' -f1)
        local master_ip=$(yq e ".nodes.masters[$i].ip" "$CONFIG_FILE")
        echo "    server ${master_name} ${master_ip}:22623 check" >> /etc/haproxy/haproxy.cfg
    done
    
    # HTTP Ingress
    cat >> /etc/haproxy/haproxy.cfg << 'EOF'

#---------------------------------------------------------------------
# HTTP Ingress (80)
#---------------------------------------------------------------------
frontend http_frontend
    bind *:80
    mode tcp
    option tcplog
    default_backend http_backend

backend http_backend
    mode tcp
    balance roundrobin
EOF

    # Ajout des workers
    local worker_count=$(yq e '.nodes.workers | length' "$CONFIG_FILE")
    for ((i=0; i<worker_count; i++)); do
        local worker_name=$(yq e ".nodes.workers[$i].hostname" "$CONFIG_FILE" | cut -d'.' -f1)
        local worker_ip=$(yq e ".nodes.workers[$i].ip" "$CONFIG_FILE")
        echo "    server ${worker_name} ${worker_ip}:80 check" >> /etc/haproxy/haproxy.cfg
    done
    
    # HTTPS Ingress
    cat >> /etc/haproxy/haproxy.cfg << 'EOF'

#---------------------------------------------------------------------
# HTTPS Ingress (443)
#---------------------------------------------------------------------
frontend https_frontend
    bind *:443
    mode tcp
    option tcplog
    default_backend https_backend

backend https_backend
    mode tcp
    balance roundrobin
    option ssl-hello-chk
EOF

    for ((i=0; i<worker_count; i++)); do
        local worker_name=$(yq e ".nodes.workers[$i].hostname" "$CONFIG_FILE" | cut -d'.' -f1)
        local worker_ip=$(yq e ".nodes.workers[$i].ip" "$CONFIG_FILE")
        echo "    server ${worker_name} ${worker_ip}:443 check" >> /etc/haproxy/haproxy.cfg
    done
    
    # Validation et activation
    haproxy -c -f /etc/haproxy/haproxy.cfg
    
    # SELinux pour HAProxy
    setsebool -P haproxy_connect_any 1 2>/dev/null || true
    
    systemctl enable haproxy
    systemctl restart haproxy
    
    log SUCCESS "HAProxy configuré et démarré"
    log INFO "Stats disponibles sur http://${bastion_ip}:9000/stats"
}

# Fonction pour retirer le bootstrap après installation
remove_bootstrap_from_haproxy() {
    log INFO "Retrait du bootstrap de HAProxy..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "[DRY-RUN] Retrait du bootstrap"
        return
    fi
    
    # Commenter les lignes bootstrap
    sed -i 's/^\([[:space:]]*server bootstrap.*\)$/#\1 # Removed after installation/' /etc/haproxy/haproxy.cfg
    
    # Recharger HAProxy
    systemctl reload haproxy
    
    log SUCCESS "Bootstrap retiré de HAProxy"
}
