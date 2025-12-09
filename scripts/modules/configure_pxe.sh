#!/bin/bash
#===============================================================================






































































































































































































































































































































































































































































































































































































































































main "$@"}    fi        log INFO "Utilisez 'oc get pods -n <namespace> -o wide' pour vérifier."        log INFO "Note: La migration des pods peut prendre quelques minutes."    if [[ "$DRY_RUN" != "true" ]]; then        echo ""    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════╝${NC}"    echo -e "${GREEN}║                                                                   ║${NC}"    echo -e "${GREEN}║   ✓ CONFIGURATION DES NŒUDS INFRA TERMINÉE                       ║${NC}"    echo -e "${GREEN}║                                                                   ║${NC}"    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════╗${NC}"    echo ""        fi        generate_report                fi            verify_migration        if [[ "$SKIP_MIGRATION" != "true" ]]; then                verify_nodes        echo ""    if [[ "$DRY_RUN" != "true" ]]; then    # Vérification        fi        log WARN "Migration des composants ignorée (--skip-migration)"    else        migrate_monitoring        log INFO "═══ ÉTAPE 5/5: MIGRATION DU MONITORING ═══"        echo ""                migrate_registry        log INFO "═══ ÉTAPE 4/5: MIGRATION DU REGISTRY ═══"        echo ""                migrate_router        log INFO "═══ ÉTAPE 3/5: MIGRATION DU ROUTER ═══"        echo ""    if [[ "$SKIP_MIGRATION" != "true" ]]; then    # Étape 3: Migration des composants        taint_infra_nodes "${infra_nodes[@]}"    log INFO "═══ ÉTAPE 2/5: APPLICATION DES TAINTS ═══"    echo ""    # Étape 2: Appliquer les taints        label_infra_nodes "${infra_nodes[@]}"    log INFO "═══ ÉTAPE 1/5: APPLICATION DES LABELS ═══"    echo ""    # Étape 1: Appliquer les labels        fi        fi            exit 0            log WARN "Opération annulée par l'utilisateur"        if [[ ! $REPLY =~ ^[Yy]$ ]]; then        echo        read -p "Voulez-vous continuer? (y/N) " -n 1 -r    if [[ "$DRY_RUN" != "true" ]]; then        echo ""    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"    echo -e "${CYAN}  NŒUDS À CONFIGURER: ${infra_nodes[*]}${NC}"    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"    echo ""        fi        exit 1        log ERROR "Aucun nœud infra à configurer"    if [[ ${#infra_nodes[@]} -eq 0 ]]; then        read -ra infra_nodes <<< "$(get_infra_nodes)"    local infra_nodes    # Obtenir la liste des nœuds infra        check_prerequisites    # Vérifications préalables        fi        echo ""        echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════╝${NC}"        echo -e "${YELLOW}║          Aucune modification ne sera effectuée                ║${NC}"        echo -e "${YELLOW}║              MODE SIMULATION (DRY-RUN) ACTIVÉ                 ║${NC}"        echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════╗${NC}"    if [[ "$DRY_RUN" == "true" ]]; then        print_banner        mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true    # Créer le répertoire de logs        parse_args "$@"main() {#-------------------------------------------------------------------------------# Main#-------------------------------------------------------------------------------}    done        esac                ;;                exit 1                usage                log ERROR "Option inconnue: $1"            *)                ;;                exit 0                usage            -h|--help)                ;;                shift                VERBOSE=true            -v|--verbose)                ;;                shift                SKIP_MIGRATION=true            -s|--skip-migration)                ;;                shift                DRY_RUN=true            -n|--dry-run)                ;;                shift 2                KUBECONFIG="$2"            -k|--kubeconfig)                ;;                shift 2                CONFIG_FILE="$2"            -c|--config)        case $1 in    while [[ $# -gt 0 ]]; doparse_args() {#-------------------------------------------------------------------------------# Parsing des arguments#-------------------------------------------------------------------------------}    log SUCCESS "Rapport généré: $report_file"        } > "$report_file" 2>/dev/null || true        echo ""        oc get configmap cluster-monitoring-config -n openshift-monitoring -o yaml 2>/dev/null || echo "Non configuré"        echo "------------------"        echo "MONITORING CONFIG:"        echo ""        oc get configs.imageregistry.operator.openshift.io/cluster -o yaml | grep -A 10 "nodeSelector:"        echo "----------------"        echo "REGISTRY STATUS:"        echo ""        oc get ingresscontroller/default -n openshift-ingress-operator -o yaml | grep -A 20 "nodePlacement:"        echo "--------------"        echo "ROUTER STATUS:"        echo ""        oc get nodes -l "${INFRA_LABEL}" -o jsonpath='{range .items[*]}{.metadata.name}{": "}{.spec.taints}{"\n"}{end}'        echo "-------"        echo "TAINTS:"        echo ""        oc get nodes -l "${INFRA_LABEL}" -o wide        echo "------------"        echo "NŒUDS INFRA:"        echo ""        echo "═══════════════════════════════════════════════════════════════════"        echo "            $(date)"        echo "            RAPPORT DE CONFIGURATION DES NŒUDS INFRA"        echo "═══════════════════════════════════════════════════════════════════"    {        log INFO "Génération du rapport de configuration..."        local report_file="/var/log/openshift-install/infra-nodes-report-$(date +%Y%m%d-%H%M%S).txt"generate_report() {# Génère un rapport de configuration}    echo ""        oc get pods -n openshift-monitoring -o wide | head -20    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"    echo -e "${CYAN}                    PODS MONITORING                                ${NC}"    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"    echo ""        oc get pods -n openshift-image-registry -o wide    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"    echo -e "${CYAN}                    PODS REGISTRY                                  ${NC}"    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"    echo ""        oc get pods -n openshift-ingress -o wide    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"    echo -e "${CYAN}                    PODS ROUTER (INGRESS)                          ${NC}"    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"    echo ""        log INFO "Vérification de la migration des composants..."verify_migration() {# Vérification des composants migrés}    echo ""        oc get nodes -l "${INFRA_LABEL}" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.taints}{"\n"}{end}'    # Afficher les taints        echo ""    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"    echo -e "${CYAN}                    TAINTS DES NŒUDS INFRA                         ${NC}"    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"    echo ""        oc get nodes -l "${INFRA_LABEL}" -o wide    # Afficher les nœuds infra        echo ""    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"    echo -e "${CYAN}                    ÉTAT DES NŒUDS INFRA                           ${NC}"    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"    echo ""        log INFO "Vérification de l'état des nœuds infra..."verify_nodes() {# Vérification de l'état des nœuds}    fi        fi            log ERROR "Échec de la migration du Monitoring"        else            log SUCCESS "Monitoring migré vers les nœuds infra"        if [[ $? -eq 0 ]]; then        echo "$config_yaml" | oc apply -f -    else        echo "$config_yaml"        log DEBUG "[DRY-RUN] Apply ConfigMap cluster-monitoring-config:"    if [[ "$DRY_RUN" == "true" ]]; then    )CONFIGYAML        effect: "NoSchedule"        operator: "Exists"      - key: "node-role.kubernetes.io/infra"      tolerations:        node-role.kubernetes.io/infra: ""      nodeSelector:    thanosQuerier:        effect: "NoSchedule"        operator: "Exists"      - key: "node-role.kubernetes.io/infra"      tolerations:        node-role.kubernetes.io/infra: ""      nodeSelector:    openshiftStateMetrics:        effect: "NoSchedule"        operator: "Exists"      - key: "node-role.kubernetes.io/infra"      tolerations:        node-role.kubernetes.io/infra: ""      nodeSelector:    telemeterClient:        effect: "NoSchedule"        operator: "Exists"      - key: "node-role.kubernetes.io/infra"      tolerations:        node-role.kubernetes.io/infra: ""      nodeSelector:    kubeStateMetrics:        effect: "NoSchedule"        operator: "Exists"      - key: "node-role.kubernetes.io/infra"      tolerations:        node-role.kubernetes.io/infra: ""      nodeSelector:    k8sPrometheusAdapter:        effect: "NoSchedule"        operator: "Exists"      - key: "node-role.kubernetes.io/infra"      tolerations:        node-role.kubernetes.io/infra: ""      nodeSelector:    grafana:        effect: "NoSchedule"        operator: "Exists"      - key: "node-role.kubernetes.io/infra"      tolerations:        node-role.kubernetes.io/infra: ""      nodeSelector:    prometheusOperator:        effect: "NoSchedule"        operator: "Exists"      - key: "node-role.kubernetes.io/infra"      tolerations:        node-role.kubernetes.io/infra: ""      nodeSelector:    prometheusK8s:        effect: "NoSchedule"        operator: "Exists"      - key: "node-role.kubernetes.io/infra"      tolerations:        node-role.kubernetes.io/infra: ""      nodeSelector:    alertmanagerMain:  config.yaml: |data:  namespace: openshift-monitoring  name: cluster-monitoring-configmetadata:kind: ConfigMapapiVersion: v1    local config_yaml=$(cat << 'CONFIGYAML'    # Créer le ConfigMap de configuration du monitoring        log INFO "Migration du Monitoring vers les nœuds infra..."migrate_monitoring() {# Migration du Monitoring}    fi        fi            log ERROR "Échec de la migration du Registry"        else            log SUCCESS "Registry migré vers les nœuds infra"        if oc patch configs.imageregistry.operator.openshift.io/cluster --type=merge -p "$patch"; then    else        echo "$patch"        log DEBUG "[DRY-RUN] Patch configs.imageregistry.operator.openshift.io/cluster:"    if [[ "$DRY_RUN" == "true" ]]; then    )PATCH  replicas: 3    effect: "NoSchedule"    operator: "Exists"  - key: "node-role.kubernetes.io/infra"  tolerations:    node-role.kubernetes.io/infra: ""  nodeSelector:spec:    local patch=$(cat << 'PATCH'        log INFO "Migration du Registry vers les nœuds infra..."migrate_registry() {# Migration du Registry}    fi        fi            log ERROR "Échec de la migration du Router"        else            log SUCCESS "Router migré vers les nœuds infra"        if oc patch ingresscontroller/default -n openshift-ingress-operator --type=merge -p "$patch"; then    else        echo "$patch"        log DEBUG "[DRY-RUN] Patch IngressController/default:"    if [[ "$DRY_RUN" == "true" ]]; then    )PATCH  replicas: 3      effect: "NoSchedule"      operator: "Exists"    - key: "node-role.kubernetes.io/infra"    tolerations:        node-role.kubernetes.io/infra: ""      matchLabels:    nodeSelector:  nodePlacement:spec:    local patch=$(cat << 'PATCH'        log INFO "Migration du Router vers les nœuds infra..."migrate_router() {# Migration du Router (Ingress Controller)}    done        fi            fi                log DEBUG "Pas de label worker sur: $node"            else                log SUCCESS "Label worker retiré: $node"            if oc label node "$node" "node-role.kubernetes.io/worker-" 2>/dev/null; then        else            log DEBUG "[DRY-RUN] oc label node $node node-role.kubernetes.io/worker-"        if [[ "$DRY_RUN" == "true" ]]; then                fi            continue        if [[ -z "$node" ]]; then    for node in "${nodes[@]}"; do        log INFO "Retrait du label 'worker' des nœuds infra (optionnel)..."        local nodes=("$@")remove_worker_label() {# Retire le label worker des nœuds infra (optionnel)}    done        fi            fi                log ERROR "Échec du taint: $node"            else                log SUCCESS "Taint appliqué: $node"            if oc adm taint node "$node" "${INFRA_TAINT_KEY}:${INFRA_TAINT_EFFECT}"; then                        oc adm taint node "$node" "${INFRA_TAINT_KEY}-" 2>/dev/null || true            # Supprimer l'ancien taint s'il existe, puis appliquer le nouveau        else            log DEBUG "[DRY-RUN] oc adm taint node $node ${INFRA_TAINT_KEY}:${INFRA_TAINT_EFFECT}"        if [[ "$DRY_RUN" == "true" ]]; then                log DEBUG "Tainting node: $node"                fi            continue        if [[ -z "$node" ]]; then    for node in "${nodes[@]}"; do        log INFO "Application du taint '${INFRA_TAINT_KEY}:${INFRA_TAINT_EFFECT}' aux nœuds..."        local nodes=("$@")taint_infra_nodes() {# Applique le taint aux nœuds infra}    done        fi            fi                log ERROR "Échec du labeling: $node"            else                log SUCCESS "Label appliqué: $node"            if oc label node "$node" "${INFRA_LABEL}=" --overwrite; then        else            log DEBUG "[DRY-RUN] oc label node $node ${INFRA_LABEL}="        if [[ "$DRY_RUN" == "true" ]]; then                log DEBUG "Labeling node: $node"                fi            continue        if [[ -z "$node" ]]; then    for node in "${nodes[@]}"; do        log INFO "Application du label '${INFRA_LABEL}' aux nœuds..."        local nodes=("$@")label_infra_nodes() {# Applique le label infra aux nœuds}    fi        exit 1        log ERROR "Aucun worker disponible pour la conversion en infra"    else        echo "$user_nodes"        read -r -p "> " user_nodes        echo "Exemple: worker-0 worker-1 worker-2"        echo "Entrez les noms des nœuds à configurer comme infra (séparés par des espaces):"        echo ""        log INFO "Workers disponibles: $workers"    if [[ -n "$workers" ]]; then        local workers=$(oc get nodes -l 'node-role.kubernetes.io/worker,!node-role.kubernetes.io/infra' -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)    # Lister les workers sans le label infra        log INFO "Recherche des nœuds worker pouvant être convertis en infra..."    log WARN "Aucun nœud infra défini dans la configuration"    # Fallback: demander à l'utilisateur ou utiliser un pattern        fi        fi            return            echo "${nodes[@]}"            log INFO "Nœuds infra détectés depuis la config: ${nodes[*]}"            done                nodes+=("$nodename")                local nodename="${hostname%%.*}"                # Extraire le nom court du nœud                local hostname=$(yq e ".nodes.infras[$i].hostname" "$CONFIG_FILE")            for ((i=0; i<count; i++)); do        if [[ "$count" -gt 0 && "$count" != "null" ]]; then        local count=$(yq e '.nodes.infras | length' "$CONFIG_FILE" 2>/dev/null || echo "0")    if [[ -f "$CONFIG_FILE" ]] && command -v yq &> /dev/null; then    # Essayer de lire depuis le fichier de configuration        local nodes=()get_infra_nodes() {# Détecte les nœuds infra depuis le fichier de config ou depuis le cluster#-------------------------------------------------------------------------------# Fonctions principales#-------------------------------------------------------------------------------}    fi        log WARN "yq non disponible - détection automatique des nœuds désactivée"    if [[ -f "$CONFIG_FILE" ]] && ! command -v yq &> /dev/null; then    # Vérifier yq (si fichier config utilisé)        log SUCCESS "Connecté au cluster en tant que: $cluster_user"    local cluster_user=$(oc whoami)        fi        exit 1        log ERROR "Impossible de se connecter au cluster OpenShift"    if ! oc whoami &> /dev/null; then    # Vérifier la connexion au cluster        export KUBECONFIG        fi        exit 1        log ERROR "Fichier kubeconfig non trouvé: $KUBECONFIG"    if [[ ! -f "$KUBECONFIG" ]]; then    # Vérifier le kubeconfig        fi        exit 1        log ERROR "La commande 'oc' n'est pas disponible"    if ! command -v oc &> /dev/null; then    # Vérifier oc        log INFO "Vérification des prérequis..."check_prerequisites() {}EOF    - Monitoring Stack (Prometheus, Alertmanager, Grafana)    - OpenShift Internal Registry    - OpenShift Router (Ingress Controller)COMPOSANTS MIGRÉS:    $(basename "$0") --kubeconfig ~/.kube/config    # Avec kubeconfig personnalisé    $(basename "$0") --skip-migration    # Seulement labels et taints (sans migration)    $(basename "$0") --dry-run --verbose    # Mode dry-run pour tester    $(basename "$0")    # Configuration complèteEXEMPLES:    -h, --help              Afficher cette aide    -v, --verbose           Mode verbeux    -s, --skip-migration    Ignorer la migration des composants    -n, --dry-run           Mode simulation (aucune modification)    -k, --kubeconfig <file> Fichier kubeconfig (défaut: /opt/openshift/install/auth/kubeconfig)    -c, --config <file>     Fichier de configuration (défaut: ../config/cluster-config.yaml)OPTIONS:Configure les nœuds Infrastructure OpenShift avec labels, taints et migration des composants.Usage: $(basename "$0") [OPTIONS]    cat << EOFusage() {}    echo -e "${NC}"EOF╚═══════════════════════════════════════════════════════════════════════════════╝║                                                                               ║║           Labels, Taints & Component Migration                                ║║           INFRASTRUCTURE NODES CONFIGURATION                                   ║║                                                                               ║║   ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝╚═╝╚═╝        ╚═╝         ║║  ╚██████╔╝██║     ███████╗██║ ╚████║███████║██║  ██║██║██║        ██║         ║║  ██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║╚════██║██╔══██║██║██╔══╝     ██║         ║║  ██║   ██║██████╔╝█████╗  ██╔██╗ ██║███████╗███████║██║█████╗     ██║         ║║  ██╔═══██╗██╔══██╗██╔════╝████╗  ██║██╔════╝██║  ██║██║██╔════╝╚══██╔══╝      ║║   ██████╗ ██████╗ ███████╗███╗   ██╗███████╗██╗  ██╗██╗███████╗████████╗      ║║                                                                               ║╔═══════════════════════════════════════════════════════════════════════════════╗    cat << 'EOF'    echo -e "${CYAN}"print_banner() {}    echo "${timestamp} [$level] $message" >> "$LOG_FILE" 2>/dev/null || true        esac        DEBUG)   [[ "$VERBOSE" == "true" ]] && echo -e "${CYAN}[DEBUG]${NC} ${timestamp} - $message" ;;        ERROR)   echo -e "${RED}[✗]${NC} ${timestamp} - $message" ;;        WARN)    echo -e "${YELLOW}[WARN]${NC} ${timestamp} - $message" ;;        SUCCESS) echo -e "${GREEN}[✓]${NC} ${timestamp} - $message" ;;        INFO)    echo -e "${BLUE}[INFO]${NC} ${timestamp} - $message" ;;    case "$level" in        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')    local message="$*"    shift    local level="$1"log() {#-------------------------------------------------------------------------------# Fonctions utilitaires#-------------------------------------------------------------------------------NC='\033[0m' # No ColorCYAN='\033[0;36m'BLUE='\033[0;34m'YELLOW='\033[1;33m'GREEN='\033[0;32m'RED='\033[0;31m'# CouleursINFRA_TAINT_EFFECT="NoSchedule"INFRA_TAINT_KEY="node-role.kubernetes.io/infra"INFRA_LABEL="node-role.kubernetes.io/infra"# Labels et TaintsKUBECONFIG="${KUBECONFIG:-/opt/openshift/install/auth/kubeconfig}"SKIP_MIGRATION=falseVERBOSE=falseDRY_RUN=falseLOG_FILE="/var/log/openshift-install/configure-infra-$(date +%Y%m%d-%H%M%S).log"CONFIG_FILE="${SCRIPT_DIR}/../config/cluster-config.yaml"SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"#-------------------------------------------------------------------------------# Variables globales#-------------------------------------------------------------------------------set -euo pipefail#===============================================================================##       CREATED: $(date +%Y-%m-%d)#       VERSION: 1.0#        AUTHOR: Infrastructure Team#       OPTIONS: Voir section OPTIONS ci-dessous##                (Router, Registry, Monitoring) vers ces nœuds.#                et taints appropriés, puis migre les composants d'infrastructure#   DESCRIPTION: Configure les nœuds Infrastructure OpenShift avec les labels##         USAGE: ./configure-infra-nodes.sh [OPTIONS]##          FILE: configure-infra-nodes.sh## Module: configure_pxe.sh
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

