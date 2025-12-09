#!/bin/bash
#===============================================================================
#
#          FILE: configure-infra-nodes.sh
#
#         USAGE: ./configure-infra-nodes.sh [OPTIONS]
#
#   DESCRIPTION: Configure les nœuds Infrastructure OpenShift avec les labels
#                et taints appropriés, puis migre les composants d'infrastructure
#                (Router, Registry, Monitoring) vers ces nœuds.
#
#       OPTIONS: Voir section OPTIONS ci-dessous
#        AUTHOR: Infrastructure Team
#       VERSION: 1.0
#       CREATED: 2024
#
#===============================================================================

set -euo pipefail

#-------------------------------------------------------------------------------
# Variables globales
#-------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/cluster-config.yaml"
LOG_FILE="/var/log/openshift-install/configure-infra-$(date +%Y%m%d-%H%M%S).log"
DRY_RUN=false
VERBOSE=false
SKIP_MIGRATION=false
KUBECONFIG="${KUBECONFIG:-/opt/openshift/install/auth/kubeconfig}"

# Labels et Taints
INFRA_LABEL="node-role.kubernetes.io/infra"
INFRA_TAINT_KEY="node-role.kubernetes.io/infra"
INFRA_TAINT_EFFECT="NoSchedule"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

#-------------------------------------------------------------------------------
# Fonctions utilitaires
#-------------------------------------------------------------------------------
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        INFO)    echo -e "${BLUE}[INFO]${NC} ${timestamp} - $message" ;;
        SUCCESS) echo -e "${GREEN}[✓]${NC} ${timestamp} - $message" ;;
        WARN)    echo -e "${YELLOW}[WARN]${NC} ${timestamp} - $message" ;;
        ERROR)   echo -e "${RED}[✗]${NC} ${timestamp} - $message" ;;
        DEBUG)   [[ "$VERBOSE" == "true" ]] && echo -e "${CYAN}[DEBUG]${NC} ${timestamp} - $message" ;;
    esac
    
    echo "${timestamp} [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
}

print_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════════════════╗
║                                                                               ║
║   ██████╗ ██████╗ ███████╗███╗   ██╗███████╗██╗  ██╗██╗███████╗████████╗      ║
║  ██╔═══██╗██╔══██╗██╔════╝████╗  ██║██╔════╝██║  ██║██║██╔════╝╚══██╔══╝      ║
║  ██║   ██║██████╔╝█████╗  ██╔██╗ ██║███████╗███████║██║█████╗     ██║         ║
║  ██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║╚════██║██╔══██║██║██╔══╝     ██║         ║
║  ╚██████╔╝██║     ███████╗██║ ╚████║███████║██║  ██║██║██║        ██║         ║
║   ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝╚═╝╚═╝        ╚═╝         ║
║                                                                               ║
║           INFRASTRUCTURE NODES CONFIGURATION                                   ║
║           Labels, Taints & Component Migration                                ║
║                                                                               ║
╚═══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Configure les nœuds Infrastructure OpenShift avec labels, taints et migration des composants.

OPTIONS:
    -c, --config <file>     Fichier de configuration (défaut: ../config/cluster-config.yaml)
    -k, --kubeconfig <file> Fichier kubeconfig (défaut: /opt/openshift/install/auth/kubeconfig)
    -n, --dry-run           Mode simulation (aucune modification)
    -s, --skip-migration    Ignorer la migration des composants
    -v, --verbose           Mode verbeux
    -h, --help              Afficher cette aide

EXEMPLES:
    # Configuration complète
    $(basename "$0")

    # Mode dry-run pour tester
    $(basename "$0") --dry-run --verbose

    # Seulement labels et taints (sans migration)
    $(basename "$0") --skip-migration

    # Avec kubeconfig personnalisé
    $(basename "$0") --kubeconfig ~/.kube/config

COMPOSANTS MIGRÉS:
    - OpenShift Router (Ingress Controller)
    - OpenShift Internal Registry
    - Monitoring Stack (Prometheus, Alertmanager, Grafana)

EOF
}

