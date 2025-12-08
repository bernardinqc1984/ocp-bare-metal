#!/bin/bash
#===============================================================================
#
#          FILE:  install.sh
#
#         USAGE:  ./install.sh [OPTIONS]
#
#   DESCRIPTION:  Script principal d'installation automatisée OpenShift 
#                 sur infrastructure bare metal avec support HyperShift
#
#       OPTIONS:  --config <file>    Fichier de configuration personnalisé
#                 --phase <phase>    Exécuter une phase spécifique
#                 --skip-prereq      Ignorer la vérification des prérequis
#                 --dry-run          Mode simulation (aucune modification)
#                 --verbose          Mode verbeux
#                 --help             Afficher l'aide
#
#  REQUIREMENTS:  RHEL 8.x/9.x, accès root, connexion Internet
#
#        AUTHOR:  Infrastructure Team
#       VERSION:  1.0.0
#       CREATED:  Décembre 2024
#
#===============================================================================

set -euo pipefail

#-------------------------------------------------------------------------------
# VARIABLES GLOBALES
#-------------------------------------------------------------------------------
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly LOG_DIR="/var/log/openshift-install"
readonly LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"
readonly CONFIG_DIR="${SCRIPT_DIR}/../config"
readonly WORK_DIR="/opt/openshift"

# Couleurs pour l'affichage
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

# Variables de configuration par défaut
CONFIG_FILE="${CONFIG_DIR}/cluster-config.yaml"
DRY_RUN=false
VERBOSE=false
SKIP_PREREQ=false
PHASE=""

#-------------------------------------------------------------------------------
# FONCTIONS UTILITAIRES
#-------------------------------------------------------------------------------

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        INFO)    echo -e "${CYAN}[INFO]${NC} ${timestamp} - ${message}" ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} ${timestamp} - ${message}" ;;
        WARN)    echo -e "${YELLOW}[WARN]${NC} ${timestamp} - ${message}" ;;
        ERROR)   echo -e "${RED}[ERROR]${NC} ${timestamp} - ${message}" ;;
        DEBUG)   [[ "$VERBOSE" == "true" ]] && echo -e "${BLUE}[DEBUG]${NC} ${timestamp} - ${message}" ;;
    esac
    
    # Écriture dans le fichier de log
    echo "[${level}] ${timestamp} - ${message}" >> "$LOG_FILE" 2>/dev/null || true
}

