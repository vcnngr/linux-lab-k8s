#!/bin/bash
# Script per configurare SSH keys dal secret

set -e

SSH_DIR="/home/student/.ssh"

# Crea directory se non esiste
mkdir -p ${SSH_DIR}
chmod 700 ${SSH_DIR}

# Se esistono chiavi nel mount del secret, copiale
if [ -d "/tmp/ssh-keys" ]; then
    echo "Configuring SSH keys from secret..."
    
    # ==========================================
    # CLIENT: Copia chiave PRIVATA
    # ==========================================
    if [ "$CONTAINER_ROLE" = "client" ]; then
        if [ -f "/tmp/ssh-keys/id_rsa" ]; then
            cp /tmp/ssh-keys/id_rsa ${SSH_DIR}/id_rsa
            chmod 600 ${SSH_DIR}/id_rsa
            chown student:student ${SSH_DIR}/id_rsa
            echo "✓ Private key configured (client)"
        fi
        
        if [ -f "/tmp/ssh-keys/id_rsa.pub" ]; then
            cp /tmp/ssh-keys/id_rsa.pub ${SSH_DIR}/id_rsa.pub
            chmod 644 ${SSH_DIR}/id_rsa.pub
            chown student:student ${SSH_DIR}/id_rsa.pub
            echo "✓ Public key configured (client)"
        fi
    fi
    
    # ==========================================
    # SERVER: Copia chiave PUBBLICA in authorized_keys
    # ==========================================
    if [ "$CONTAINER_ROLE" = "server" ]; then
        if [ -f "/tmp/ssh-keys/id_rsa.pub" ]; then
            # Usa >> per AGGIUNGERE, non sovrascrivere
            cat /tmp/ssh-keys/id_rsa.pub >> ${SSH_DIR}/authorized_keys
            chmod 600 ${SSH_DIR}/authorized_keys
            chown student:student ${SSH_DIR}/authorized_keys
            echo "✓ Public key added to authorized_keys (server)"
        fi
    fi
    
    # ==========================================
    # TUTTI: Copia known_hosts (se presente)
    # ==========================================
    if [ -f "/tmp/ssh-keys/known_hosts" ]; then
        cp /tmp/ssh-keys/known_hosts ${SSH_DIR}/known_hosts
        chmod 644 ${SSH_DIR}/known_hosts
        chown student:student ${SSH_DIR}/known_hosts
        echo "✓ known_hosts configured"
    fi
else
    echo "No SSH keys directory found at /tmp/ssh-keys"
fi

# ==========================================
# OWNERSHIP: Solo su file che abbiamo creato
# ==========================================
# NON fare chown -R perché il file 'config' è montato da ConfigMap (read-only)
# Cambia ownership solo dei file specifici che abbiamo copiato

# Assicura che la directory .ssh appartenga a student
chown student:student ${SSH_DIR}

# Cambia ownership solo dei file che esistono E che NON sono mount
if [ -f "${SSH_DIR}/id_rsa" ]; then
    chown student:student ${SSH_DIR}/id_rsa
fi

if [ -f "${SSH_DIR}/id_rsa.pub" ]; then
    chown student:student ${SSH_DIR}/id_rsa.pub
fi

if [ -f "${SSH_DIR}/authorized_keys" ]; then
    chown student:student ${SSH_DIR}/authorized_keys
fi

if [ -f "${SSH_DIR}/known_hosts" ]; then
    chown student:student ${SSH_DIR}/known_hosts
fi

# Il file 'config' è montato da ConfigMap, non toccare!
# Kubernetes gestisce automaticamente i permessi dei ConfigMap mount

echo "SSH keys setup completed"