check_prerequisites() {
    log INFO "Vérification des prérequis..."
    
    # Vérifier oc
    if ! command -v oc &> /dev/null; then
        log ERROR "La commande 'oc' n'est pas disponible"
        exit 1
    fi
    
    # Vérifier le kubeconfig
    if [[ ! -f "$KUBECONFIG" ]]; then
        log ERROR "Fichier kubeconfig non trouvé: $KUBECONFIG"
        exit 1
    fi
    
    export KUBECONFIG
    
    # Vérifier la connexion au cluster
    if ! oc whoami &> /dev/null; then
        log ERROR "Impossible de se connecter au cluster OpenShift"
        exit 1
    fi
    
    local cluster_user=$(oc whoami)
    log SUCCESS "Connecté au cluster en tant que: $cluster_user"
    
    # Vérifier yq (si fichier config utilisé)
    if [[ -f "$CONFIG_FILE" ]] && ! command -v yq &> /dev/null; then
        log WARN "yq non disponible - détection automatique des nœuds désactivée"
    fi
}

#-------------------------------------------------------------------------------
# Fonctions principales
#-------------------------------------------------------------------------------

# Détecte les nœuds infra depuis le fichier de config ou depuis le cluster
get_infra_nodes() {
    local nodes=()
    
    # Essayer de lire depuis le fichier de configuration
    if [[ -f "$CONFIG_FILE" ]] && command -v yq &> /dev/null; then
        local count=$(yq e '.nodes.infras | length' "$CONFIG_FILE" 2>/dev/null || echo "0")
        if [[ "$count" -gt 0 && "$count" != "null" ]]; then
            for ((i=0; i<count; i++)); do
                local hostname=$(yq e ".nodes.infras[$i].hostname" "$CONFIG_FILE")
                # Extraire le nom court du nœud
                local nodename="${hostname%%.*}"
                nodes+=("$nodename")
            done
            log INFO "Nœuds infra détectés depuis la config: ${nodes[*]}"
            echo "${nodes[@]}"
            return
        fi
    fi
    
    # Fallback: demander à l'utilisateur ou utiliser un pattern
    log WARN "Aucun nœud infra défini dans la configuration"
    log INFO "Recherche des nœuds worker pouvant être convertis en infra..."
    
    # Lister les workers sans le label infra
    local workers=$(oc get nodes -l 'node-role.kubernetes.io/worker,!node-role.kubernetes.io/infra' -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    if [[ -n "$workers" ]]; then
        log INFO "Workers disponibles: $workers"
        echo ""
        echo "Entrez les noms des nœuds à configurer comme infra (séparés par des espaces):"
        echo "Exemple: worker-0 worker-1 worker-2"
        read -r -p "> " user_nodes
        echo "$user_nodes"
    else
        log ERROR "Aucun worker disponible pour la conversion en infra"
        exit 1
    fi
}

# Applique le label infra aux nœuds
label_infra_nodes() {
    local nodes=("$@")
    
    log INFO "Application du label '${INFRA_LABEL}' aux nœuds..."
    
    for node in "${nodes[@]}"; do
        if [[ -z "$node" ]]; then
            continue
        fi
        
        log DEBUG "Labeling node: $node"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log DEBUG "[DRY-RUN] oc label node $node ${INFRA_LABEL}="
        else
            if oc label node "$node" "${INFRA_LABEL}=" --overwrite; then
                log SUCCESS "Label appliqué: $node"
            else
                log ERROR "Échec du labeling: $node"
            fi
        fi
    done
}

# Applique le taint aux nœuds infra
taint_infra_nodes() {
    local nodes=("$@")
    
    log INFO "Application du taint '${INFRA_TAINT_KEY}:${INFRA_TAINT_EFFECT}' aux nœuds..."
    
    for node in "${nodes[@]}"; do
        if [[ -z "$node" ]]; then
            continue
        fi
        
        log DEBUG "Tainting node: $node"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log DEBUG "[DRY-RUN] oc adm taint node $node ${INFRA_TAINT_KEY}:${INFRA_TAINT_EFFECT}"
        else
            # Supprimer l'ancien taint s'il existe, puis appliquer le nouveau
            oc adm taint node "$node" "${INFRA_TAINT_KEY}-" 2>/dev/null || true
            
            if oc adm taint node "$node" "${INFRA_TAINT_KEY}:${INFRA_TAINT_EFFECT}"; then
                log SUCCESS "Taint appliqué: $node"
            else
                log ERROR "Échec du taint: $node"
            fi
        fi
    done
}

# Retire le label worker des nœuds infra (optionnel)
remove_worker_label() {
    local nodes=("$@")
    
    log INFO "Retrait du label 'worker' des nœuds infra (optionnel)..."
    
    for node in "${nodes[@]}"; do
        if [[ -z "$node" ]]; then
            continue
        fi
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log DEBUG "[DRY-RUN] oc label node $node node-role.kubernetes.io/worker-"
        else
            if oc label node "$node" "node-role.kubernetes.io/worker-" 2>/dev/null; then
                log SUCCESS "Label worker retiré: $node"
            else
                log DEBUG "Pas de label worker sur: $node"
            fi
        fi
    done
}

# Migration du Router (Ingress Controller)
migrate_router() {
    log INFO "Migration du Router vers les nœuds infra..."
    
    local patch=$(cat << 'PATCH'
spec:
  nodePlacement:
    nodeSelector:
      matchLabels:
        node-role.kubernetes.io/infra: ""
    tolerations:
    - key: "node-role.kubernetes.io/infra"
      operator: "Exists"
      effect: "NoSchedule"
  replicas: 3
PATCH
)
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "[DRY-RUN] Patch IngressController/default:"
        echo "$patch"
    else
        if oc patch ingresscontroller/default -n openshift-ingress-operator --type=merge -p "$patch"; then
            log SUCCESS "Router migré vers les nœuds infra"
        else
            log ERROR "Échec de la migration du Router"
        fi
    fi
}

# Migration du Registry
migrate_registry() {
    log INFO "Migration du Registry vers les nœuds infra..."
    
    local patch=$(cat << 'PATCH'
spec:
  nodeSelector:
    node-role.kubernetes.io/infra: ""
  tolerations:
  - key: "node-role.kubernetes.io/infra"
    operator: "Exists"
    effect: "NoSchedule"
  replicas: 3
PATCH
)
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "[DRY-RUN] Patch configs.imageregistry.operator.openshift.io/cluster:"
        echo "$patch"
    else
        if oc patch configs.imageregistry.operator.openshift.io/cluster --type=merge -p "$patch"; then
            log SUCCESS "Registry migré vers les nœuds infra"
        else
            log ERROR "Échec de la migration du Registry"
        fi
    fi
}

# Migration du Monitoring
migrate_monitoring() {
    log INFO "Migration du Monitoring vers les nœuds infra..."
    
    # Créer le ConfigMap de configuration du monitoring
    local config_yaml=$(cat << 'CONFIGYAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    alertmanagerMain:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
      - key: "node-role.kubernetes.io/infra"
        operator: "Exists"
        effect: "NoSchedule"
    prometheusK8s:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
      - key: "node-role.kubernetes.io/infra"
        operator: "Exists"
        effect: "NoSchedule"
    prometheusOperator:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
      - key: "node-role.kubernetes.io/infra"
        operator: "Exists"
        effect: "NoSchedule"
    grafana:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
      - key: "node-role.kubernetes.io/infra"
        operator: "Exists"
        effect: "NoSchedule"
    k8sPrometheusAdapter:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
      - key: "node-role.kubernetes.io/infra"
        operator: "Exists"
        effect: "NoSchedule"
    kubeStateMetrics:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
      - key: "node-role.kubernetes.io/infra"
        operator: "Exists"
        effect: "NoSchedule"
    telemeterClient:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
      - key: "node-role.kubernetes.io/infra"
        operator: "Exists"
        effect: "NoSchedule"
    openshiftStateMetrics:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
      - key: "node-role.kubernetes.io/infra"
        operator: "Exists"
        effect: "NoSchedule"
    thanosQuerier:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
      - key: "node-role.kubernetes.io/infra"
        operator: "Exists"
        effect: "NoSchedule"
CONFIGYAML
)
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "[DRY-RUN] Apply ConfigMap cluster-monitoring-config:"
        echo "$config_yaml"
    else
        echo "$config_yaml" | oc apply -f -
        if [[ $? -eq 0 ]]; then
            log SUCCESS "Monitoring migré vers les nœuds infra"
        else
            log ERROR "Échec de la migration du Monitoring"
        fi
    fi
}

# Vérification de l'état des nœuds
verify_nodes() {
    log INFO "Vérification de l'état des nœuds infra..."
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                    ÉTAT DES NŒUDS INFRA                           ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Afficher les nœuds infra
    oc get nodes -l "${INFRA_LABEL}" -o wide
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                    TAINTS DES NŒUDS INFRA                         ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Afficher les taints
    oc get nodes -l "${INFRA_LABEL}" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.taints}{"\n"}{end}'
    
    echo ""
}

