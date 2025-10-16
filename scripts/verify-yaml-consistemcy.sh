#!/bin/bash

# Script per verificare coerenza file YAML

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ISSUES=0

echo ""
echo -e "${BLUE}=========================================="
echo "  YAML CONSISTENCY VERIFICATION"
echo -e "==========================================${NC}"
echo ""

# Funzione per check
check() {
    local description=$1
    local test_command=$2
    
    echo -n "Checking: $description... "
    if eval "$test_command" &> /dev/null; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}✗${NC}"
        ISSUES=$((ISSUES + 1))
        return 1
    fi
}

# 1. Verifica file esistono
echo -e "${BLUE}=== File Existence ===${NC}"
check "01-namespaces.yaml" "test -f kubernetes/01-namespaces.yaml"
check "02-ssh-config.yaml" "test -f kubernetes/02-ssh-config.yaml"
check "03-ssh-keygen-job.yaml" "test -f kubernetes/03-ssh-keygen-job.yaml"
check "04-student-lab-secure.yaml" "test -f kubernetes/04-student-lab-secure.yaml"
check "05-network-policies.yaml" "test -f kubernetes/05-network-policies.yaml"
check "06-resource-limits.yaml" "test -f kubernetes/06-resource-limits.yaml"
check "07-traefik-middleware.yaml" "test -f kubernetes/07-traefik-middleware.yaml"
check "08-traefik-tls.yaml" "test -f kubernetes/08-traefik-tls.yaml"
check "09-prometheus-monitoring.yaml" "test -f kubernetes/09-prometheus-monitoring.yaml"
check "10-traefik-monitoring.yaml" "test -f kubernetes/10-traefik-monitoring.yaml"
check "11-grafana-dashboard.yaml" "test -f kubernetes/11-grafana-dashboard.yaml"

echo ""
echo -e "${BLUE}=== YAML Syntax ===${NC}"

