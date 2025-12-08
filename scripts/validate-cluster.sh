#!/bin/bash
#===============================================================================
#
#          FILE:  validate-cluster.sh
#
#         USAGE:  ./validate-cluster.sh [OPTIONS]
#
#   DESCRIPTION:  Script de validation post-installation du cluster OpenShift
#
#===============================================================================

set -euo pipefail

readonly WORK_DIR="/opt/openshift"
export KUBECONFIG="${WORK_DIR}/install/auth/kubeconfig"

# Couleurs
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# Compteurs
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNING=0

log_test() {
    local status="$1"
    local test_name="$2"
    local details="${3:-}"
    
    case "$status" in
        PASS)
            echo -e "  ${GREEN}✓${NC} ${test_name}"
            ((TESTS_PASSED++))
            ;;
        FAIL)
            echo -e "  ${RED}✗${NC} ${test_name}"
            [[ -n "$details" ]] && echo -e "      ${RED}→ ${details}${NC}"
            ((TESTS_FAILED++))
            ;;
        WARN)
            echo -e "  ${YELLOW}⚠${NC} ${test_name}"
            [[ -n "$details" ]] && echo -e "      ${YELLOW}→ ${details}${NC}"
            ((TESTS_WARNING++))
            ;;
    esac
}

print_section() {
    echo ""
    echo -e "${BOLD}${BLUE}━━━ $1 ━━━${NC}"
    echo ""
}

#-------------------------------------------------------------------------------
# Tests d'infrastructure
#-------------------------------------------------------------------------------

test_nodes() {
    print_section "NŒUDS DU CLUSTER"
    
    local total_nodes=$(oc get nodes --no-headers 2>/dev/null | wc -l)
    local ready_nodes=$(oc get nodes --no-headers 2>/dev/null | grep -c " Ready " || true)
    
    if [[ "$total_nodes" -gt 0 ]]; then
        log_test PASS "Nœuds détectés: $total_nodes"
    else
        log_test FAIL "Aucun nœud détecté"
        return
    fi
    
    if [[ "$ready_nodes" -eq "$total_nodes" ]]; then
        log_test PASS "Tous les nœuds sont Ready ($ready_nodes/$total_nodes)"
    else
        log_test FAIL "Nœuds non Ready" "$ready_nodes/$total_nodes prêts"
    fi
    
    # Vérification des masters
    local master_count=$(oc get nodes --selector='node-role.kubernetes.io/master' --no-headers 2>/dev/null | wc -l)
    if [[ "$master_count" -ge 3 ]]; then
        log_test PASS "Control Plane: $master_count masters"
    else
        log_test WARN "Control Plane: $master_count masters (3 recommandés)"
    fi
    
    # Vérification des workers
    local worker_count=$(oc get nodes --selector='node-role.kubernetes.io/worker' --no-headers 2>/dev/null | wc -l)
    if [[ "$worker_count" -ge 2 ]]; then
        log_test PASS "Workers: $worker_count nœuds"
    else
        log_test WARN "Workers: $worker_count nœuds (2+ recommandés)"
    fi
    
    # Affichage des nœuds
    echo ""
    oc get nodes -o wide
}

test_cluster_operators() {
    print_section "CLUSTER OPERATORS"
    
    local total_co=$(oc get clusteroperators --no-headers 2>/dev/null | wc -l)
    local available_co=$(oc get clusteroperators -o json 2>/dev/null | \
        jq '[.items[] | select(.status.conditions[] | select(.type=="Available" and .status=="True"))] | length')
    local degraded_co=$(oc get clusteroperators -o json 2>/dev/null | \
        jq -r '[.items[] | select(.status.conditions[] | select(.type=="Degraded" and .status=="True"))] | .[].metadata.name' 2>/dev/null || true)
    
    if [[ "$available_co" -eq "$total_co" ]]; then
        log_test PASS "Tous les opérateurs sont disponibles ($available_co/$total_co)"
    else
        log_test FAIL "Opérateurs non disponibles" "$available_co/$total_co disponibles"
    fi
    
    if [[ -z "$degraded_co" ]]; then
        log_test PASS "Aucun opérateur dégradé"
    else
        log_test FAIL "Opérateurs dégradés" "$degraded_co"
    fi
    
    # Affichage des opérateurs non disponibles
    echo ""
    local unavailable=$(oc get clusteroperators -o json 2>/dev/null | \
        jq -r '.items[] | select(.status.conditions[] | select(.type=="Available" and .status=="False")) | .metadata.name' 2>/dev/null || true)
    if [[ -n "$unavailable" ]]; then
        echo -e "${YELLOW}Opérateurs non disponibles:${NC}"
        echo "$unavailable"
    fi
}

