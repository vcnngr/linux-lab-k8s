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
    # TUTTI: Copia known_hosts e config
    # ==========================================
    if [ -f "/tmp/ssh-keys/known_hosts" ]; then
        cp /tmp/ssh-keys/known_hosts ${SSH_DIR}/known_hosts
        chmod 644 ${SSH_DIR}/known_hosts
        chown student:student ${SSH_DIR}/known_hosts
        echo "✓ known_hosts configured"
    fi
    
    # Configura SSH config per client
    if [ "$CONTAINER_ROLE" = "client" ] && [ -f "/home/student/.ssh/config" ]; then
        chmod 600 ${SSH_DIR}/config
        chown student:student ${SSH_DIR}/config
        echo "✓ SSH config configured"
    fi
    
    # Assicurati ownership corretto
    chown -R student:student ${SSH_DIR}
else
    echo "No SSH keys directory found at /tmp/ssh-keys"
fi

echo "SSH keys setup completed"