# 2. Verifica sintassi YAML
for file in kubernetes/*.yaml; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        echo -n "Validating $filename... "
        if kubectl apply --dry-run=client -f "$file" &> /dev/null; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${RED}✗ Invalid YAML${NC}"
            ISSUES=$((ISSUES + 1))
        fi
    fi
done

echo ""
echo -e "${BLUE}=== Label Consistency ===${NC}"

# 3. Verifica label monitor: student-lab
echo -n "Checking 'monitor: student-lab' labels... "
MONITOR_LABELS=$(grep -r "monitor: student-lab" kubernetes/04-student-lab-secure.yaml | wc -l)
if [ "$MONITOR_LABELS" -ge 6 ]; then
    echo -e "${GREEN}✓ Found ${MONITOR_LABELS} instances${NC}"
else
    echo -e "${RED}✗ Only ${MONITOR_LABELS} instances (expected 6+)${NC}"
    ISSUES=$((ISSUES + 1))
fi

echo ""
echo -e "${BLUE}=== Image References ===${NC}"

# 4. Verifica image references
echo -n "Checking container image references... "
IMAGE_REFS=$(grep -E "image:.*linux-lab" kubernetes/04-student-lab-secure.yaml | wc -l)
if [ "$IMAGE_REFS" -eq 3 ]; then
    echo -e "${GREEN}✓ Found 3 image references${NC}"
else
    echo -e "${RED}✗ Found ${IMAGE_REFS} image references (expected 3)${NC}"
    ISSUES=$((ISSUES + 1))
fi

echo ""
echo -e "${BLUE}=== Capabilities ===${NC}"

# 5. Verifica NO SYS_ADMIN
echo -n "Checking for SYS_ADMIN capability... "
if grep -q "SYS_ADMIN" kubernetes/04-student-lab-secure.yaml; then
    echo -e "${RED}✗ SYS_ADMIN found (security risk!)${NC}"
    ISSUES=$((ISSUES + 1))
else
    echo -e "${GREEN}✓ No SYS_ADMIN${NC}"
fi

echo ""
echo -e "${BLUE}=== Network Policies ===${NC}"

# 6. Verifica NetworkPolicy count
echo -n "Checking NetworkPolicy count... "
NP_COUNT=$(grep -c "kind: NetworkPolicy" kubernetes/05-network-policies.yaml)
if [ "$NP_COUNT" -ge 6 ]; then
    echo -e "${GREEN}✓ Found ${NP_COUNT} policies${NC}"
else
    echo -e "${YELLOW}⚠ Only ${NP_COUNT} policies${NC}"
fi

echo ""
echo -e "${BLUE}=== Resource Quotas ===${NC}"

# 7. Verifica Resource Quota values
echo -n "Checking CPU limits... "
CPU_LIMIT=$(grep "limits.cpu:" kubernetes/06-resource-limits.yaml | grep -oP '\d+' | head -1)
if [ "$CPU_LIMIT" -ge 4000 ]; then
    echo -e "${GREEN}✓ ${CPU_LIMIT}m (adequate)${NC}"
else
    echo -e "${YELLOW}⚠ ${CPU_LIMIT}m (may be low)${NC}"
fi

echo -n "Checking Memory limits... "
MEM_LIMIT=$(grep "limits.memory:" kubernetes/06-resource-limits.yaml | grep -oP '\d+' | head -1)
if [ "$MEM_LIMIT" -ge 5 ]; then
    echo -e "${GREEN}✓ ${MEM_LIMIT}Gi (adequate)${NC}"
else
    echo -e "${YELLOW}⚠ ${MEM_LIMIT}Gi (may be low)${NC}"
fi

echo ""
echo -e "${BLUE}=== Traefik Configuration ===${NC}"

# 8. Verifica Traefik Middleware chain
echo -n "Checking middleware chain... "
if grep -q "student-lab-chain" kubernetes/07-traefik-middleware.yaml; then
    echo -e "${GREEN}✓ Found middleware chain${NC}"
else
    echo -e "${RED}✗ Middleware chain missing${NC}"
    ISSUES=$((ISSUES + 1))
fi

# 9. Verifica TLS configuration
echo -n "Checking TLS wildcard cert... "
if grep -q "lab-wildcard-tls" kubernetes/08-traefik-tls.yaml; then
    echo -e "${GREEN}✓ Wildcard cert configured${NC}"
else
    echo -e "${RED}✗ Wildcard cert missing${NC}"
    ISSUES=$((ISSUES + 1))
fi

echo ""
echo -e "${BLUE}=== Monitoring ===${NC}"

# 10. Verifica Prometheus rules
echo -n "Checking Prometheus alert rules... "
ALERT_COUNT=$(grep -c "alert:" kubernetes/09-prometheus-monitoring.yaml 2>/dev/null || echo 0)
if [ "$ALERT_COUNT" -ge 5 ]; then
    echo -e "${GREEN}✓ Found ${ALERT_COUNT} alerts${NC}"
else
    echo -e "${YELLOW}⚠ Only ${ALERT_COUNT} alerts${NC}"
fi

echo ""
echo -e "${BLUE}=== File References ===${NC}"

# 11. Verifica no references a file eliminati
echo -n "Checking for NGINX references... "
if grep -r "nginx" kubernetes/*.yaml &> /dev/null; then
    echo -e "${RED}✗ Found NGINX references (should be Traefik only)${NC}"
    ISSUES=$((ISSUES + 1))
else
    echo -e "${GREEN}✓ No NGINX references${NC}"
fi

echo -n "Checking for deprecated files... "
DEPRECATED_FILES=(
    "kubernetes/optional-basic-auth.yaml"
    "kubernetes/optional-nginx-security.yaml"
    "kubernetes/07-security-hardening.yaml"
)
FOUND_DEPRECATED=0
for file in "${DEPRECATED_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${RED}✗ Found deprecated: $(basename $file)${NC}"
        FOUND_DEPRECATED=1
        ISSUES=$((ISSUES + 1))
    fi
done
if [ $FOUND_DEPRECATED -eq 0 ]; then
    echo -e "${GREEN}✓ No deprecated files${NC}"
fi

# Summary
echo ""
echo -e "${BLUE}=========================================="
echo "  VERIFICATION SUMMARY"
echo -e "==========================================${NC}"
echo ""

if [ $ISSUES -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo ""
    echo "Your YAML files are consistent and ready for deployment."
    exit 0
else
    echo -e "${RED}✗ Found ${ISSUES} issue(s)${NC}"
    echo ""
    echo "Please review and fix the issues above before deploying."
    exit 1
fi