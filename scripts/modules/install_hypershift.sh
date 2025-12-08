#!/bin/bash
#===============================================================================
# Module: install_hypershift.sh
# Description: Installation et configuration de HyperShift
#===============================================================================

install_hypershift_operator() {
    log INFO "Installation de l'opérateur HyperShift..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "[DRY-RUN] Installation opérateur HyperShift"
        return
    fi
    
    export KUBECONFIG="${WORK_DIR}/install/auth/kubeconfig"
    
    # Création du namespace
    cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: hypershift
  labels:
    openshift.io/cluster-monitoring: "true"
EOF

    # Création de l'OperatorGroup
    cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: hypershift-operator-group
  namespace: hypershift
spec:
  targetNamespaces:
  - hypershift
EOF

    # Souscription à l'opérateur
    cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: hypershift-operator
  namespace: hypershift
spec:
  channel: stable
  name: hypershift-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

    # Attente de l'installation
    log INFO "Attente de l'installation de l'opérateur..."
    local retries=30
    while [[ $retries -gt 0 ]]; do
        local csv_status=$(oc get csv -n hypershift -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Pending")
        if [[ "$csv_status" == "Succeeded" ]]; then
            log SUCCESS "Opérateur HyperShift installé avec succès"
            break
        fi
        log DEBUG "Status: $csv_status - Attente..."
        sleep 10
        ((retries--))
    done
    
    if [[ $retries -eq 0 ]]; then
        log WARN "Timeout lors de l'installation de l'opérateur. Vérifiez manuellement."
    fi
    
    # Vérification des CRDs
    log DEBUG "Vérification des CRDs HyperShift..."
    oc get crd | grep hypershift
    
    log SUCCESS "Installation de l'opérateur HyperShift terminée"
}

configure_agent_service() {
    log INFO "Configuration de l'Agent Service..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "[DRY-RUN] Configuration Agent Service"
        return
    fi
    
    export KUBECONFIG="${WORK_DIR}/install/auth/kubeconfig"
    
    local storage_class=$(yq e '.hypershift.storageClass // "lvms-vg1"' "$CONFIG_FILE")
    
    # Création du namespace multicluster-engine si nécessaire
    oc create namespace multicluster-engine --dry-run=client -o yaml | oc apply -f -
    
    # Configuration de l'Agent Service
    cat <<EOF | oc apply -f -
apiVersion: agent-install.openshift.io/v1beta1
kind: AgentServiceConfig
metadata:
  name: agent
  namespace: multicluster-engine
spec:
  databaseStorage:
    storageClassName: ${storage_class}
    accessModes:
    - ReadWriteOnce
    resources:
      requests:
        storage: 20Gi
  filesystemStorage:
    storageClassName: ${storage_class}
    accessModes:
    - ReadWriteOnce
    resources:
      requests:
        storage: 20Gi
  imageStorage:
    storageClassName: ${storage_class}
    accessModes:
    - ReadWriteOnce
    resources:
      requests:
        storage: 50Gi
  osImages:
  - openshiftVersion: "${OPENSHIFT_VERSION}"
    version: "417.94.202401091943-0"
    url: "https://mirror.openshift.com/pub/openshift-v4/x86_64/dependencies/rhcos/${OPENSHIFT_VERSION}/${OPENSHIFT_VERSION}.0/rhcos-${OPENSHIFT_VERSION}.0-x86_64-live.x86_64.iso"
    cpuArchitecture: x86_64
EOF

    # Attente que l'Agent Service soit prêt
    log INFO "Attente de l'Agent Service..."
    sleep 30
    
    oc get agentserviceconfig -n multicluster-engine
    oc get pods -n multicluster-engine
    
    log SUCCESS "Agent Service configuré"
}

install_hypershift_cli() {
    log INFO "Installation du CLI HyperShift..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "[DRY-RUN] Installation CLI HyperShift"
        return
    fi
    
    cd "$WORK_DIR"
    
    # Téléchargement depuis GitHub
    local hypershift_version=$(yq e '.hypershift.cliVersion // "latest"' "$CONFIG_FILE")
    
    if [[ "$hypershift_version" == "latest" ]]; then
        wget -q --show-progress \
            "https://github.com/openshift/hypershift/releases/latest/download/hypershift-linux-amd64" \
            -O hypershift
    else
        wget -q --show-progress \
            "https://github.com/openshift/hypershift/releases/download/${hypershift_version}/hypershift-linux-amd64" \
            -O hypershift
    fi
    
    chmod +x hypershift
    mv hypershift /usr/local/bin/
    
    # Vérification
    hypershift version
    
    log SUCCESS "CLI HyperShift installé"
}