test_etcd() {
    print_section "ETCD"
    
    local etcd_pods=$(oc get pods -n openshift-etcd --no-headers 2>/dev/null | grep -c "etcd-" || true)
    local etcd_running=$(oc get pods -n openshift-etcd --no-headers 2>/dev/null | grep "etcd-" | grep -c "Running" || true)
    
    if [[ "$etcd_running" -ge 3 ]]; then
        log_test PASS "etcd pods running: $etcd_running"
    else
        log_test FAIL "etcd pods insuffisants" "$etcd_running/3 running"
    fi
    
    # Test de santé etcd
    local etcd_health=$(oc get etcd cluster -o jsonpath='{.status.conditions[?(@.type=="EtcdMembersAvailable")].status}' 2>/dev/null || echo "Unknown")
    if [[ "$etcd_health" == "True" ]]; then
        log_test PASS "etcd cluster health: OK"
    else
        log_test WARN "etcd cluster health: $etcd_health"
    fi
}

test_networking() {
    print_section "RÉSEAU"
    
    # Vérification du type de réseau
    local network_type=$(oc get network.config cluster -o jsonpath='{.spec.networkType}' 2>/dev/null || echo "Unknown")
    log_test PASS "Network Type: $network_type"
    
    # Vérification du réseau de pods
    local pod_network=$(oc get network.config cluster -o jsonpath='{.spec.clusterNetwork[0].cidr}' 2>/dev/null || echo "Unknown")
    log_test PASS "Pod Network: $pod_network"
    
    # Vérification du réseau de services
    local svc_network=$(oc get network.config cluster -o jsonpath='{.spec.serviceNetwork[0]}' 2>/dev/null || echo "Unknown")
    log_test PASS "Service Network: $svc_network"
    
    # Test DNS
    local dns_pods=$(oc get pods -n openshift-dns --no-headers 2>/dev/null | grep -c "Running" || true)
    if [[ "$dns_pods" -gt 0 ]]; then
        log_test PASS "DNS pods running: $dns_pods"
    else
        log_test FAIL "DNS pods non fonctionnels"
    fi
}