print_banner() {
    echo -e "${BOLD}${CYAN}"
    cat << 'EOF'
    ╔═══════════════════════════════════════════════════════════════════════════╗
    ║                                                                           ║
    ║     ██████╗ ██████╗ ███████╗███╗   ██╗███████╗██╗  ██╗██╗███████╗████████╗║
    ║    ██╔═══██╗██╔══██╗██╔════╝████╗  ██║██╔════╝██║  ██║██║██╔════╝╚══██╔══╝║
    ║    ██║   ██║██████╔╝█████╗  ██╔██╗ ██║███████╗███████║██║█████╗     ██║   ║
    ║    ██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║╚════██║██╔══██║██║██╔══╝     ██║   ║
    ║    ╚██████╔╝██║     ███████╗██║ ╚████║███████║██║  ██║██║██║        ██║   ║
    ║     ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝╚═╝╚═╝        ╚═╝   ║
    ║                                                                           ║
    ║              Bare Metal Installation Automation Script                     ║
    ║                           Version 1.0.0                                   ║
    ║                                                                           ║
    ╚═══════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_phase() {
    local phase_num="$1"
    local phase_name="$2"
    echo ""
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${BLUE}  PHASE ${phase_num}: ${phase_name}${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

show_help() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Script d'installation automatisée OpenShift sur bare metal avec HyperShift.

OPTIONS:
    -c, --config <file>     Fichier de configuration personnalisé
                            (défaut: ${CONFIG_FILE})
    
    -p, --phase <phase>     Exécuter une phase spécifique:
                            prereq    - Vérification des prérequis
                            bastion   - Configuration du bastion
                            services  - Configuration des services
                            ignition  - Génération des fichiers ignition
                            deploy    - Déploiement du cluster
                            validate  - Validation post-installation
                            hypershift- Installation HyperShift
                            all       - Toutes les phases (défaut)
    
    -s, --skip-prereq       Ignorer la vérification des prérequis
    
    -n, --dry-run           Mode simulation (aucune modification effectuée)
    
    -v, --verbose           Mode verbeux (affiche les détails)
    
    -h, --help              Afficher cette aide

EXEMPLES:
    # Installation complète avec configuration par défaut
    ${SCRIPT_NAME}
    
    # Installation avec fichier de configuration personnalisé
    ${SCRIPT_NAME} --config /path/to/my-config.yaml
    
    # Exécution d'une phase spécifique
    ${SCRIPT_NAME} --phase bastion
    
    # Mode simulation
    ${SCRIPT_NAME} --dry-run --verbose

FICHIERS DE CONFIGURATION:
    Créez votre fichier de configuration en copiant le template:
    cp ${CONFIG_DIR}/cluster-config.yaml.template ${CONFIG_DIR}/cluster-config.yaml

Pour plus d'informations, consultez la documentation:
    ${SCRIPT_DIR}/../docs/OpenShift_BareMetal_Installation_Guide.md

EOF
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log ERROR "Ce script doit être exécuté en tant que root"
        exit 1
    fi
}

create_directories() {
    log INFO "Création des répertoires de travail..."
    
    local dirs=(
        "$LOG_DIR"
        "$WORK_DIR"
        "${WORK_DIR}/install"
        "${WORK_DIR}/backup"
        "/var/www/html/rhcos"
        "/var/www/html/ignition"
        "/var/lib/tftpboot/pxelinux.cfg"
        "/var/lib/tftpboot/rhcos"
        "/var/lib/tftpboot/uefi"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log DEBUG "[DRY-RUN] Création du répertoire: $dir"
        else
            mkdir -p "$dir"
            log DEBUG "Répertoire créé: $dir"
        fi
    done
    
    log SUCCESS "Répertoires de travail créés"
}

parse_config() {
    log INFO "Lecture de la configuration depuis: $CONFIG_FILE"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log ERROR "Fichier de configuration non trouvé: $CONFIG_FILE"
        log INFO "Créez le fichier à partir du template:"
        log INFO "  cp ${CONFIG_DIR}/cluster-config.yaml.template ${CONFIG_DIR}/cluster-config.yaml"
        exit 1
    fi
    
    # Vérification que yq est disponible
    if ! command -v yq &> /dev/null; then
        log WARN "yq non disponible, installation en cours..."
        install_yq
    fi
    
    # Lecture des variables depuis le fichier YAML
    export CLUSTER_NAME=$(yq e '.cluster.name' "$CONFIG_FILE")
    export BASE_DOMAIN=$(yq e '.cluster.baseDomain' "$CONFIG_FILE")
    export OPENSHIFT_VERSION=$(yq e '.cluster.version' "$CONFIG_FILE")
    
    export BAREMETAL_NETWORK=$(yq e '.network.baremetal.subnet' "$CONFIG_FILE")
    export BAREMETAL_GATEWAY=$(yq e '.network.baremetal.gateway' "$CONFIG_FILE")
    export PROVISIONING_NETWORK=$(yq e '.network.provisioning.subnet' "$CONFIG_FILE")
    
    export API_VIP=$(yq e '.network.vips.api' "$CONFIG_FILE")
    export INGRESS_VIP=$(yq e '.network.vips.ingress' "$CONFIG_FILE")
    
    export BASTION_IP=$(yq e '.nodes.bastion.ip' "$CONFIG_FILE")
    export BASTION_PROV_IP=$(yq e '.nodes.bastion.provisioningIp' "$CONFIG_FILE")
    
    log SUCCESS "Configuration chargée avec succès"
    log DEBUG "Cluster: ${CLUSTER_NAME}.${BASE_DOMAIN}"
    log DEBUG "Version OpenShift: ${OPENSHIFT_VERSION}"
}

install_yq() {
    log INFO "Installation de yq..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "[DRY-RUN] Installation de yq"
        return
    fi
    
    local yq_version="v4.35.1"
    wget -qO /usr/local/bin/yq \
        "https://github.com/mikefarah/yq/releases/download/${yq_version}/yq_linux_amd64"
    chmod +x /usr/local/bin/yq
    
    log SUCCESS "yq installé avec succès"
}

#-------------------------------------------------------------------------------
# PHASE 1: VÉRIFICATION DES PRÉREQUIS
#-------------------------------------------------------------------------------

phase_prereq() {
    print_phase "1" "VÉRIFICATION DES PRÉREQUIS"
    
    local errors=0
    
    log INFO "Vérification du système d'exploitation..."
    if [[ -f /etc/redhat-release ]]; then
        local os_version=$(cat /etc/redhat-release)
        log SUCCESS "OS détecté: $os_version"
    else
        log ERROR "Ce script requiert RHEL 8.x ou 9.x"
        ((errors++))
    fi
    
    log INFO "Vérification de la connectivité Internet..."
    if ping -c 1 mirror.openshift.com &> /dev/null; then
        log SUCCESS "Connectivité Internet: OK"
    else
        log ERROR "Pas de connectivité Internet vers mirror.openshift.com"
        ((errors++))
    fi
    
    log INFO "Vérification de l'espace disque..."
    local available_space=$(df -BG /opt | tail -1 | awk '{print $4}' | tr -d 'G')
    if [[ "$available_space" -ge 50 ]]; then
        log SUCCESS "Espace disque disponible: ${available_space}GB"
    else
        log ERROR "Espace disque insuffisant: ${available_space}GB (minimum 50GB requis)"
        ((errors++))
    fi
    
    log INFO "Vérification de la mémoire RAM..."
    local total_ram=$(free -g | awk '/^Mem:/{print $2}')
    if [[ "$total_ram" -ge 8 ]]; then
        log SUCCESS "RAM disponible: ${total_ram}GB"
    else
        log WARN "RAM limitée: ${total_ram}GB (8GB recommandé)"
    fi
    
    log INFO "Vérification des interfaces réseau..."
    local iface_count=$(ip -o link show | grep -c 'state UP')
    if [[ "$iface_count" -ge 2 ]]; then
        log SUCCESS "Interfaces réseau actives: $iface_count"
    else
        log WARN "Une seule interface réseau détectée (2 recommandées)"
    fi
    
    log INFO "Vérification de SELinux..."
    local selinux_status=$(getenforce 2>/dev/null || echo "Disabled")
    log INFO "SELinux: $selinux_status"
    
    if [[ "$errors" -gt 0 ]]; then
        log ERROR "Vérification des prérequis échouée avec $errors erreur(s)"
        exit 1
    fi
    
    log SUCCESS "Tous les prérequis sont satisfaits"
}

#-------------------------------------------------------------------------------
# PHASE 2: CONFIGURATION DU BASTION
#-------------------------------------------------------------------------------

phase_bastion() {
    print_phase "2" "CONFIGURATION DU BASTION"
    
    log INFO "Installation des packages nécessaires..."
    
    local packages=(
        "tftp-server"
        "dhcp-server"
        "syslinux"
        "httpd"
        "haproxy"
        "bind"
        "bind-utils"
        "wget"
        "jq"
        "git"
        "podman"
        "skopeo"
        "nfs-utils"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "[DRY-RUN] Installation des packages: ${packages[*]}"
    else
        dnf install -y epel-release
        dnf update -y
        dnf install -y "${packages[@]}"
    fi
    
    log SUCCESS "Packages installés"
    
    # Configuration réseau
    log INFO "Configuration des interfaces réseau..."
    source "${SCRIPT_DIR}/modules/configure_network.sh"
    configure_bastion_network
    
    # Configuration du firewall
    log INFO "Configuration du firewall..."
    source "${SCRIPT_DIR}/modules/configure_firewall.sh"
    configure_firewall
    
    # Téléchargement des binaires OpenShift
    log INFO "Téléchargement des binaires OpenShift ${OPENSHIFT_VERSION}..."
    source "${SCRIPT_DIR}/modules/download_binaries.sh"
    download_openshift_binaries
    
    log SUCCESS "Configuration du bastion terminée"
}

#-------------------------------------------------------------------------------
# PHASE 3: CONFIGURATION DES SERVICES
#-------------------------------------------------------------------------------

phase_services() {
    print_phase "3" "CONFIGURATION DES SERVICES"
    
    log INFO "Configuration du serveur DHCP..."
    source "${SCRIPT_DIR}/modules/configure_dhcp.sh"
    configure_dhcp_server
    
    log INFO "Configuration du serveur TFTP..."
    source "${SCRIPT_DIR}/modules/configure_tftp.sh"
    configure_tftp_server
    
    log INFO "Configuration du serveur HTTP..."
    source "${SCRIPT_DIR}/modules/configure_http.sh"
    configure_http_server
    
    log INFO "Configuration de HAProxy..."
    source "${SCRIPT_DIR}/modules/configure_haproxy.sh"
    configure_haproxy
    
    log INFO "Configuration DNS (optionnel)..."
    source "${SCRIPT_DIR}/modules/configure_dns.sh"
    configure_dns_server
    
    log INFO "Téléchargement des images RHCOS..."
    source "${SCRIPT_DIR}/modules/download_rhcos.sh"
    download_rhcos_images
    
    log SUCCESS "Configuration des services terminée"
}

#-------------------------------------------------------------------------------
# PHASE 4: GÉNÉRATION DES FICHIERS IGNITION
#-------------------------------------------------------------------------------

phase_ignition() {
    print_phase "4" "GÉNÉRATION DES FICHIERS IGNITION"
    
    log INFO "Création du fichier install-config.yaml..."
    source "${SCRIPT_DIR}/modules/generate_install_config.sh"
    generate_install_config
    
    log INFO "Génération des manifestes..."
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "[DRY-RUN] openshift-install create manifests"
    else
        cd "${WORK_DIR}/install"
        openshift-install create manifests --dir=.
    fi
    
    log INFO "Génération des fichiers Ignition..."
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "[DRY-RUN] openshift-install create ignition-configs"
    else
        openshift-install create ignition-configs --dir=.
        
        # Copie vers le serveur web
        cp "${WORK_DIR}/install/"*.ign /var/www/html/ignition/
        chmod 644 /var/www/html/ignition/*.ign
        restorecon -RFv /var/www/html/ignition/
    fi
    
    log INFO "Configuration du menu PXE..."
    source "${SCRIPT_DIR}/modules/configure_pxe.sh"
    configure_pxe_menu
    
    log SUCCESS "Fichiers Ignition générés et déployés"
}

#-------------------------------------------------------------------------------
# PHASE 5: DÉPLOIEMENT DU CLUSTER
#-------------------------------------------------------------------------------

phase_deploy() {
    print_phase "5" "DÉPLOIEMENT DU CLUSTER"
    
    log INFO "Vérification des services..."
    local services=("dhcpd" "tftp.socket" "httpd" "haproxy")
    
    for svc in "${services[@]}"; do
        if systemctl is-active --quiet "$svc"; then
            log SUCCESS "Service $svc: actif"
        else
            log ERROR "Service $svc: inactif"
            systemctl start "$svc" || true
        fi
    done
    
    log INFO ""
    log INFO "═══════════════════════════════════════════════════════════════════"
    log INFO "  INSTRUCTIONS DE DÉPLOIEMENT MANUEL"
    log INFO "═══════════════════════════════════════════════════════════════════"
    log INFO ""
    log INFO "  1. Démarrer le nœud BOOTSTRAP en boot PXE"
    log INFO "     Sélectionner: 'Install OpenShift Bootstrap Node'"
    log INFO ""
    log INFO "  2. Démarrer les nœuds MASTER en boot PXE"
    log INFO "     Sélectionner: 'Install OpenShift Master Node'"
    log INFO ""
    log INFO "  3. Surveiller la progression du bootstrap:"
    log INFO "     openshift-install --dir=${WORK_DIR}/install wait-for bootstrap-complete"
    log INFO ""
    log INFO "  4. Une fois le bootstrap terminé (~30 min):"
    log INFO "     - Éteindre le nœud bootstrap"
    log INFO "     - Retirer bootstrap de HAProxy"
    log INFO "     - Redémarrer HAProxy"
    log INFO ""
    log INFO "  5. Démarrer les nœuds WORKER en boot PXE"
    log INFO "     Sélectionner: 'Install OpenShift Worker Node'"
    log INFO ""
    log INFO "  6. Approuver les certificats des workers:"
    log INFO "     export KUBECONFIG=${WORK_DIR}/install/auth/kubeconfig"
    log INFO "     oc get csr -o name | xargs oc adm certificate approve"
    log INFO ""
    log INFO "  7. Attendre la fin de l'installation:"
    log INFO "     openshift-install --dir=${WORK_DIR}/install wait-for install-complete"
    log INFO ""
    log INFO "═══════════════════════════════════════════════════════════════════"
    
    # Attente du bootstrap (si mode interactif)
    if [[ "$DRY_RUN" != "true" ]]; then
        read -p "Appuyez sur [Entrée] une fois le bootstrap et les masters démarrés..."
        
        log INFO "Surveillance du bootstrap..."
        openshift-install --dir="${WORK_DIR}/install" wait-for bootstrap-complete --log-level=info || {
            log ERROR "Le bootstrap a échoué. Consultez les logs pour plus de détails."
            exit 1
        }
        
        log SUCCESS "Bootstrap terminé avec succès!"
        log WARN "N'oubliez pas de retirer le nœud bootstrap et de redémarrer HAProxy"
        
        read -p "Appuyez sur [Entrée] une fois les workers démarrés..."
        
        log INFO "Approbation automatique des CSR..."
        export KUBECONFIG="${WORK_DIR}/install/auth/kubeconfig"
        
        # Boucle d'approbation des CSR
        for i in {1..10}; do
            sleep 30
            oc get csr -o name 2>/dev/null | xargs -r oc adm certificate approve 2>/dev/null || true
        done
        
        log INFO "Attente de la fin de l'installation..."
        openshift-install --dir="${WORK_DIR}/install" wait-for install-complete --log-level=info
    fi
    
    log SUCCESS "Déploiement du cluster terminé"
}

#-------------------------------------------------------------------------------
# PHASE 6: VALIDATION POST-INSTALLATION
#-------------------------------------------------------------------------------

phase_validate() {
    print_phase "6" "VALIDATION POST-INSTALLATION"
    
    export KUBECONFIG="${WORK_DIR}/install/auth/kubeconfig"
    
    log INFO "Vérification des nœuds..."
    if [[ "$DRY_RUN" != "true" ]]; then
        oc get nodes -o wide
        echo ""
    fi
    
    log INFO "Vérification des ClusterOperators..."
    if [[ "$DRY_RUN" != "true" ]]; then
        oc get clusteroperators
        echo ""
        
        # Vérification des opérateurs dégradés
        degraded=$(oc get co -o json | jq -r '.items[] | select(.status.conditions[] | select(.type=="Degraded" and .status=="True")) | .metadata.name' 2>/dev/null || true)
        if [[ -n "$degraded" ]]; then
            log WARN "Opérateurs dégradés détectés: $degraded"
        else
            log SUCCESS "Tous les opérateurs sont fonctionnels"
        fi
    fi
    
    log INFO "Test de connectivité API..."
    if [[ "$DRY_RUN" != "true" ]]; then
        if oc whoami &>/dev/null; then
            log SUCCESS "Connexion API: OK"
        else
            log ERROR "Connexion API: ÉCHEC"
        fi
    fi
    
    # Sauvegarde des informations d'accès
    log INFO "Sauvegarde des informations d'accès..."
    if [[ "$DRY_RUN" != "true" ]]; then
        cat > "${WORK_DIR}/cluster-info.txt" << EOF
═══════════════════════════════════════════════════════════════════════════════
                    INFORMATIONS D'ACCÈS AU CLUSTER OPENSHIFT
═══════════════════════════════════════════════════════════════════════════════

Cluster Name:       ${CLUSTER_NAME}
Base Domain:        ${BASE_DOMAIN}

Console URL:        https://console-openshift-console.apps.${CLUSTER_NAME}.${BASE_DOMAIN}
API URL:            https://api.${CLUSTER_NAME}.${BASE_DOMAIN}:6443

Kubeadmin User:     kubeadmin
Kubeadmin Password: $(cat ${WORK_DIR}/install/auth/kubeadmin-password 2>/dev/null || echo "N/A")

Kubeconfig:         ${WORK_DIR}/install/auth/kubeconfig

Installation Date:  $(date)
OpenShift Version:  $(oc version -o json 2>/dev/null | jq -r '.openshiftVersion' || echo "N/A")

═══════════════════════════════════════════════════════════════════════════════
EOF
        chmod 600 "${WORK_DIR}/cluster-info.txt"
        log SUCCESS "Informations sauvegardées dans: ${WORK_DIR}/cluster-info.txt"
    fi
    
    log SUCCESS "Validation post-installation terminée"
}

#-------------------------------------------------------------------------------
# PHASE 7: INSTALLATION HYPERSHIFT
#-------------------------------------------------------------------------------

phase_hypershift() {
    print_phase "7" "INSTALLATION HYPERSHIFT"
    
    export KUBECONFIG="${WORK_DIR}/install/auth/kubeconfig"
    
    log INFO "Installation de l'opérateur HyperShift..."
    source "${SCRIPT_DIR}/modules/install_hypershift.sh"
    install_hypershift_operator
    
    log INFO "Configuration de l'Agent Service..."
    configure_agent_service
    
    log SUCCESS "HyperShift installé et configuré"
    log INFO ""
    log INFO "Pour créer un Hosted Cluster, utilisez:"
    log INFO "  ${SCRIPT_DIR}/create-hosted-cluster.sh --name <cluster-name>"
}

#-------------------------------------------------------------------------------
# FONCTION PRINCIPALE
#-------------------------------------------------------------------------------

main() {
    # Parsing des arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -p|--phase)
                PHASE="$2"
                shift 2
                ;;
            -s|--skip-prereq)
                SKIP_PREREQ=true
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log ERROR "Option inconnue: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Vérification root
    check_root
    
    # Affichage du banner
    print_banner
    
    # Création des répertoires
    create_directories
    
    # Chargement de la configuration
    parse_config
    
    # Mode dry-run
    if [[ "$DRY_RUN" == "true" ]]; then
        log WARN "Mode DRY-RUN activé - Aucune modification ne sera effectuée"
    fi
    
    # Exécution des phases
    case "${PHASE:-all}" in
        prereq)
            phase_prereq
            ;;
        bastion)
            phase_bastion
            ;;
        services)
            phase_services
            ;;
        ignition)
            phase_ignition
            ;;
        deploy)
            phase_deploy
            ;;
        validate)
            phase_validate
            ;;
        hypershift)
            phase_hypershift
            ;;
        all)
            [[ "$SKIP_PREREQ" != "true" ]] && phase_prereq
            phase_bastion
            phase_services
            phase_ignition
            phase_deploy
            phase_validate
            phase_hypershift
            ;;
        *)
            log ERROR "Phase inconnue: $PHASE"
            show_help
            exit 1
            ;;
    esac
    
    echo ""
    log SUCCESS "═══════════════════════════════════════════════════════════════════"
    log SUCCESS "  INSTALLATION TERMINÉE AVEC SUCCÈS"
    log SUCCESS "═══════════════════════════════════════════════════════════════════"
    echo ""
}

# Point d'entrée
main "$@"