# Vérification des composants migrés
verify_migration() {
    log INFO "Vérification de la migration des composants..."
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                    PODS ROUTER (INGRESS)                          ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    oc get pods -n openshift-ingress -o wide
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                    PODS REGISTRY                                  ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    oc get pods -n openshift-image-registry -o wide
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                    PODS MONITORING                                ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    oc get pods -n openshift-monitoring -o wide | head -20
    
    echo ""
}

# Génère un rapport de configuration
generate_report() {
    local report_file="/var/log/openshift-install/infra-nodes-report-$(date +%Y%m%d-%H%M%S).txt"
    
    log INFO "Génération du rapport de configuration..."
    
    {
        echo "═══════════════════════════════════════════════════════════════════"
        echo "            RAPPORT DE CONFIGURATION DES NŒUDS INFRA"
        echo "            $(date)"
        echo "═══════════════════════════════════════════════════════════════════"
        echo ""
        echo "NŒUDS INFRA:"
        echo "------------"
        oc get nodes -l "${INFRA_LABEL}" -o wide
        echo ""
        echo "TAINTS:"
        echo "-------"
        oc get nodes -l "${INFRA_LABEL}" -o jsonpath='{range .items[*]}{.metadata.name}{": "}{.spec.taints}{"\n"}{end}'
        echo ""
        echo "ROUTER STATUS:"
        echo "--------------"
        oc get ingresscontroller/default -n openshift-ingress-operator -o yaml | grep -A 20 "nodePlacement:"
        echo ""
        echo "REGISTRY STATUS:"
        echo "----------------"
        oc get configs.imageregistry.operator.openshift.io/cluster -o yaml | grep -A 10 "nodeSelector:"
        echo ""
        echo "MONITORING CONFIG:"
        echo "------------------"
        oc get configmap cluster-monitoring-config -n openshift-monitoring -o yaml 2>/dev/null || echo "Non configuré"
        echo ""
    } > "$report_file" 2>/dev/null || true
    
    log SUCCESS "Rapport généré: $report_file"
}

