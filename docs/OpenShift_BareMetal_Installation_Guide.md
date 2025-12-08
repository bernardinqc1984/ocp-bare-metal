# Guide d'Installation OpenShift Container Platform sur Infrastructure Bare Metal

<div align="center">

**Document Technique - Version 1.0**

*Red Hat OpenShift Container Platform 4.17*  
*avec Hosted Control Planes (HyperShift)*

---

**Classification :** Interne  
**Date de publication :** Décembre 2024  
**Dernière révision :** Décembre 2024

</div>

---

## Résumé Exécutif

Ce document présente la procédure complète de déploiement d'**OpenShift Container Platform** sur infrastructure bare metal, intégrant la technologie **HyperShift** (Hosted Control Planes) pour une gestion multi-cluster optimisée.

### Bénéfices Clés

| Avantage | Impact Business |
|----------|-----------------|
| **Réduction des coûts** | Diminution de 60% des ressources nécessaires pour les control planes |
| **Time-to-Market** | Provisionnement de nouveaux clusters en minutes vs heures |
| **Scalabilité** | Support de 100+ clusters depuis un seul management cluster |
| **Haute Disponibilité** | Architecture redondante avec SLA 99.9% |
| **Multi-tenancy** | Isolation complète entre les équipes/projets |

### Périmètre du Projet

- Déploiement d'un cluster OpenShift management hautement disponible
- Configuration d'un serveur bastion pour provisionnement PXE automatisé
- Implémentation d'HyperShift pour l'orchestration multi-cluster
- Utilisation de Red Hat Enterprise Linux CoreOS (RHCOS)

---

## Table des Matières

