#!/bin/bash
# Configurazione sudoers per ambiente didattico

# Leggi modalità da variabile ambiente (default: limited)
SUDO_MODE="${SUDO_MODE:-limited}"

echo "Configuring sudo mode: $SUDO_MODE"

# Rimuovi configurazioni esistenti
rm -f /etc/sudoers.d/student-*

case $SUDO_MODE in
    "strict")
        # Sudo con password per TUTTO
        cat > /etc/sudoers.d/student-strict << 'EOF'
# Student deve usare password per qualsiasi comando sudo
student ALL=(ALL) ALL

# Logging dettagliato
Defaults logfile=/var/log/sudo.log
Defaults log_input, log_output
EOF
        chmod 440 /etc/sudoers.d/student-strict
        echo "✓ Sudo strict: password richiesta per tutti i comandi"
        ;;
        
    "limited")
        # Sudo senza password solo per comandi comuni
        cat > /etc/sudoers.d/student-limited << 'EOF'
# Comandi senza password
student ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /bin/systemctl
student ALL=(ALL) NOPASSWD: /usr/bin/apt, /usr/bin/apt-get
student ALL=(ALL) NOPASSWD: /usr/bin/dnf, /usr/bin/yum
student ALL=(ALL) NOPASSWD: /usr/bin/journalctl, /bin/journalctl
student ALL=(ALL) NOPASSWD: /usr/bin/cat /var/log/*
student ALL=(ALL) NOPASSWD: /usr/bin/less /var/log/*
student ALL=(ALL) NOPASSWD: /usr/bin/tail /var/log/*
student ALL=(ALL) NOPASSWD: /usr/bin/head /var/log/*

# Altri comandi richiedono password
student ALL=(ALL) ALL

# Logging
Defaults logfile=/var/log/sudo.log
EOF
        chmod 440 /etc/sudoers.d/student-limited
        echo "✓ Sudo limited: password richiesta per comandi sensibili"
        ;;
        
    "full")
        # Sudo completo senza password (solo per lab)
        cat > /etc/sudoers.d/student-full << 'EOF'
# ATTENZIONE: Solo per ambiente didattico!
# Accesso sudo completo senza password
student ALL=(ALL) NOPASSWD:ALL

# Logging comunque attivo
Defaults logfile=/var/log/sudo.log
EOF
        chmod 440 /etc/sudoers.d/student-full
        echo "✓ Sudo full: accesso completo senza password"
        ;;
        
    *)
        echo "⚠ Unknown SUDO_MODE: $SUDO_MODE, using default (limited)"
        # Default = limited
        cat > /etc/sudoers.d/student-limited << 'EOF'
student ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/bin/apt, /usr/bin/dnf, /usr/bin/journalctl
student ALL=(ALL) ALL
Defaults logfile=/var/log/sudo.log
EOF
        chmod 440 /etc/sudoers.d/student-limited
        ;;
esac

# Verifica sintassi sudoers
if visudo -c -f /etc/sudoers.d/student-* 2>/dev/null; then
    echo "✓ Sudoers configuration valid"
else
    echo "✗ ERROR: Invalid sudoers configuration!"
    exit 1
fi

# Assicurati che log directory esista
mkdir -p /var/log
touch /var/log/sudo.log
chmod 600 /var/log/sudo.log

echo "Sudo configuration completed successfully"