LABEL infra
    MENU LABEL ^5) Install OpenShift Infra Node
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

menuentry 'Install OpenShift Infra Node' {
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
    
    # Infra nodes (utilisent le même ignition que les workers)
    local infra_count=$(yq e '.nodes.infras | length' "$CONFIG_FILE" 2>/dev/null || echo "0")
    if [[ "$infra_count" -gt 0 && "$infra_count" != "null" ]]; then
        for ((i=0; i<infra_count; i++)); do
            local infra_mac=$(yq e ".nodes.infras[$i].mac" "$CONFIG_FILE" | tr ':' '-' | tr '[:upper:]' '[:lower:]')
            cat > "/var/lib/tftpboot/pxelinux.cfg/01-${infra_mac}" << EOF
DEFAULT infra
LABEL infra
    KERNEL http://${bastion_ip}:8080/rhcos/rhcos-kernel
    APPEND initrd=http://${bastion_ip}:8080/rhcos/rhcos-initramfs.img coreos.live.rootfs_url=http://${bastion_ip}:8080/rhcos/rhcos-rootfs.img coreos.inst.install_dev=/dev/sda coreos.inst.ignition_url=http://${bastion_ip}:8080/ignition/worker.ign ip=dhcp rd.neednet=1
EOF
        done
    fi
    
    restorecon -RFv /var/lib/tftpboot/pxelinux.cfg/
    
    log SUCCESS "Configuration PXE par hôte terminée"
}
