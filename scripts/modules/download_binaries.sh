#!/bin/bash
#===============================================================================
# Module: download_binaries.sh
# Description: Téléchargement des binaires OpenShift
#===============================================================================

download_openshift_binaries() {
    local version="${OPENSHIFT_VERSION:-stable}"
    local base_url="https://mirror.openshift.com/pub/openshift-v4/clients/ocp"
    
    log INFO "Téléchargement des binaires OpenShift ${version}..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "[DRY-RUN] Téléchargement depuis ${base_url}/${version}/"
        return
    fi
    
    cd "$WORK_DIR"
    
    # Téléchargement de l'installer
    log DEBUG "Téléchargement de openshift-install..."
    wget -q --show-progress \
        "${base_url}/stable-${version}/openshift-install-linux.tar.gz" \
        -O openshift-install-linux.tar.gz
    
    # Téléchargement du client
    log DEBUG "Téléchargement de oc client..."
    wget -q --show-progress \
        "${base_url}/stable-${version}/openshift-client-linux.tar.gz" \
        -O openshift-client-linux.tar.gz
    
    # Extraction
    log DEBUG "Extraction des archives..."
    tar xzf openshift-install-linux.tar.gz
    tar xzf openshift-client-linux.tar.gz
    
    # Installation
    mv -f openshift-install oc kubectl /usr/local/bin/
    chmod +x /usr/local/bin/openshift-install /usr/local/bin/oc /usr/local/bin/kubectl
    
    # Cleanup
    rm -f openshift-install-linux.tar.gz openshift-client-linux.tar.gz README.md
    
    # Vérification
    log DEBUG "Versions installées:"
    openshift-install version
    oc version --client
    
    log SUCCESS "Binaires OpenShift installés"
}
