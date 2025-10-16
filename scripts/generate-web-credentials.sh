#!/bin/bash

# Script per generare credenziali sicure per accesso web

set -e

NUM_STUDENTS="${NUM_STUDENTS:-6}"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo "  GENERATING WEB CREDENTIALS"
echo -e "==========================================${NC}"
echo ""

# Check htpasswd
if ! command -v htpasswd &> /dev/null; then
    echo "Installing apache2-utils for htpasswd..."
    sudo apt-get update && sudo apt-get install -y apache2-utils
fi

mkdir -p credentials/

# Genera password casuali e crea file htpasswd
for i in $(seq 1 $NUM_STUDENTS); do
    USERNAME="student${i}"
    # Genera password casuale (16 caratteri)
    PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)
    
    echo -e "${GREEN}Student ${i}:${NC}"
    echo "  Username: $USERNAME"
    echo "  Password: $PASSWORD"
    
    # Salva in file
    echo "Username: $USERNAME" > credentials/student${i}.txt
    echo "Password: $PASSWORD" >> credentials/student${i}.txt
    echo "URL: https://student${i}.lab.example.com" >> credentials/student${i}.txt
    
    # Genera hash htpasswd
    HASH=$(htpasswd -nb "$USERNAME" "$PASSWORD")
    
    # Crea secret Kubernetes
    cat > credentials/student${i}-auth-secret.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: basic-auth
  namespace: student${i}
type: Opaque
data:
  auth: $(echo -n "$HASH" | base64 -w0)
EOF
    
    # Applica secret
    kubectl apply -f credentials/student${i}-auth-secret.yaml
    
    echo ""
done

# Crea file riepilogo
cat > credentials/ALL_CREDENTIALS.txt << EOF
========================================
  STUDENT LAB - WEB CREDENTIALS
========================================

IMPORTANT: Keep these credentials secure!
Distribute to students via secure channel.

EOF

for i in $(seq 1 $NUM_STUDENTS); do
    cat credentials/student${i}.txt >> credentials/ALL_CREDENTIALS.txt
    echo "" >> credentials/ALL_CREDENTIALS.txt
done

echo -e "${GREEN}✓ Credentials generated and saved in: credentials/${NC}"
echo ""
echo "Files created:"
echo "  - credentials/student1.txt to student${NUM_STUDENTS}.txt (individual)"
echo "  - credentials/ALL_CREDENTIALS.txt (all credentials)"
echo "  - credentials/student*-auth-secret.yaml (K8s secrets)"
echo ""
echo "Next steps:"
echo "  1. Verify secrets: kubectl get secrets -n student1"
echo "  2. Apply ingress with auth: kubectl apply -f kubernetes/12-basic-auth.yaml"
echo "  3. Distribute credentials securely to students"
echo ""