#-------------------------------------------------------------------------------
# Parsing des arguments
#-------------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -k|--kubeconfig)
                KUBECONFIG="$2"
                shift 2
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -s|--skip-migration)
                SKIP_MIGRATION=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log ERROR "Option inconnue: $1"
                usage
                exit 1
                ;;
        esac
    done
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------
main() {
    parse_args "$@"
    
    # Créer le répertoire de logs
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    
    print_banner
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║              MODE SIMULATION (DRY-RUN) ACTIVÉ                 ║${NC}"
        echo -e "${YELLOW}║          Aucune modification ne sera effectuée                ║${NC}"
        echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
    fi
    
    # Vérifications préalables
    check_prerequisites
    
    # Obtenir la liste des nœuds infra
    local infra_nodes
    read -ra infra_nodes <<< "$(get_infra_nodes)"
    
    if [[ ${#infra_nodes[@]} -eq 0 ]]; then
        log ERROR "Aucun nœud infra à configurer"
        exit 1
    fi
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  NŒUDS À CONFIGURER: ${infra_nodes[*]}${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [[ "$DRY_RUN" != "true" ]]; then
        read -p "Voulez-vous continuer? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log WARN "Opération annulée par l'utilisateur"
            exit 0
        fi
    fi
    
    # Étape 1: Appliquer les labels
    echo ""
    log INFO "═══ ÉTAPE 1/5: APPLICATION DES LABELS ═══"
    label_infra_nodes "${infra_nodes[@]}"
    
    # Étape 2: Appliquer les taints
    echo ""
    log INFO "═══ ÉTAPE 2/5: APPLICATION DES TAINTS ═══"
    taint_infra_nodes "${infra_nodes[@]}"
    
    # Étape 3: Migration des composants
    if [[ "$SKIP_MIGRATION" != "true" ]]; then
        echo ""
        log INFO "═══ ÉTAPE 3/5: MIGRATION DU ROUTER ═══"
        migrate_router
        
        echo ""
        log INFO "═══ ÉTAPE 4/5: MIGRATION DU REGISTRY ═══"
        migrate_registry
        
        echo ""
        log INFO "═══ ÉTAPE 5/5: MIGRATION DU MONITORING ═══"
        migrate_monitoring
    else
        log WARN "Migration des composants ignorée (--skip-migration)"
    fi
    
    # Vérification
    if [[ "$DRY_RUN" != "true" ]]; then
        echo ""
        verify_nodes
        
        if [[ "$SKIP_MIGRATION" != "true" ]]; then
            verify_migration
        fi
        
        generate_report
    fi
    
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                                   ║${NC}"
    echo -e "${GREEN}║   ✓ CONFIGURATION DES NŒUDS INFRA TERMINÉE                       ║${NC}"
    echo -e "${GREEN}║                                                                   ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log INFO "Note: La migration des pods peut prendre quelques minutes."
        log INFO "Utilisez 'oc get pods -n <namespace> -o wide' pour vérifier."
    fi
}

main "$@"
