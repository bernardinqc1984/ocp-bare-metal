#!/bin/bash
#===============================================================================
# Module: configure_http.sh
# Description: Configuration du serveur HTTP Apache
#===============================================================================

configure_http_server() {
    log INFO "Configuration du serveur HTTP..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "[DRY-RUN] Configuration HTTP"
        return
    fi
    
    local bastion_ip=$(yq e '.nodes.bastion.ip' "$CONFIG_FILE")
    
    # Configuration Apache pour écouter sur le port 8080
    cat > /etc/httpd/conf.d/openshift.conf << EOF
# Configuration Apache pour OpenShift Installation
# Port 8080 pour les fichiers d'installation

Listen 8080

<VirtualHost *:8080>
    ServerName ${bastion_ip}
    DocumentRoot /var/www/html
    
    <Directory /var/www/html>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
    
    <Directory /var/www/html/ignition>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
    
    <Directory /var/www/html/rhcos>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
    
    # Logging
    ErrorLog logs/openshift_error_log
    CustomLog logs/openshift_access_log combined
</VirtualHost>
EOF
    
    # Création des répertoires
    mkdir -p /var/www/html/{rhcos,ignition}
    
    # Permissions
    chmod -R 755 /var/www/html/
    chown -R apache:apache /var/www/html/
    restorecon -RFv /var/www/html/
    
    # Test de la configuration
    httpd -t
    
    # Activation du service
    systemctl enable httpd
    systemctl restart httpd
    
    log SUCCESS "Serveur HTTP configuré et démarré sur le port 8080"
}
