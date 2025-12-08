#!/bin/bash
#===============================================================================
# Module: generate_install_config.sh
# Description: Génération du fichier install-config.yaml
#===============================================================================

generate_install_config() {
    log INFO "Génération du fichier install-config.yaml..."
    
    local install_dir="${WORK_DIR}/install"
    mkdir -p "$install_dir"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "[DRY-RUN] Génération install-config.yaml"
        return
    fi
    
    local cluster_name=$(yq e '.cluster.name' "$CONFIG_FILE")
    local base_domain=$(yq e '.cluster.baseDomain' "$CONFIG_FILE")
    local api_vip=$(yq e '.network.vips.api' "$CONFIG_FILE")
    local ingress_vip=$(yq e '.network.vips.ingress' "$CONFIG_FILE")
    local pull_secret_file=$(yq e '.cluster.pullSecretFile' "$CONFIG_FILE")
    local ssh_key_file=$(yq e '.cluster.sshKeyFile' "$CONFIG_FILE")
    
    local master_count=$(yq e '.nodes.masters | length' "$CONFIG_FILE")
    local worker_count=$(yq e '.nodes.workers | length' "$CONFIG_FILE")
    
    # Lecture du pull secret
    if [[ ! -f "$pull_secret_file" ]]; then
        log ERROR "Fichier pull secret non trouvé: $pull_secret_file"
        exit 1
    fi
    local pull_secret=$(cat "$pull_secret_file" | tr -d '\n')
    
    # Lecture de la clé SSH
    if [[ ! -f "$ssh_key_file" ]]; then
        log ERROR "Fichier clé SSH non trouvé: $ssh_key_file"
        exit 1
    fi
    local ssh_key=$(cat "$ssh_key_file")
    
    # Début du fichier install-config.yaml
    cat > "${install_dir}/install-config.yaml" << EOF
apiVersion: v1
baseDomain: ${base_domain}
metadata:
  name: ${cluster_name}

compute:
- name: worker
  replicas: ${worker_count}

controlPlane:
  name: master
  replicas: ${master_count}
  platform:
    baremetal: {}

networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  serviceNetwork:
  - 172.30.0.0/16
  networkType: OVNKubernetes

platform:
  baremetal:
    apiVIPs:
    - ${api_vip}
    ingressVIPs:
    - ${ingress_vip}
    hosts:
EOF

    # Ajout du bootstrap
    local bootstrap_hostname=$(yq e '.nodes.bootstrap.hostname' "$CONFIG_FILE")
    local bootstrap_mac=$(yq e '.nodes.bootstrap.mac' "$CONFIG_FILE")
    local bootstrap_bmc=$(yq e '.nodes.bootstrap.bmc.address' "$CONFIG_FILE")
    local bootstrap_bmc_user=$(yq e '.nodes.bootstrap.bmc.username' "$CONFIG_FILE")
    local bootstrap_bmc_pass=$(yq e '.nodes.bootstrap.bmc.password' "$CONFIG_FILE")
    local bootstrap_disk=$(yq e '.nodes.bootstrap.rootDevice // "/dev/sda"' "$CONFIG_FILE")
    
    cat >> "${install_dir}/install-config.yaml" << EOF
    # Bootstrap
    - name: bootstrap
      role: bootstrap
      bmc:
        address: ${bootstrap_bmc}
        username: ${bootstrap_bmc_user}
        password: ${bootstrap_bmc_pass}
      bootMACAddress: ${bootstrap_mac}
      rootDeviceHints:
        deviceName: "${bootstrap_disk}"
EOF

    # Ajout des masters
    for ((i=0; i<master_count; i++)); do
        local master_name=$(yq e ".nodes.masters[$i].hostname" "$CONFIG_FILE" | cut -d'.' -f1)
        local master_mac=$(yq e ".nodes.masters[$i].mac" "$CONFIG_FILE")
        local master_bmc=$(yq e ".nodes.masters[$i].bmc.address" "$CONFIG_FILE")
        local master_bmc_user=$(yq e ".nodes.masters[$i].bmc.username" "$CONFIG_FILE")
        local master_bmc_pass=$(yq e ".nodes.masters[$i].bmc.password" "$CONFIG_FILE")
        local master_disk=$(yq e ".nodes.masters[$i].rootDevice // \"/dev/sda\"" "$CONFIG_FILE")
        
        cat >> "${install_dir}/install-config.yaml" << EOF
    # Master ${i}
    - name: ${master_name}
      role: master
      bmc:
        address: ${master_bmc}
        username: ${master_bmc_user}
        password: ${master_bmc_pass}
      bootMACAddress: ${master_mac}
      rootDeviceHints:
        deviceName: "${master_disk}"
EOF
    done
    
    # Ajout des workers
    for ((i=0; i<worker_count; i++)); do
        local worker_name=$(yq e ".nodes.workers[$i].hostname" "$CONFIG_FILE" | cut -d'.' -f1)
        local worker_mac=$(yq e ".nodes.workers[$i].mac" "$CONFIG_FILE")
        local worker_bmc=$(yq e ".nodes.workers[$i].bmc.address" "$CONFIG_FILE")
        local worker_bmc_user=$(yq e ".nodes.workers[$i].bmc.username" "$CONFIG_FILE")
        local worker_bmc_pass=$(yq e ".nodes.workers[$i].bmc.password" "$CONFIG_FILE")
        local worker_disk=$(yq e ".nodes.workers[$i].rootDevice // \"/dev/sda\"" "$CONFIG_FILE")
        
        cat >> "${install_dir}/install-config.yaml" << EOF
    # Worker ${i}
    - name: ${worker_name}
      role: worker
      bmc:
        address: ${worker_bmc}
        username: ${worker_bmc_user}
        password: ${worker_bmc_pass}
      bootMACAddress: ${worker_mac}
      rootDeviceHints:
        deviceName: "${worker_disk}"
EOF
    done
    
    # Ajout du pull secret et de la clé SSH
    cat >> "${install_dir}/install-config.yaml" << EOF

pullSecret: '${pull_secret}'
sshKey: '${ssh_key}'
EOF

    # Sauvegarde du fichier (sera supprimé après génération des ignition)
    cp "${install_dir}/install-config.yaml" "${WORK_DIR}/install-config.yaml.backup"
    
    log SUCCESS "Fichier install-config.yaml généré"
    log DEBUG "Backup sauvegardé dans: ${WORK_DIR}/install-config.yaml.backup"
}
