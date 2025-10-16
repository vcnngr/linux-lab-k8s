#!/bin/bash

# Script per eliminare completamente il lab
# Versione MIGLIORATA con gestione PVC

set -e

NUM_STUDENTS="${NUM_STUDENTS:-6}"

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${RED}=========================================="
echo "  WARNING: LAB CLEANUP"
echo -e "==========================================${NC}"
echo ""
echo "This will DELETE:"
echo "  - All student namespaces (student1 to student${NUM_STUDENTS})"
echo "  - All pods, services, deployments"
echo "  - All SSH keys"
echo "  - All ingress rules"
echo "  - All PersistentVolumeClaims (WORKSPACE DATA WILL BE LOST!)"
echo ""
echo -e "${YELLOW}This action CANNOT be undone!${NC}"
echo ""

read -p "Are you ABSOLUTELY sure? Type 'DELETE' to confirm: " confirm

if [ "$confirm" != "DELETE" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "Starting cleanup..."
echo ""

# ========================================
# Opzione 1: Backup dei PVC prima di eliminare
# ========================================

echo -e "${BLUE}Do you want to backup PVC data before deletion?${NC}"
read -p "Backup PVCs? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${YELLOW}Backing up PVC data...${NC}"
    
    BACKUP_DIR="./pvc-backups-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    for i in $(seq 1 $NUM_STUDENTS); do
        echo -e "${BLUE}[${i}/${NUM_STUDENTS}]${NC} Backing up student${i} workspace..."
        
        # Ottieni il nome del pod client
        CLIENT_POD=$(kubectl get pods -n student${i} -l app=client -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        
        if [ -n "$CLIENT_POD" ]; then
            # Crea tar.gz della workspace e scaricalo
            kubectl exec -n student${i} ${CLIENT_POD} -c linux -- \
                tar czf /tmp/workspace-backup.tar.gz -C /home/student workspace 2>/dev/null || true
            
            kubectl cp student${i}/${CLIENT_POD}:/tmp/workspace-backup.tar.gz \
                ${BACKUP_DIR}/student${i}-workspace.tar.gz -c linux 2>/dev/null || true
            
            echo -e "  ${GREEN}✓${NC} Backed up to ${BACKUP_DIR}/student${i}-workspace.tar.gz"
        else
            echo -e "  ${YELLOW}⚠${NC} Pod not found, skipping"
        fi
    done
    
    echo ""
    echo -e "${GREEN}✓ Backup completed in: ${BACKUP_DIR}/${NC}"
    echo ""
fi

# ========================================
# Eliminazione namespace (include PVC automaticamente)
# ========================================

echo -e "${YELLOW}Deleting namespaces (this will also delete PVCs)...${NC}"
echo ""

for i in $(seq 1 $NUM_STUDENTS); do
    echo -e "${BLUE}[${i}/${NUM_STUDENTS}]${NC} Deleting namespace student${i}..."
    kubectl delete namespace student${i} --ignore-not-found=true &
done

# Wait for all background deletions
echo ""
echo "Waiting for namespace deletion to complete..."
echo "(This may take a few minutes as PVCs are being released)"
echo ""
wait

# ========================================
# Verifica che i PVC siano stati eliminati
# ========================================

echo ""
echo -e "${BLUE}Verifying PVC cleanup...${NC}"

REMAINING_PVC=0
for i in $(seq 1 $NUM_STUDENTS); do
    if kubectl get pvc -n student${i} student-workspace-pvc &> /dev/null; then
        echo -e "${YELLOW}⚠${NC} PVC still exists in student${i}"
        REMAINING_PVC=$((REMAINING_PVC + 1))
    fi
done

if [ $REMAINING_PVC -eq 0 ]; then
    echo -e "${GREEN}✓${NC} All PVCs deleted successfully"
else
    echo -e "${YELLOW}⚠ ${REMAINING_PVC} PVC(s) still exist (may be in Terminating state)${NC}"
    echo ""
    echo "To force delete stuck PVCs, run:"
    echo "  kubectl patch pvc student-workspace-pvc -n studentN -p '{\"metadata\":{\"finalizers\":null}}'"
fi

# ========================================
# Pulizia IngressRoutes (se non eliminate con namespace)
# ========================================

echo ""
echo -e "${BLUE}Cleaning up IngressRoutes...${NC}"

for i in $(seq 1 $NUM_STUDENTS); do
    kubectl delete ingressroute student${i}-http -n student${i} --ignore-not-found=true &> /dev/null || true
    kubectl delete ingressroute student${i}-https -n student${i} --ignore-not-found=true &> /dev/null || true
done

echo -e "${GREEN}✓${NC} IngressRoutes cleanup completed"

# ========================================
# Opzione: Mantieni o elimina credenziali
# ========================================

echo ""
echo -e "${BLUE}Do you want to delete saved credentials?${NC}"
read -p "Delete credentials directory? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [ -d "./credentials" ]; then
        rm -rf ./credentials
        echo -e "${GREEN}✓${NC} Credentials directory deleted"
    fi
else
    echo -e "${YELLOW}⚠${NC} Credentials kept in ./credentials/"
fi

# ========================================
# Summary
# ========================================

echo ""
echo -e "${GREEN}=========================================="
echo "  ✓ CLEANUP COMPLETED!"
echo -e "==========================================${NC}"
echo ""
echo "Removed:"
echo "  • All student namespaces"
echo "  • All pods, services, deployments"
echo "  • All PersistentVolumeClaims"
echo "  • All SSH keys"
echo "  • All ingress rules"
echo ""

if [ -d "$BACKUP_DIR" ]; then
    echo "Workspace backups saved in:"
    echo "  ${BACKUP_DIR}/"
    echo ""
fi

if [ -d "./credentials" ]; then
    echo "Credentials still available in:"
    echo "  ./credentials/"
    echo ""
fi

echo "To redeploy:"
echo "  ./scripts/deploy-lab.sh"
echo ""