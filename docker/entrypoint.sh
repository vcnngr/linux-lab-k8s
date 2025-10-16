#!/bin/bash
set -e

# ==========================================
#  DYNAMIC PASSWORD SETUP
# ==========================================
# Imposta la password dello studente se fornita tramite variabile d'ambiente
# Questo permette di evitare password hardcoded nei Dockerfile
if [ -n "$STUDENT_PASSWORD" ]; then
    echo "student:${STUDENT_PASSWORD}" | chpasswd
    echo "[✓] Student password has been set dynamically."
else
    echo "[!] WARNING: No STUDENT_PASSWORD environment variable set!"
    echo "[!] Student account will have NO password (login disabled)."
fi
# ==========================================

echo "=========================================="
echo "  LINUX LAB CONTAINER STARTING"
echo "=========================================="

# Setup SSH keys se presenti
if [ -d "/tmp/ssh-keys" ]; then
    echo "[1/4] Setting up SSH keys..."
    /usr/local/bin/setup-ssh-keys.sh
else
    echo "[1/4] No SSH keys found, skipping..."
fi

# Genera host keys se non esistono
echo "[2/4] Generating SSH host keys..."
ssh-keygen -A 2>/dev/null || true

# Configura sudoers se necessario
if [ -x /usr/local/bin/sudoers-config.sh ]; then
    echo "[3/4] Configuring sudo permissions..."
    /usr/local/bin/sudoers-config.sh
fi

# Crea file di benvenuto personalizzato
echo "[4/4] Creating welcome message..."
cat > /home/student/welcome.sh << 'EOF'
#!/bin/bash
clear
cat /etc/motd
echo ""
echo "Hostname: $(hostname)"
echo "User: $(whoami)"
echo "Date: $(date)"
echo ""
echo "Quick commands:"
echo "  - cat ~/README.txt        (read instructions)"
echo "  - ssh server1             (connect to server1)"
echo "  - ssh server2             (connect to server2)"
echo "  - htop                    (system monitor)"
echo ""
EOF

chmod +x /home/student/welcome.sh
chown student:student /home/student/welcome.sh

# Aggiungi welcome script a bashrc se non presente
if ! grep -q "welcome.sh" /home/student/.bashrc 2>/dev/null; then
    echo "~/welcome.sh" >> /home/student/.bashrc
fi

echo "=========================================="
echo "  CONTAINER READY - Starting systemd"
echo "=========================================="
echo ""

# Avvia systemd o il comando specificato
exec "$@"