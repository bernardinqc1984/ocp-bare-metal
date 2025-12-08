#!/bin/bash
#===============================================================================
#
#          FILE:  create-hosted-cluster.sh
#
#         USAGE:  ./create-hosted-cluster.sh --name <cluster-name> [OPTIONS]
#
#   DESCRIPTION:  Script de création d'un Hosted Cluster HyperShift
#
#       OPTIONS:  --name <name>           Nom du hosted cluster (requis)
#                 --namespace <ns>        Namespace (défaut: clusters)
#                 --node-pool-replicas    Nombre de workers (défaut: 3)
#                 --release <image>       Image de release OpenShift
#                 --help                  Afficher l'aide
#
#===============================================================================

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WORK_DIR="/opt/openshift"

# Couleurs
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# Variables par défaut
CLUSTER_NAME=""
NAMESPACE="clusters"
NODE_POOL_REPLICAS=3
RELEASE_IMAGE="quay.io/openshift-release-dev/ocp-release:4.17.0-x86_64"
PULL_SECRET_FILE="/opt/openshift/pull-secret.json"
SSH_KEY_FILE="/root/.ssh/id_rsa.pub"

log() {
    local level="$1"
    shift
    case "$level" in
        INFO)    echo -e "${GREEN}[INFO]${NC} $*" ;;
        WARN)    echo -e "${YELLOW}[WARN]${NC} $*" ;;
        ERROR)   echo -e "${RED}[ERROR]${NC} $*" ;;
    esac
}

show_help() {
    cat << EOF
Usage: $0 --name <cluster-name> [OPTIONS]

Crée un nouveau Hosted Cluster HyperShift sur le management cluster.

OPTIONS:
    -n, --name <name>           Nom du hosted cluster (requis)
    --namespace <ns>            Namespace Kubernetes (défaut: clusters)
    --node-pool-replicas <n>    Nombre de workers (défaut: 3)
    --release <image>           Image de release OpenShift
    --pull-secret <file>        Fichier pull secret
    --ssh-key <file>            Fichier clé SSH publique
    -h, --help                  Afficher cette aide

EXEMPLES:
    # Création basique
    $0 --name dev-cluster

    # Avec options
    $0 --name prod-cluster --node-pool-replicas 5 --namespace production

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--name)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            --namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            --node-pool-replicas)
                NODE_POOL_REPLICAS="$2"
                shift 2
                ;;
            --release)
                RELEASE_IMAGE="$2"
                shift 2
                ;;
            --pull-secret)
                PULL_SECRET_FILE="$2"
                shift 2
                ;;
            --ssh-key)
                SSH_KEY_FILE="$2"
                shift 2
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
    
    if [[ -z "$CLUSTER_NAME" ]]; then
        log ERROR "Le nom du cluster est requis (--name)"
        show_help
        exit 1
    fi
}

