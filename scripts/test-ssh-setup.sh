#!/bin/bash
# Script per testare la configurazione SSH completa

set -e

STUDENT_ID=${1:-1}

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo -e "${BLUE}=========================================="
echo "  TEST SSH SETUP - Student ${STUDENT_ID}"
echo -e "==========================================${NC}"
echo ""

# Funzione per test con output colorato
test_step() {
    local description=$1
    local command=$2
    
    echo -n "Testing: $description... "
    if eval "$command" &> /dev/null; then
        echo -e "${GREEN}✓ OK${NC}"
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}"
        return 1
    fi
}

# Counter per failures
FAILURES=0

# 1. Verifica namespace
if ! test_step "Namespace student${STUDENT_ID}" "kubectl get namespace student${STUDENT_ID}"; then
    echo -e "${RED}CRITICAL: Namespace not found!${NC}"
    exit 1
fi

# 2. Verifica secret SSH keys
if ! test_step "SSH keys secret" "kubectl get secret ssh-keys -n student${STUDENT_ID}"; then
    echo -e "${YELLOW}WARNING: SSH keys secret missing${NC}"
    FAILURES=$((FAILURES + 1))
fi

# 3. Verifica client pod
if ! test_step "Client pod running" "kubectl get pods -n student${STUDENT_ID} -l app=client --field-selector=status.phase=Running"; then
    echo -e "${RED}ERROR: Client pod not running${NC}"
    FAILURES=$((FAILURES + 1))
    exit 1
fi

# 4. Verifica server1 pod
if ! test_step "Server1 pod running" "kubectl get pods -n student${STUDENT_ID} -l app=server1 --field-selector=status.phase=Running"; then
    echo -e "${RED}ERROR: Server1 pod not running${NC}"
    FAILURES=$((FAILURES + 1))
fi

# 5. Verifica server2 pod
if ! test_step "Server2 pod running" "kubectl get pods -n student${STUDENT_ID} -l app=server2 --field-selector=status.phase=Running"; then
    echo -e "${RED}ERROR: Server2 pod not running${NC}"
    FAILURES=$((FAILURES + 1))
fi

# 6. Wait for pods ready
echo ""
echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready --timeout=30s pod -l app=client -n student${STUDENT_ID} 2>/dev/null || true
kubectl wait --for=condition=ready --timeout=30s pod -l app=server1 -n student${STUDENT_ID} 2>/dev/null || true
kubectl wait --for=condition=ready --timeout=30s pod -l app=server2 -n student${STUDENT_ID} 2>/dev/null || true

# Get pod names
CLIENT_POD=$(kubectl get pods -n student${STUDENT_ID} -l app=client -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
SERVER1_POD=$(kubectl get pods -n student${STUDENT_ID} -l app=server1 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
SERVER2_POD=$(kubectl get pods -n student${STUDENT_ID} -l app=server2 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$CLIENT_POD" ]; then
    echo -e "${RED}ERROR: Cannot find client pod${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}=== SSH Connectivity Tests ===${NC}"
echo ""

# 7. Test SSH da client a server1
echo -n "Client → Server1: "
if kubectl exec -n student${STUDENT_ID} ${CLIENT_POD} -c linux -- \
    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        -o LogLevel=ERROR \
        student@server1 "echo 'SSH_OK'" 2>/dev/null | grep -q "SSH_OK"; then
    echo -e "${GREEN}✓ Connection successful${NC}"
else
    echo -e "${RED}✗ Connection failed${NC}"
    FAILURES=$((FAILURES + 1))
fi

# 8. Test SSH da client a server2
echo -n "Client → Server2: "
if kubectl exec -n student${STUDENT_ID} ${CLIENT_POD} -c linux -- \
    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        -o LogLevel=ERROR \
        student@server2 "echo 'SSH_OK'" 2>/dev/null | grep -q "SSH_OK"; then
    echo -e "${GREEN}✓ Connection successful${NC}"
else
    echo -e "${RED}✗ Connection failed${NC}"
    FAILURES=$((FAILURES + 1))
fi

# 9. Test SSH keys presente in client
echo -n "SSH private key in client: "
if kubectl exec -n student${STUDENT_ID} ${CLIENT_POD} -c linux -- \
    test -f /home/student/.ssh/id_rsa 2>/dev/null; then
    echo -e "${GREEN}✓ Present${NC}"
else
    echo -e "${RED}✗ Missing${NC}"
    FAILURES=$((FAILURES + 1))
fi

# 10. Test authorized_keys presente in server1
echo -n "SSH authorized_keys in server1: "
if [ -n "$SERVER1_POD" ]; then
    if kubectl exec -n student${STUDENT_ID} ${SERVER1_POD} -c linux -- \
        test -f /home/student/.ssh/authorized_keys 2>/dev/null; then
        echo -e "${GREEN}✓ Present${NC}"
    else
        echo -e "${RED}✗ Missing${NC}"
        FAILURES=$((FAILURES + 1))
    fi
else
    echo -e "${YELLOW}⚠ Server1 pod not found${NC}"
fi

# 11. Test authorized_keys presente in server2
echo -n "SSH authorized_keys in server2: "
if [ -n "$SERVER2_POD" ]; then
    if kubectl exec -n student${STUDENT_ID} ${SERVER2_POD} -c linux -- \
        test -f /home/student/.ssh/authorized_keys 2>/dev/null; then
        echo -e "${GREEN}✓ Present${NC}"
    else
        echo -e "${RED}✗ Missing${NC}"
        FAILURES=$((FAILURES + 1))
    fi
else
    echo -e "${YELLOW}⚠ Server2 pod not found${NC}"
fi

# 12. Test SSH config file
echo -n "SSH config file in client: "
if kubectl exec -n student${STUDENT_ID} ${CLIENT_POD} -c linux -- \
    test -f /home/student/.ssh/config 2>/dev/null; then
    echo -e "${GREEN}✓ Present${NC}"
else
    echo -e "${YELLOW}⚠ Missing (optional)${NC}"
fi

# Summary
echo ""
echo -e "${BLUE}=========================================="
echo "  TEST SUMMARY"
echo -e "==========================================${NC}"
echo ""

if [ $FAILURES -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    echo ""
    echo "SSH setup is working correctly for student${STUDENT_ID}"
    exit 0
else
    echo -e "${RED}✗ ${FAILURES} test(s) failed${NC}"
    echo ""
    echo "Troubleshooting steps:"
    echo "  1. Check if SSH keys were generated:"
    echo "     kubectl get secret ssh-keys -n student${STUDENT_ID}"
    echo ""
    echo "  2. Verify pod logs:"
    echo "     kubectl logs -n student${STUDENT_ID} ${CLIENT_POD} -c linux"
    echo ""
    echo "  3. Manually test SSH:"
    echo "     kubectl exec -it -n student${STUDENT_ID} ${CLIENT_POD} -c linux -- ssh server1"
    echo ""
    exit 1
fi