# OpenShift Bare Metal Installation Automation

<div align="center">

![OpenShift](https://img.shields.io/badge/OpenShift-4.17-EE0000?style=for-the-badge&logo=redhatopenshift&logoColor=white)
![RHCOS](https://img.shields.io/badge/RHCOS-Bare%20Metal-CC0000?style=for-the-badge&logo=redhat&logoColor=white)
![HyperShift](https://img.shields.io/badge/HyperShift-HCP-00ADD8?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

**Scripts d'automatisation pour le déploiement d'OpenShift Container Platform sur infrastructure bare metal avec support HyperShift**

[Documentation](#documentation) • [Installation](#installation-rapide) • [Configuration](#configuration) • [Support](#support)

</div>

---

## 📋 Vue d'ensemble

Ce projet fournit une suite complète de scripts pour automatiser le déploiement d'OpenShift Container Platform sur des serveurs physiques (bare metal), incluant:

- ✅ Configuration automatique du serveur bastion (DHCP, TFTP, HTTP, HAProxy)
- ✅ Génération des fichiers Ignition et configurations PXE
- ✅ Support du boot réseau BIOS et UEFI
- ✅ Installation de HyperShift pour la gestion multi-cluster
- ✅ Scripts de validation post-installation
- ✅ Création de Hosted Clusters automatisée

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    INFRASTRUCTURE OPENSHIFT                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────┐     ┌───────────────────────────────────────────────┐  │
│  │ BASTION │     │            MANAGEMENT CLUSTER                  │  │
│  │         │     │  ┌───────┐ ┌───────┐ ┌───────┐                │  │
│  │ • DHCP  │     │  │Master │ │Master │ │Master │                │  │
│  │ • TFTP  │────▶│  │  -0   │ │  -1   │ │  -2   │                │  │
│  │ • HTTP  │     │  └───────┘ └───────┘ └───────┘                │  │
│  │ • HAProxy│    │                                                │  │
│  └─────────┘     │  ┌───────┐ ┌───────┐ ┌───────┐                │  │
│                  │  │Worker │ │Worker │ │Worker │                │  │
│                  │  │  -0   │ │  -1   │ │  -2   │                │  │
│                  │  └───────┘ └───────┘ └───────┘                │  │
│                  │                                                │  │
│                  │  ┌─────────────────────────────────────────┐  │  │
│                  │  │             HYPERSHIFT                   │  │  │
│                  │  │  • Hosted Cluster Dev                    │  │  │
│                  │  │  • Hosted Cluster Prod                   │  │  │
│                  │  └─────────────────────────────────────────┘  │  │
│                  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

## 📁 Structure du Projet

```
Openshif-bare-metal/
├── README.md
├── config/
│   └── cluster-config.yaml.template    # Template de configuration
├── docs/
│   └── OpenShift_BareMetal_Installation_Guide.md
├── scripts/
│   ├── install.sh                      # Script principal
│   ├── create-hosted-cluster.sh        # Création de hosted clusters
│   ├── validate-cluster.sh             # Validation post-installation
│   └── modules/
│       ├── configure_dhcp.sh
│       ├── configure_dns.sh
│       ├── configure_firewall.sh
│       ├── configure_haproxy.sh
│       ├── configure_http.sh
│       ├── configure_network.sh
│       ├── configure_pxe.sh
│       ├── configure_tftp.sh
│       ├── download_binaries.sh
│       ├── download_rhcos.sh
│       ├── generate_install_config.sh
│       └── install_hypershift.sh
```

## ⚡ Installation Rapide

### Prérequis

- Serveur Bastion avec RHEL 8.x ou 9.x
- Accès root
- Connexion Internet
- Pull Secret Red Hat ([Obtenir ici](https://cloud.redhat.com/openshift/install/pull-secret))

### Étapes

```bash
# 1. Cloner le projet
git clone <repository-url>
cd Openshif-bare-metal

# 2. Copier et éditer la configuration
cp config/cluster-config.yaml.template config/cluster-config.yaml
vim config/cluster-config.yaml

# 3. Placer le pull secret
cp ~/pull-secret.json /opt/openshift/pull-secret.json

# 4. Lancer l'installation
chmod +x scripts/*.sh scripts/modules/*.sh
sudo ./scripts/install.sh

# 5. Suivre les instructions à l'écran pour le boot PXE des serveurs
```

## ⚙️ Configuration

### Fichier de Configuration Principal

Éditez `config/cluster-config.yaml` avec les informations de votre infrastructure:

```yaml
cluster:
  name: ocp
  baseDomain: example.com
  version: "4.17"

network:
  baremetal:
    subnet: 192.168.1.0/24
    gateway: 192.168.1.1
  vips:
    api: 192.168.1.5
    ingress: 192.168.1.6

nodes:
  masters:
    - hostname: master-0.ocp.example.com
      ip: 192.168.1.100
      mac: "AA:BB:CC:DD:EE:01"
      bmc:
        address: redfish://192.168.1.51/redfish/v1/Systems/1
        username: admin
        password: secret
```

### Options du Script Principal

```bash
./scripts/install.sh [OPTIONS]

Options:
  -c, --config <file>     Fichier de configuration personnalisé
  -p, --phase <phase>     Exécuter une phase spécifique:
                          prereq, bastion, services, ignition, deploy, validate, hypershift
  -s, --skip-prereq       Ignorer la vérification des prérequis
  -n, --dry-run           Mode simulation
  -v, --verbose           Mode verbeux
  -h, --help              Afficher l'aide
```

### Exemples d'Utilisation

```bash
# Installation complète
sudo ./scripts/install.sh

# Mode dry-run (simulation)
sudo ./scripts/install.sh --dry-run --verbose

# Exécuter uniquement la configuration du bastion
sudo ./scripts/install.sh --phase bastion

# Utiliser un fichier de configuration personnalisé
sudo ./scripts/install.sh --config /path/to/my-config.yaml

# Valider le cluster après installation
./scripts/validate-cluster.sh

# Créer un hosted cluster HyperShift
./scripts/create-hosted-cluster.sh --name dev-cluster --node-pool-replicas 3
```

## 📊 Phases d'Installation

| Phase | Description | Durée estimée |
|-------|-------------|---------------|
| `prereq` | Vérification des prérequis | 1 min |
| `bastion` | Configuration du serveur bastion | 10 min |
| `services` | Configuration DHCP, TFTP, HTTP, HAProxy | 5 min |
| `ignition` | Génération des fichiers Ignition | 2 min |
| `deploy` | Déploiement du cluster (manuel PXE boot) | 60-90 min |
| `validate` | Validation post-installation | 5 min |
| `hypershift` | Installation HyperShift | 10 min |

## 🔧 Dépannage

### Logs

```bash
# Logs d'installation
tail -f /var/log/openshift-install/install-*.log

# Logs du bootstrap (via SSH)
ssh core@bootstrap journalctl -b -f -u bootkube.service

# Logs des services bastion
journalctl -u dhcpd -f
journalctl -u httpd -f
journalctl -u haproxy -f
```

### Commandes Utiles

```bash
# Vérifier l'état du cluster
export KUBECONFIG=/opt/openshift/install/auth/kubeconfig
oc get nodes
oc get clusteroperators
oc get pods -A

# Approuver les CSR en attente
oc get csr -o name | xargs oc adm certificate approve

# Vérifier les services bastion
systemctl status dhcpd tftp.socket httpd haproxy
```

## 📚 Documentation

- [Guide d'Installation Complet](docs/OpenShift_BareMetal_Installation_Guide.md)
- [Documentation OpenShift](https://docs.openshift.com)
- [Documentation HyperShift](https://hypershift-docs.netlify.app)

## 🤝 Support

Pour toute question ou problème:

1. Consultez la [documentation](docs/)
2. Vérifiez les logs d'installation
3. Ouvrez une issue sur le repository

## 📝 License

MIT License - voir [LICENSE](LICENSE) pour plus de détails.

---

<div align="center">

**Développé avec ❤️ par l'équipe Infrastructure**

</div>