create_hosted_cluster() {
    log INFO "Création du Hosted Cluster: $CLUSTER_NAME"
    
    export KUBECONFIG="${WORK_DIR}/install/auth/kubeconfig"
    
    # Vérification que HyperShift est installé
    if ! oc get crd hostedclusters.hypershift.openshift.io &>/dev/null; then
        log ERROR "HyperShift n'est pas installé sur ce cluster"
        exit 1
    fi
    
    # Création du namespace
    log INFO "Création du namespace: $NAMESPACE"
    oc create namespace "$NAMESPACE" --dry-run=client -o yaml | oc apply -f -
    
    # Création du secret pull
    log INFO "Création du secret pull..."
    oc create secret generic pull-secret \
        --from-file=.dockerconfigjson="$PULL_SECRET_FILE" \
        --type=kubernetes.io/dockerconfigjson \
        -n "$NAMESPACE" \
        --dry-run=client -o yaml | oc apply -f -
    
    # Création du secret SSH
    log INFO "Création du secret SSH..."
    oc create secret generic ssh-key \
        --from-file=id_rsa.pub="$SSH_KEY_FILE" \
        -n "$NAMESPACE" \
        --dry-run=client -o yaml | oc apply -f -
    
    # Création du namespace pour l'agent
    local agent_namespace="${CLUSTER_NAME}-agents"
    oc create namespace "$agent_namespace" --dry-run=client -o yaml | oc apply -f -
    
    # Création du HostedCluster
    log INFO "Création du HostedCluster..."
    cat <<EOF | oc apply -f -
apiVersion: hypershift.openshift.io/v1beta1
kind: HostedCluster
metadata:
  name: ${CLUSTER_NAME}
  namespace: ${NAMESPACE}
spec:
  release:
    image: ${RELEASE_IMAGE}
  pullSecret:
    name: pull-secret
  sshKey:
    name: ssh-key
  networking:
    clusterNetwork:
    - cidr: 10.132.0.0/14
    serviceNetwork:
    - cidr: 172.31.0.0/16
    networkType: OVNKubernetes
  platform:
    type: Agent
    agent:
      agentNamespace: ${agent_namespace}
  infraID: ${CLUSTER_NAME}-infra
  dns:
    baseDomain: example.com
  services:
  - service: APIServer
    servicePublishingStrategy:
      type: LoadBalancer
  - service: OAuthServer
    servicePublishingStrategy:
      type: Route
  - service: Konnectivity
    servicePublishingStrategy:
      type: Route
  - service: Ignition
    servicePublishingStrategy:
      type: Route
  controllerAvailabilityPolicy: HighlyAvailable
EOF

    # Création du NodePool
    log INFO "Création du NodePool..."
    cat <<EOF | oc apply -f -
apiVersion: hypershift.openshift.io/v1beta1
kind: NodePool
metadata:
  name: ${CLUSTER_NAME}-nodepool
  namespace: ${NAMESPACE}
spec:
  clusterName: ${CLUSTER_NAME}
  replicas: ${NODE_POOL_REPLICAS}
  management:
    autoRepair: true
    upgradeType: Replace
  platform:
    type: Agent
    agent:
      agentLabelSelector:
        matchLabels:
          cluster: ${CLUSTER_NAME}
  release:
    image: ${RELEASE_IMAGE}
EOF

    # Création de l'InfraEnv pour les agents
    log INFO "Création de l'InfraEnv..."
    cat <<EOF | oc apply -f -
apiVersion: agent-install.openshift.io/v1beta1
kind: InfraEnv
metadata:
  name: ${CLUSTER_NAME}
  namespace: ${agent_namespace}
spec:
  clusterRef:
    name: ${CLUSTER_NAME}
    namespace: ${NAMESPACE}
  pullSecretRef:
    name: pull-secret
  sshAuthorizedKey: "$(cat $SSH_KEY_FILE)"
  nmStateConfigLabelSelector:
    matchLabels:
      cluster: ${CLUSTER_NAME}
EOF

    log INFO "Attente de la génération de l'ISO de découverte..."
    sleep 30
    
    # Récupération de l'URL de l'ISO
    local iso_url=$(oc get infraenv "${CLUSTER_NAME}" -n "${agent_namespace}" \
        -o jsonpath='{.status.isoDownloadURL}' 2>/dev/null || echo "")
    
    if [[ -n "$iso_url" ]]; then
        log INFO "ISO de découverte disponible:"
        echo "$iso_url"
        
        # Téléchargement de l'ISO
        log INFO "Téléchargement de l'ISO..."
        wget -q --show-progress -O "/var/www/html/discovery-${CLUSTER_NAME}.iso" "$iso_url"
    else
        log WARN "L'ISO n'est pas encore disponible. Vérifiez avec:"
        echo "  oc get infraenv ${CLUSTER_NAME} -n ${agent_namespace} -o jsonpath='{.status.isoDownloadURL}'"
    fi
    
    log INFO ""
    log INFO "═══════════════════════════════════════════════════════════════════"
    log INFO "  Hosted Cluster créé avec succès!"
    log INFO "═══════════════════════════════════════════════════════════════════"
    log INFO ""
    log INFO "  Cluster Name: ${CLUSTER_NAME}"
    log INFO "  Namespace: ${NAMESPACE}"
    log INFO "  NodePool Replicas: ${NODE_POOL_REPLICAS}"
    log INFO ""
    log INFO "  Prochaines étapes:"
    log INFO "  1. Bootez les workers avec l'ISO de découverte"
    log INFO "  2. Les agents apparaîtront automatiquement"
    log INFO "  3. Approuvez les agents pour les ajouter au cluster"
    log INFO ""
    log INFO "  Commandes utiles:"
    log INFO "    # État du hosted cluster"
    log INFO "    oc get hostedcluster ${CLUSTER_NAME} -n ${NAMESPACE}"
    log INFO ""
    log INFO "    # Liste des agents"
    log INFO "    oc get agents -n ${agent_namespace}"
    log INFO ""
    log INFO "    # Générer le kubeconfig"
    log INFO "    hypershift create kubeconfig --name=${CLUSTER_NAME} --namespace=${NAMESPACE}"
    log INFO ""
}

main() {
    parse_args "$@"
    create_hosted_cluster
}

main "$@"
