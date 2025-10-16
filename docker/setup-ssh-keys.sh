#!/bin/bash
# Script per configurare SSH keys dal secret

set -e

SSH_DIR="/home/student/.ssh"

# Se esistono chiavi nel mount del secret, copiale
if [ -d "/tmp/ssh-keys" ]; then
    echo "Configuring SSH keys from secret..."
    
    # Copia chiavi private (solo per client)
    if [ -f "/tmp/ssh-keys/id_rsa" ]; then
        cp /tmp/ssh-keys/id_rsa ${SSH_DIR}/id_rsa
        chmod 600 ${SSH_DIR}/id_rsa
        chown student:student ${SSH_DIR}/id_rsa
        echo "Private key configured"
    fi
    
    # Copia chiavi pubbliche (per server)
    if [ -f "/tmp/ssh-keys/id_rsa.pub" ]; then
        cp /tmp/ssh-keys/id_rsa.pub ${SSH_DIR}/authorized_keys
        chmod 600 ${SSH_DIR}/authorized_keys
        chown student:student ${SSH_DIR}/authorized_keys
        echo "Public key configured in authorized_keys"
    fi
    
    # Copia known_hosts se presente
    if [ -f "/tmp/ssh-keys/known_hosts" ]; then
        cp /tmp/ssh-keys/known_hosts ${SSH_DIR}/known_hosts
        chmod 644 ${SSH_DIR}/known_hosts
        chown student:student ${SSH_DIR}/known_hosts
    fi
fi

echo "SSH keys setup completed"