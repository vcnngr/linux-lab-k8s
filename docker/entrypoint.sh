#!/bin/bash
set -e

echo "=========================================="
echo "  LINUX LAB CONTAINER STARTING"
echo "=========================================="

# ==========================================
# CREA UTENTE STUDENT SE NON ESISTE
# ==========================================
if ! id -u student &> /dev/null; then
    useradd -m -s /bin/bash student
    echo "✓ User 'student' created"
fi

# ==========================================
# DYNAMIC PASSWORD SETUP
# ==========================================
if [ -n "$STUDENT_PASSWORD" ]; then
    echo "student:${STUDENT_PASSWORD}" | chpasswd
    echo "✓ Student password set dynamically"
else
    echo "⚠ WARNING: No STUDENT_PASSWORD set!"
fi

# ==========================================
# CREA DIRECTORY .ssh CON PERMESSI CORRETTI
# ==========================================
SSH_DIR="/home/student/.ssh"
mkdir -p ${SSH_DIR}
chmod 700 ${SSH_DIR}
chown student:student ${SSH_DIR}
echo "✓ SSH directory prepared"

# ==========================================
# SETUP SSH KEYS
# ==========================================
if [ -d "/tmp/ssh-keys" ]; then
    echo "[1/4] Setting up SSH keys..."
    /usr/local/bin/setup-ssh-keys.sh
else
    echo "[1/4] No SSH keys found, skipping..."
fi

# ==========================================
# GENERA HOST KEYS SSH
# ==========================================
echo "[2/4] Generating SSH host keys..."
ssh-keygen -A 2>/dev/null || true

# ==========================================
# CONFIGURA SUDOERS
# ==========================================
if [ -x /usr/local/bin/sudoers-config.sh ]; then
    echo "[3/4] Configuring sudo permissions..."
    /usr/local/bin/sudoers-config.sh
fi

# ==========================================
# WELCOME MESSAGE
# ==========================================
echo "[4/4] Creating welcome message..."
cat > /home/student/welcome.sh << 'EOF'
#!/bin/bash
clear
cat /etc/motd 2>/dev/null || echo "Welcome to Linux Lab"
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
    chown student:student /home/student/.bashrc
fi

echo "=========================================="
echo "  CONTAINER READY - Starting systemd"
echo "=========================================="
echo ""

# Avvia systemd
exec "$@"