test_ingress() {
    print_section "INGRESS"
    
    # Vérification du router
    local router_pods=$(oc get pods -n openshift-ingress --no-headers 2>/dev/null | grep -c "Running" || true)
    if [[ "$router_pods" -gt 0 ]]; then
        log_test PASS "Router pods running: $router_pods"
    else
        log_test FAIL "Router pods non fonctionnels"
    fi
    
    # Test de la console
    local console_route=$(oc get route -n openshift-console console -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
    if [[ -n "$console_route" ]]; then
        log_test PASS "Console route: $console_route"
        
        # Test HTTP
        if curl -sk "https://${console_route}" --connect-timeout 5 &>/dev/null; then
            log_test PASS "Console accessible via HTTPS"
        else
            log_test WARN "Console non accessible (vérifiez le DNS/firewall)"
        fi
    else
        log_test FAIL "Console route non trouvée"
    fi
}

test_storage() {
    print_section "STOCKAGE"
    
    # StorageClasses
    local sc_count=$(oc get storageclass --no-headers 2>/dev/null | wc -l)
    if [[ "$sc_count" -gt 0 ]]; then
        log_test PASS "StorageClasses disponibles: $sc_count"
        
        local default_sc=$(oc get storageclass -o json 2>/dev/null | \
            jq -r '.items[] | select(.metadata.annotations["storageclass.kubernetes.io/is-default-class"]=="true") | .metadata.name' 2>/dev/null || true)
        if [[ -n "$default_sc" ]]; then
            log_test PASS "Default StorageClass: $default_sc"
        else
            log_test WARN "Aucune StorageClass par défaut"
        fi
    else
        log_test WARN "Aucune StorageClass configurée"
    fi
    
    # PVs
    local pv_count=$(oc get pv --no-headers 2>/dev/null | wc -l)
    log_test PASS "PersistentVolumes: $pv_count"
}

test_authentication() {
    print_section "AUTHENTIFICATION"
    
    # Test de connexion
    if oc whoami &>/dev/null; then
        local current_user=$(oc whoami)
        log_test PASS "Authentifié en tant que: $current_user"
    else
        log_test FAIL "Non authentifié"
    fi
    
    # OAuth
    local oauth_pods=$(oc get pods -n openshift-authentication --no-headers 2>/dev/null | grep -c "Running" || true)
    if [[ "$oauth_pods" -gt 0 ]]; then
        log_test PASS "OAuth pods running: $oauth_pods"
    else
        log_test WARN "OAuth pods non fonctionnels"
    fi
}

test_monitoring() {
    print_section "MONITORING"
    
    # Prometheus
    local prom_pods=$(oc get pods -n openshift-monitoring --no-headers 2>/dev/null | grep "prometheus-" | grep -c "Running" || true)
    if [[ "$prom_pods" -gt 0 ]]; then
        log_test PASS "Prometheus pods running: $prom_pods"
    else
        log_test WARN "Prometheus non fonctionnel"
    fi
    
    # Alertmanager
    local alert_pods=$(oc get pods -n openshift-monitoring --no-headers 2>/dev/null | grep "alertmanager-" | grep -c "Running" || true)
    if [[ "$alert_pods" -gt 0 ]]; then
        log_test PASS "Alertmanager pods running: $alert_pods"
    else
        log_test WARN "Alertmanager non fonctionnel"
    fi
}

test_hypershift() {
    print_section "HYPERSHIFT"
    
    # Vérification de l'opérateur HyperShift
    if oc get crd hostedclusters.hypershift.openshift.io &>/dev/null; then
        log_test PASS "HyperShift CRDs installés"
        
        local hs_pods=$(oc get pods -n hypershift --no-headers 2>/dev/null | grep -c "Running" || true)
        if [[ "$hs_pods" -gt 0 ]]; then
            log_test PASS "HyperShift operator running"
        else
            log_test WARN "HyperShift operator non fonctionnel"
        fi
        
        # Hosted clusters
        local hc_count=$(oc get hostedclusters -A --no-headers 2>/dev/null | wc -l)
        log_test PASS "Hosted Clusters: $hc_count"
    else
        log_test WARN "HyperShift non installé"
    fi
}

#-------------------------------------------------------------------------------
# Rapport final
#-------------------------------------------------------------------------------

print_summary() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}                         RÉSUMÉ DE VALIDATION${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${GREEN}✓ Tests réussis:${NC}    $TESTS_PASSED"
    echo -e "  ${RED}✗ Tests échoués:${NC}    $TESTS_FAILED"
    echo -e "  ${YELLOW}⚠ Avertissements:${NC}  $TESTS_WARNING"
    echo ""
    
    local total=$((TESTS_PASSED + TESTS_FAILED + TESTS_WARNING))
    local score=$((TESTS_PASSED * 100 / total))
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "  ${GREEN}${BOLD}STATUT: CLUSTER OPÉRATIONNEL${NC} (Score: ${score}%)"
    elif [[ $TESTS_FAILED -le 2 ]]; then
        echo -e "  ${YELLOW}${BOLD}STATUT: CLUSTER PARTIELLEMENT OPÉRATIONNEL${NC} (Score: ${score}%)"
    else
        echo -e "  ${RED}${BOLD}STATUT: CLUSTER NON OPÉRATIONNEL${NC} (Score: ${score}%)"
    fi
    echo ""
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

main() {
    echo ""
    echo -e "${BOLD}${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════════╗"
    echo "║          VALIDATION DU CLUSTER OPENSHIFT BARE METAL               ║"
    echo "╚═══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Vérification du kubeconfig
    if [[ ! -f "$KUBECONFIG" ]]; then
        echo -e "${RED}ERREUR: Kubeconfig non trouvé: $KUBECONFIG${NC}"
        exit 1
    fi
    
    test_nodes
    test_cluster_operators
    test_etcd
    test_networking
    test_ingress
    test_storage
    test_authentication
    test_monitoring
    test_hypershift
    
    print_summary
    
    # Code de retour
    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