1. [Architecture de la Solution](#1-architecture-de-la-solution)
2. [Prérequis et Dimensionnement](#2-prérequis-et-dimensionnement)
3. [Topologie Réseau](#3-topologie-réseau)
4. [Procédure d'Installation](#4-procédure-dinstallation)
5. [Déploiement HyperShift](#5-déploiement-hypershift)
6. [Validation et Tests](#6-validation-et-tests)
7. [Opérations et Maintenance](#7-opérations-et-maintenance)
8. [Annexes](#8-annexes)

---

## 1. Architecture de la Solution

### 1.1 Vue d'Ensemble

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        INFRASTRUCTURE OPENSHIFT                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────┐     ┌─────────────────────────────────────────────────┐    │
│  │   BASTION   │     │              MANAGEMENT CLUSTER                  │    │
│  │             │     │  ┌─────────┐ ┌─────────┐ ┌─────────┐            │    │
│  │  • DHCP     │     │  │Master-0 │ │Master-1 │ │Master-2 │            │    │
│  │  • TFTP     │     │  └─────────┘ └─────────┘ └─────────┘            │    │
│  │  • HTTP     │     │                                                  │    │
│  │  • HAProxy  │     │  ┌─────────┐ ┌─────────┐ ┌─────────┐            │    │
│  │  • DNS      │     │  │Worker-0 │ │Worker-1 │ │Worker-2 │            │    │
│  └──────┬──────┘     │  └─────────┘ └─────────┘ └─────────┘            │    │
│         │            └─────────────────────────────────────────────────┘    │
│         │                                                                    │
│         │            ┌─────────────────────────────────────────────────┐    │
│         │            │              HYPERSHIFT (HCP)                    │    │
│         │            │  ┌───────────────┐  ┌───────────────┐           │    │
│         └───────────▶│  │ Hosted        │  │ Hosted        │           │    │
│                      │  │ Cluster 01    │  │ Cluster 02    │           │    │
│                      │  │ (Équipe Dev)  │  │ (Équipe Prod) │           │    │
│                      │  └───────────────┘  └───────────────┘           │    │
│                      └─────────────────────────────────────────────────┘    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Composants Principaux

| Composant | Rôle | Technologie |
|-----------|------|-------------|
| **Serveur Bastion** | Infrastructure de provisionnement | RHEL 9.x |
| **Control Plane** | Orchestration Kubernetes | RHCOS + etcd |
| **Workers** | Exécution des workloads | RHCOS |
| **HyperShift** | Hosted Control Planes | OpenShift Operator |
| **Load Balancer** | Distribution du trafic | HAProxy |

---

## 2. Prérequis et Dimensionnement

### 2.1 Spécifications Matérielles

#### Nœuds Control Plane (3 requis)

| Ressource | Minimum | Recommandé Production |
|-----------|---------|----------------------|
| **CPU** | 8 vCPU | 16 vCPU |
| **RAM** | 16 GB | 32 GB |
| **Stockage** | 120 GB | 500 GB NVMe |
| **Réseau** | 10 Gbps | 2x 10 Gbps (LAG) |
| **Latence disque** | < 10ms p99 fsync | < 5ms p99 fsync |

#### Nœuds Worker (3+ recommandés)

| Ressource | Minimum | Recommandé Production |
|-----------|---------|----------------------|
| **CPU** | 4 vCPU | 16 vCPU |
| **RAM** | 8 GB | 32 GB |
| **Stockage** | 120 GB | 500 GB SSD |
| **Réseau** | 10 Gbps | 2x 10 Gbps (LAG) |

#### Serveur Bastion

| Ressource | Spécification |
|-----------|---------------|
| **OS** | RHEL 8.x ou 9.x |
| **CPU** | 4 vCPU |
| **RAM** | 8 GB |
| **Stockage** | 200 GB |
| **Réseau** | 2x 1 Gbps (baremetal + provisioning) |

### 2.2 Exigences Techniques

#### Architecture Processeur
- x86_64 ou aarch64
- Extensions de virtualisation (Intel VT-x / AMD-V)
- Compatible RHEL 9.2+ pour OpenShift 4.13+

#### Gestion Out-of-Band (BMC)
- Baseboard Management Controller requis
- Protocole **Redfish** (recommandé) ou IPMI
- Connectivité réseau BMC depuis le bastion

#### Firmware
- UEFI obligatoire (requis pour IPv6)
- Secure Boot supporté
- Boot PXE activé

---

## 3. Topologie Réseau

### 3.1 Architecture Réseau

```
┌─────────────────────────────────────────────────────────────────────┐
│                         RÉSEAU BAREMETAL                            │
│                         192.168.1.0/24                              │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                                                               │  │
│  │   API VIP ──────────────── 192.168.1.5                       │  │
│  │   Ingress VIP ────────────  192.168.1.6                       │  │
│  │   Bastion ─────────────── 192.168.1.10                       │  │
│  │   Masters ────────────── 192.168.1.100-102                   │  │
│  │   Workers ────────────── 192.168.1.200-202                   │  │
│  │                                                               │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    │
┌─────────────────────────────────────────────────────────────────────┐
│                      RÉSEAU PROVISIONING                            │
│                         172.22.0.0/24                               │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                                                               │  │
│  │   Bastion (DHCP/TFTP) ──── 172.22.0.1                        │  │
│  │   Bootstrap ──────────── 172.22.0.20                         │  │
│  │   Masters ────────────── 172.22.0.100-102                    │  │
│  │   Workers ────────────── 172.22.0.200-202                    │  │
│  │                                                               │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

### 3.2 Plan d'Adressage IP

| Composant | Hostname | IP Baremetal | IP Provisioning | MAC Address |
|-----------|----------|--------------|-----------------|-------------|
| Bastion | bastion.ocp.example.com | 192.168.1.10 | 172.22.0.1 | - |
| API VIP | api.ocp.example.com | 192.168.1.5 | - | - |
| Ingress VIP | *.apps.ocp.example.com | 192.168.1.6 | - | - |
| Bootstrap | bootstrap.ocp.example.com | 192.168.1.20 | 172.22.0.20 | AA:BB:CC:DD:EE:00 |
| Master-0 | master-0.ocp.example.com | 192.168.1.100 | 172.22.0.100 | AA:BB:CC:DD:EE:01 |
| Master-1 | master-1.ocp.example.com | 192.168.1.101 | 172.22.0.101 | AA:BB:CC:DD:EE:02 |
| Master-2 | master-2.ocp.example.com | 192.168.1.102 | 172.22.0.102 | AA:BB:CC:DD:EE:03 |
| Worker-0 | worker-0.ocp.example.com | 192.168.1.200 | 172.22.0.200 | AA:BB:CC:DD:EE:10 |
| Worker-1 | worker-1.ocp.example.com | 192.168.1.201 | 172.22.0.201 | AA:BB:CC:DD:EE:11 |
| Worker-2 | worker-2.ocp.example.com | 192.168.1.202 | 172.22.0.202 | AA:BB:CC:DD:EE:12 |

### 3.3 Configuration DNS Requise

#### Enregistrements A (Forward)
```dns
; API et Ingress
api.ocp.example.com.              IN  A   192.168.1.5
api-int.ocp.example.com.          IN  A   192.168.1.5
*.apps.ocp.example.com.           IN  A   192.168.1.6

; Nœuds
bootstrap.ocp.example.com.        IN  A   192.168.1.20
master-0.ocp.example.com.         IN  A   192.168.1.100
master-1.ocp.example.com.         IN  A   192.168.1.101
master-2.ocp.example.com.         IN  A   192.168.1.102
worker-0.ocp.example.com.         IN  A   192.168.1.200
worker-1.ocp.example.com.         IN  A   192.168.1.201
worker-2.ocp.example.com.         IN  A   192.168.1.202
```

#### Enregistrements PTR (Reverse)
```dns
5.1.168.192.in-addr.arpa.         IN  PTR api.ocp.example.com.
100.1.168.192.in-addr.arpa.       IN  PTR master-0.ocp.example.com.
```

#### Enregistrements SRV (etcd)
```dns
_etcd-server-ssl._tcp.ocp.example.com.  IN  SRV  0 10 2380 master-0.ocp.example.com.
_etcd-server-ssl._tcp.ocp.example.com.  IN  SRV  0 10 2380 master-1.ocp.example.com.
_etcd-server-ssl._tcp.ocp.example.com.  IN  SRV  0 10 2380 master-2.ocp.example.com.
```

### 3.4 Ports Réseau Requis

| Port | Protocole | Source | Destination | Description |
|------|-----------|--------|-------------|-------------|
| 6443 | TCP | All | Masters | Kubernetes API |
| 22623 | TCP | Nodes | Masters | Machine Config Server |
| 2379-2380 | TCP | Masters | Masters | etcd cluster |
| 80 | TCP | External | Workers | HTTP Ingress |
| 443 | TCP | External | Workers | HTTPS Ingress |
| 69 | UDP | Nodes | Bastion | TFTP (PXE) |
| 67-68 | UDP | Nodes | Bastion | DHCP |

---

## 4. Procédure d'Installation

### 4.1 Phase 1 : Préparation du Bastion

#### Étapes Principales
1. Installation de RHEL 8.x/9.x
2. Configuration réseau (dual-homed)
3. Installation des services (DHCP, TFTP, HTTP, HAProxy, DNS)
4. Téléchargement des binaires OpenShift
5. Téléchargement des images RHCOS

### 4.2 Phase 2 : Configuration des Services

#### Services à Configurer
- **DHCP** : Attribution d'adresses sur le réseau provisioning
- **TFTP** : Serveur PXE pour boot réseau
- **HTTP** : Hébergement des images et fichiers ignition
- **HAProxy** : Load balancing API et Ingress
- **DNS** : Résolution de noms (optionnel, peut être externe)

### 4.3 Phase 3 : Génération des Configurations

1. Création du fichier `install-config.yaml`
2. Génération des manifestes Kubernetes
3. Génération des fichiers Ignition (bootstrap, master, worker)
4. Déploiement sur le serveur HTTP

### 4.4 Phase 4 : Déploiement du Cluster

```
┌─────────────────────────────────────────────────────────────────────┐
│                    SÉQUENCE DE DÉPLOIEMENT                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐         │
│   │  Boot   │───▶│ Install │───▶│  Wait   │───▶│ Remove  │         │
│   │Bootstrap│    │ Masters │    │Complete │    │Bootstrap│         │
│   └─────────┘    └─────────┘    └─────────┘    └─────────┘         │
│       │              │              │                                │
│       │              │              │         ┌─────────┐           │
│       │              │              └────────▶│ Install │           │
│       │              │                        │ Workers │           │
│       │              │                        └─────────┘           │
│       │              │                             │                 │
│       ▼              ▼                             ▼                 │
│   [30 min]       [15 min]                     [20 min]              │
│                                                                      │
│   TEMPS TOTAL ESTIMÉ : ~90 minutes                                  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 4.5 Phase 5 : Validation Post-Installation

- Vérification de l'état des nœuds
- Validation des ClusterOperators
- Tests de connectivité réseau
- Accès à la console web

---

## 5. Déploiement HyperShift

### 5.1 Architecture HyperShift

```
┌─────────────────────────────────────────────────────────────────────┐
│                    MANAGEMENT CLUSTER                                │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                    HyperShift Operator                         │  │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌───────────────┐  │  │
│  │  │ Hosted Cluster  │  │ Hosted Cluster  │  │ Hosted Cluster│  │  │
│  │  │   Control Plane │  │   Control Plane │  │  Control Plane│  │  │
│  │  │   (Namespace)   │  │   (Namespace)   │  │  (Namespace)  │  │  │
│  │  │                 │  │                 │  │               │  │  │
│  │  │  • API Server   │  │  • API Server   │  │ • API Server  │  │  │
│  │  │  • etcd         │  │  • etcd         │  │ • etcd        │  │  │
│  │  │  • Controllers  │  │  • Controllers  │  │ • Controllers │  │  │
│  │  └────────┬────────┘  └────────┬────────┘  └───────┬───────┘  │  │
│  │           │                    │                    │          │  │
│  └───────────┼────────────────────┼────────────────────┼──────────┘  │
│              │                    │                    │             │
└──────────────┼────────────────────┼────────────────────┼─────────────┘
               │                    │                    │
               ▼                    ▼                    ▼
        ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
        │   Workers    │    │   Workers    │    │   Workers    │
        │  Cluster A   │    │  Cluster B   │    │  Cluster C   │
        │  (3 nodes)   │    │  (5 nodes)   │    │  (10 nodes)  │
        └──────────────┘    └──────────────┘    └──────────────┘
```

### 5.2 Avantages du Modèle HyperShift

| Caractéristique | Architecture Classique | Architecture HyperShift |
|-----------------|----------------------|------------------------|
| **Control Plane** | 3 VMs dédiées | Pods dans management cluster |
| **Temps de provisionnement** | 45-60 minutes | 10-15 minutes |
| **Coût infrastructure** | Élevé | Réduit de 60% |
| **Mise à jour CP** | Downtime possible | Zero-downtime |
| **Nombre de clusters** | Limité par infrastructure | 100+ clusters |

### 5.3 Prérequis HyperShift

- Cluster OpenShift 4.14+ fonctionnel
- Stockage persistant (ODF, NFS, ou équivalent)
- Accès administrateur
- Agent Service configuré pour bare metal

### 5.4 Processus de Déploiement

1. Installation de l'opérateur HyperShift via OperatorHub
2. Configuration de l'Agent Service
3. Création des Hosted Clusters
4. Configuration des NodePools
5. Ajout des workers bare metal

---

## 6. Validation et Tests

### 6.1 Checklist de Validation

#### Infrastructure
- [ ] Tous les nœuds en état "Ready"
- [ ] Tous les ClusterOperators "Available"
- [ ] VIPs API et Ingress accessibles
- [ ] DNS résolution correcte

#### Réseau
- [ ] Connectivité pod-to-pod
- [ ] Connectivité pod-to-service
- [ ] Ingress externe fonctionnel

#### Sécurité
- [ ] Certificats TLS valides
- [ ] Authentification opérationnelle
- [ ] RBAC configuré

#### HyperShift
- [ ] Opérateur opérationnel
- [ ] Hosted clusters "Available"
- [ ] NodePools correctement dimensionnés

### 6.2 Tests de Validation

```bash
# Vérification des nœuds
oc get nodes -o wide

# Vérification des opérateurs
oc get clusteroperators

# Test de déploiement application
oc new-project test-validation
oc new-app httpd~https://github.com/sclorg/httpd-ex
oc get pods -w
```

---

## 7. Opérations et Maintenance

### 7.1 Procédures de Mise à Jour

```bash
# Vérifier les mises à jour disponibles
oc adm upgrade

# Appliquer une mise à jour
oc adm upgrade --to=<version>

# Surveiller la progression
watch "oc get clusterversion; oc get co"
```

### 7.2 Backup et Disaster Recovery

- Backup quotidien des configurations etcd
- Snapshots des volumes persistants
- Documentation des procédures de restauration
- Tests de DR trimestriels

### 7.3 Monitoring

- Prometheus pour les métriques
- Alertmanager pour les alertes
- Grafana pour les dashboards
- Log aggregation avec Loki ou EFK

---

## 8. Annexes

### 8.1 Commandes de Dépannage Essentielles

```bash
# Logs bootstrap
ssh core@bootstrap journalctl -b -f -u bootkube.service

# État etcd
oc rsh -n openshift-etcd etcd-master-0 etcdctl member list -w table

# Debug opérateur
oc describe co <operator-name>
```

### 8.2 Contacts et Support

| Type | Contact |
|------|---------|
| Red Hat Support | https://access.redhat.com |
| Documentation | https://docs.openshift.com |
| Community | https://community.redhat.com |

### 8.3 Références Documentaires

- OpenShift Documentation: https://docs.openshift.com
- HyperShift Documentation: https://hypershift-docs.netlify.app
- Red Hat CoreOS: https://docs.openshift.com/container-platform/latest/architecture/architecture-rhcos.html

---

<div align="center">
