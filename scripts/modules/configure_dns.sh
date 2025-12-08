#!/bin/bash
#===============================================================================
# Module: configure_dns.sh
# Description: Configuration du serveur DNS BIND (optionnel)
#===============================================================================

configure_dns_server() {
    local use_internal_dns=$(yq e '.network.dns.useInternal // false' "$CONFIG_FILE")
    
    if [[ "$use_internal_dns" != "true" ]]; then
        log INFO "DNS interne désactivé - utilisation d'un DNS externe"
        return
    fi
    
    log INFO "Configuration du serveur DNS BIND..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "[DRY-RUN] Configuration DNS"
        return
    fi
    
    local cluster_name=$(yq e '.cluster.name' "$CONFIG_FILE")
    local base_domain=$(yq e '.cluster.baseDomain' "$CONFIG_FILE")
    local full_domain="${cluster_name}.${base_domain}"
    local bastion_ip=$(yq e '.nodes.bastion.ip' "$CONFIG_FILE")
    local api_vip=$(yq e '.network.vips.api' "$CONFIG_FILE")
    local ingress_vip=$(yq e '.network.vips.ingress' "$CONFIG_FILE")
    
    # Configuration principale de BIND
    cat > /etc/named.conf << EOF
options {
    listen-on port 53 { any; };
    listen-on-v6 port 53 { any; };
    directory       "/var/named";
    dump-file       "/var/named/data/cache_dump.db";
    statistics-file "/var/named/data/named_stats.txt";
    memstatistics-file "/var/named/data/named_mem_stats.txt";
    secroots-file   "/var/named/data/named.secroots";
    recursing-file  "/var/named/data/named.recursing";
    allow-query     { any; };
    recursion yes;
    
    dnssec-validation no;
    
    forwarders {
        8.8.8.8;
        8.8.4.4;
    };
};

logging {
    channel default_debug {
        file "data/named.run";
        severity dynamic;
    };
};

zone "." IN {
    type hint;
    file "named.ca";
};

include "/etc/named.rfc1912.zones";
include "/etc/named.root.key";

# Zone OpenShift
zone "${full_domain}" IN {
    type master;
    file "/var/named/${full_domain}.zone";
    allow-update { none; };
};

# Zone reverse
zone "1.168.192.in-addr.arpa" IN {
    type master;
    file "/var/named/1.168.192.rev";
    allow-update { none; };
};
EOF

    # Fichier de zone forward
    cat > "/var/named/${full_domain}.zone" << EOF
\$TTL 1D
@   IN SOA  bastion.${full_domain}. admin.${full_domain}. (
                    $(date +%Y%m%d)01 ; serial
                    1D              ; refresh
                    1H              ; retry
                    1W              ; expire
                    3H )            ; minimum
    IN  NS      bastion.${full_domain}.

; API et Ingress VIPs
api                     IN  A   ${api_vip}
api-int                 IN  A   ${api_vip}
*.apps                  IN  A   ${ingress_vip}

; Nœuds
bastion                 IN  A   ${bastion_ip}
EOF

    # Ajout du bootstrap
    local bootstrap_ip=$(yq e '.nodes.bootstrap.ip' "$CONFIG_FILE")
    echo "bootstrap               IN  A   ${bootstrap_ip}" >> "/var/named/${full_domain}.zone"
    
    # Ajout des masters
    local master_count=$(yq e '.nodes.masters | length' "$CONFIG_FILE")
    for ((i=0; i<master_count; i++)); do
        local master_name=$(yq e ".nodes.masters[$i].hostname" "$CONFIG_FILE" | cut -d'.' -f1)
        local master_ip=$(yq e ".nodes.masters[$i].ip" "$CONFIG_FILE")
        echo "${master_name}               IN  A   ${master_ip}" >> "/var/named/${full_domain}.zone"
    done
    
    # Ajout des workers
    local worker_count=$(yq e '.nodes.workers | length' "$CONFIG_FILE")
    for ((i=0; i<worker_count; i++)); do
        local worker_name=$(yq e ".nodes.workers[$i].hostname" "$CONFIG_FILE" | cut -d'.' -f1)
        local worker_ip=$(yq e ".nodes.workers[$i].ip" "$CONFIG_FILE")
        echo "${worker_name}               IN  A   ${worker_ip}" >> "/var/named/${full_domain}.zone"
    done
    
    # Enregistrements SRV pour etcd
    echo "" >> "/var/named/${full_domain}.zone"
    echo "; etcd SRV records" >> "/var/named/${full_domain}.zone"
    for ((i=0; i<master_count; i++)); do
        local master_name=$(yq e ".nodes.masters[$i].hostname" "$CONFIG_FILE" | cut -d'.' -f1)
        echo "_etcd-server-ssl._tcp   IN  SRV 0 10 2380 ${master_name}.${full_domain}." >> "/var/named/${full_domain}.zone"
    done
    
    # Fichier de zone reverse
    cat > "/var/named/1.168.192.rev" << EOF
\$TTL 1D
@   IN SOA  bastion.${full_domain}. admin.${full_domain}. (
                    $(date +%Y%m%d)01 ; serial
                    1D              ; refresh
                    1H              ; retry
                    1W              ; expire
                    3H )            ; minimum
    IN  NS      bastion.${full_domain}.

; PTR Records
$(echo ${api_vip} | cut -d'.' -f4)     IN  PTR api.${full_domain}.
$(echo ${bastion_ip} | cut -d'.' -f4)  IN  PTR bastion.${full_domain}.
$(echo ${bootstrap_ip} | cut -d'.' -f4) IN  PTR bootstrap.${full_domain}.
EOF

    # Ajout des PTR pour masters
    for ((i=0; i<master_count; i++)); do
        local master_name=$(yq e ".nodes.masters[$i].hostname" "$CONFIG_FILE" | cut -d'.' -f1)
        local master_ip=$(yq e ".nodes.masters[$i].ip" "$CONFIG_FILE")
        echo "$(echo ${master_ip} | cut -d'.' -f4)  IN  PTR ${master_name}.${full_domain}." >> "/var/named/1.168.192.rev"
    done
    
    # Permissions
    chown root:named /var/named/*.zone /var/named/*.rev
    chmod 640 /var/named/*.zone /var/named/*.rev
    
    # Validation
    named-checkconf
    named-checkzone "${full_domain}" "/var/named/${full_domain}.zone"
    
    # Activation
    systemctl enable named
    systemctl restart named
    
    log SUCCESS "Serveur DNS configuré et démarré"
}
