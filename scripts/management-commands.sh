#!/bin/bash

# Comandi utili per gestire il laboratorio
# Versione corretta e completa

NUM_STUDENTS="${NUM_STUDENTS:-6}"

# ========================================
# COLORI
# ========================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# ========================================
# MONITORAGGIO
# ========================================

view_all_pods() {
    echo -e "${BLUE}=== ALL STUDENT PODS ===${NC}"
    for i in $(seq 1 $NUM_STUDENTS); do
        echo ""
        echo -e "${GREEN}Student ${i}:${NC}"
        kubectl get pods -n student${i} -o wide
    done
}

view_resources() {
    echo -e "${BLUE}=== RESOURCE USAGE ===${NC}"
    for i in $(seq 1 $NUM_STUDENTS); do
        echo ""
        echo -e "${GREEN}Student ${i}:${NC}"
        kubectl top pods -n student${i} 2>/dev/null || echo "  metrics-server not available"
    done
}

view_student_status() {
    local student_id=$1
    if [ -z "$student_id" ]; then
        echo "Usage: view_student_status <student_number>"
        return 1
    fi
    
    echo -e "${BLUE}=== STUDENT ${student_id} STATUS ===${NC}"
    echo ""
    echo "Pods:"
    kubectl get pods -n student${student_id}
    echo ""
    echo "Services:"
    kubectl get svc -n student${student_id}
    echo ""
    echo "IngressRoutes:"
    kubectl get ingressroute -n student${student_id} 2>/dev/null || echo "  No IngressRoutes found"
    echo ""
    echo "Resource Quota:"
    kubectl describe resourcequota -n student${student_id}
}

# ========================================
# RESET E PULIZIA
# ========================================

reset_student() {
    local student_id=$1
    if [ -z "$student_id" ]; then
        echo "Usage: reset_student <student_number>"
        return 1
    fi
    
    echo -e "${YELLOW}Resetting student${student_id} lab...${NC}"
    
    # Rollout restart tutti i deployment
    kubectl rollout restart deployment -n student${student_id}
    
    echo -e "${GREEN}✓ Student${student_id} lab restarted${NC}"
    echo ""
    echo "Monitor restart progress:"
    echo "  kubectl rollout status deployment/client -n student${student_id}"
}

reset_all_students() {
    read -p "Reset ALL student labs? This will restart all pods! (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        for i in $(seq 1 $NUM_STUDENTS); do
            echo "Restarting student${i}..."
            kubectl rollout restart deployment -n student${i}
        done
        echo -e "${GREEN}✓ All labs restarted${NC}"
    fi
}

# ========================================
# DEBUGGING
# ========================================

get_logs() {
    local student_id=$1
    local pod_type=$2
    local container=${3:-linux}
    
    if [ -z "$student_id" ] || [ -z "$pod_type" ]; then
        echo "Usage: get_logs <student_number> <pod_type> [container]"
        echo "Example: get_logs 1 client"
        echo "Example: get_logs 1 client code-server"
        return 1
    fi
    
    local pod_name=$(kubectl get pods -n student${student_id} -l app=${pod_type} -o jsonpath='{.items[0].metadata.name}')
    
    if [ -z "$pod_name" ]; then
        echo "No pod found for app=${pod_type} in student${student_id}"
        return 1
    fi
    
    echo -e "${BLUE}Logs for ${pod_type}/${container} in student${student_id}:${NC}"
    kubectl logs -n student${student_id} ${pod_name} -c ${container} --tail=100
}

exec_shell() {
    local student_id=$1
    local pod_type=$2
    
    if [ -z "$student_id" ] || [ -z "$pod_type" ]; then
        echo "Usage: exec_shell <student_number> <pod_type>"
        echo "Example: exec_shell 1 client"
        echo "Example: exec_shell 1 server1"
        return 1
    fi
    
    local pod_name=$(kubectl get pods -n student${student_id} -l app=${pod_type} -o jsonpath='{.items[0].metadata.name}')
    
    if [ -z "$pod_name" ]; then
        echo "No pod found"
        return 1
    fi
    
    echo -e "${GREEN}Opening shell in ${pod_type}/linux (student${student_id})...${NC}"
    kubectl exec -it -n student${student_id} ${pod_name} -c linux -- /bin/bash
}

exec_code_server() {
    local student_id=$1
    
    if [ -z "$student_id" ]; then
        echo "Usage: exec_code_server <student_number>"
        echo "Example: exec_code_server 1"
        return 1
    fi
    
    local pod_name=$(kubectl get pods -n student${student_id} -l app=client -o jsonpath='{.items[0].metadata.name}')
    
    if [ -z "$pod_name" ]; then
        echo "No client pod found for student${student_id}"
        return 1
    fi
    
    echo -e "${GREEN}Opening shell in code-server container (student${student_id})...${NC}"
    echo "Note: This is the Code-Server container, not the Linux container"
    echo ""
    kubectl exec -it -n student${student_id} ${pod_name} -c code-server -- /bin/sh
}

test_ssh_connectivity() {
    local student_id=$1
    
    if [ -z "$student_id" ]; then
        echo "Usage: test_ssh_connectivity <student_number>"
        return 1
    fi
    
    echo -e "${BLUE}Testing SSH connectivity for student${student_id}...${NC}"
    echo ""
    
    local client_pod=$(kubectl get pods -n student${student_id} -l app=client -o jsonpath='{.items[0].metadata.name}')
    
    if [ -z "$client_pod" ]; then
        echo "Client pod not found"
        return 1
    fi
    
    echo -n "Client → Server1: "
    if kubectl exec -n student${student_id} ${client_pod} -c linux -- \
        ssh -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=5 \
            -o LogLevel=ERROR \
            student@server1 "echo 'OK'" 2>/dev/null | grep -q "OK"; then
        echo -e "${GREEN}✓ Connected${NC}"
    else
        echo -e "${RED}✗ Failed${NC}"
    fi
    
    echo -n "Client → Server2: "
    if kubectl exec -n student${student_id} ${client_pod} -c linux -- \
        ssh -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=5 \
            -o LogLevel=ERROR \
            student@server2 "echo 'OK'" 2>/dev/null | grep -q "OK"; then
        echo -e "${GREEN}✓ Connected${NC}"
    else
        echo -e "${RED}✗ Failed${NC}"
    fi
}

debug_pod() {
    local student_id=$1
    local pod_type=$2
    
    if [ -z "$student_id" ] || [ -z "$pod_type" ]; then
        echo "Usage: debug_pod <student_number> <pod_type>"
        return 1
    fi
    
    local pod_name=$(kubectl get pods -n student${student_id} -l app=${pod_type} -o jsonpath='{.items[0].metadata.name}')
    
    if [ -z "$pod_name" ]; then
        echo "No pod found for app=${pod_type}"
        return 1
    fi
    
    echo -e "${BLUE}=== DEBUG INFO FOR ${pod_type} (student${student_id}) ===${NC}"
    echo ""
    
    echo "Pod Status:"
    kubectl get pod ${pod_name} -n student${student_id}
    echo ""
    
    echo "Pod Description:"
    kubectl describe pod ${pod_name} -n student${student_id}
    echo ""
    
    echo "Recent Events:"
    kubectl get events -n student${student_id} --sort-by='.lastTimestamp' | grep ${pod_name} | tail -10
    echo ""
    
    echo "Container logs (last 50 lines):"
    echo "--- Linux container ---"
    kubectl logs -n student${student_id} ${pod_name} -c linux --tail=50 2>/dev/null || echo "No logs"
    
    if [ "$pod_type" == "client" ]; then
        echo ""
        echo "--- Code-Server container ---"
        kubectl logs -n student${student_id} ${pod_name} -c code-server --tail=50 2>/dev/null || echo "No logs"
    fi
}

# ========================================
# ESERCITAZIONI
# ========================================

deploy_exercise_files() {
    local exercise_name=$1
    
    if [ -z "$exercise_name" ]; then
        echo "Usage: deploy_exercise_files <exercise_name>"
        return 1
    fi
    
    echo -e "${BLUE}Deploying exercise: ${exercise_name}${NC}"
    echo ""
    
    for student in $(seq 1 $NUM_STUDENTS); do
        echo -e "${CYAN}Student ${student}:${NC}"
        
        for server in client server1 server2; do
            local pod=$(kubectl get pods -n student${student} -l app=${server} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
            
            if [ -n "$pod" ]; then
                if kubectl exec -n student${student} ${pod} -c linux -- \
                    bash -c "mkdir -p /home/student/exercises && echo 'Esercitazione: ${exercise_name}' > /home/student/exercises/${exercise_name}.txt && chown student:student /home/student/exercises/${exercise_name}.txt" 2>/dev/null; then
                    echo "  ✓ ${server}"
                else
                    echo "  ✗ ${server} (failed)"
                fi
            fi
        done
    done
    
    echo ""
    echo -e "${GREEN}Exercise files deployed${NC}"
}

run_command_all_students() {
    local command=$1
    
    if [ -z "$command" ]; then
        echo "Usage: run_command_all_students '<command>'"
        echo "Example: run_command_all_students 'df -h'"
        return 1
    fi
    
    echo -e "${BLUE}Running command on all student clients: ${command}${NC}"
    echo ""
    
    for i in $(seq 1 $NUM_STUDENTS); do
        local pod=$(kubectl get pods -n student${i} -l app=client -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        
        if [ -n "$pod" ]; then
            echo -e "${GREEN}Student ${i}:${NC}"
            kubectl exec -n student${i} ${pod} -c linux -- su - student -c "$command" 2>/dev/null || echo "  Failed"
            echo ""
        fi
    done
}

# ========================================
# STATISTICHE
# ========================================

stats() {
    echo -e "${BLUE}=========================================="
    echo "  LAB STATISTICS"
    echo -e "==========================================${NC}"
    echo ""
    
    local total_pods=0
    local running_pods=0
    
    for i in $(seq 1 $NUM_STUDENTS); do
        local student_pods=$(kubectl get pods -n student${i} --no-headers 2>/dev/null | wc -l)
        local student_running=$(kubectl get pods -n student${i} --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
        
        total_pods=$((total_pods + student_pods))
        running_pods=$((running_pods + student_running))
        
        echo "Student ${i}: ${student_running}/${student_pods} pods running"
    done
    
    echo ""
    echo "Total: ${running_pods}/${total_pods} pods running"
    echo ""
    
    echo "Cluster Resources:"
    kubectl top nodes 2>/dev/null || echo "  metrics-server not available"
}

health_check() {
    echo -e "${BLUE}=== LAB HEALTH CHECK ===${NC}"
    echo ""
    
    local issues=0
    
    for i in $(seq 1 $NUM_STUDENTS); do
        echo -e "${CYAN}Checking student${i}...${NC}"
        
        # Check namespace exists
        if ! kubectl get namespace student${i} &>/dev/null; then
            echo -e "  ${RED}✗ Namespace not found${NC}"
            issues=$((issues + 1))
            continue
        fi
        
        # Check pods
        local client=$(kubectl get pods -n student${i} -l app=client --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
        local server1=$(kubectl get pods -n student${i} -l app=server1 --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
        local server2=$(kubectl get pods -n student${i} -l app=server2 --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
        
        if [ "$client" -eq 0 ]; then
            echo -e "  ${RED}✗ Client pod not running${NC}"
            issues=$((issues + 1))
        else
            echo -e "  ${GREEN}✓ Client pod running${NC}"
        fi
        
        if [ "$server1" -eq 0 ]; then
            echo -e "  ${RED}✗ Server1 pod not running${NC}"
            issues=$((issues + 1))
        else
            echo -e "  ${GREEN}✓ Server1 pod running${NC}"
        fi
        
        if [ "$server2" -eq 0 ]; then
            echo -e "  ${RED}✗ Server2 pod not running${NC}"
            issues=$((issues + 1))
        else
            echo -e "  ${GREEN}✓ Server2 pod running${NC}"
        fi
        
        # Check SSH keys secret
        if ! kubectl get secret ssh-keys -n student${i} &>/dev/null; then
            echo -e "  ${RED}✗ SSH keys secret not found${NC}"
            issues=$((issues + 1))
        else
            echo -e "  ${GREEN}✓ SSH keys configured${NC}"
        fi
        
        echo ""
    done
    
    if [ $issues -eq 0 ]; then
        echo -e "${GREEN}✓ All checks passed!${NC}"
    else
        echo -e "${RED}✗ Found ${issues} issue(s)${NC}"
    fi
}

# ========================================
# BACKUP E RESTORE
# ========================================

backup_lab() {
    local backup_name=$1
    
    if [ -z "$backup_name" ]; then
        backup_name="backup-$(date +%Y%m%d-%H%M%S)"
    fi
    
    mkdir -p backups/${backup_name}
    
    echo -e "${BLUE}Creating backup: ${backup_name}${NC}"
    echo ""
    
    for i in $(seq 1 $NUM_STUDENTS); do
        echo "  Backing up student${i}..."
        kubectl get all,configmaps,secrets,ingressroute -n student${i} -o yaml > backups/${backup_name}/student${i}.yaml 2>/dev/null
    done
    
    echo ""
    echo -e "${GREEN}✓ Backup saved in: backups/${backup_name}/${NC}"
}

# ========================================
# UTILITA'
# ========================================

get_student_url() {
    local student_id=$1
    
    if [ -z "$student_id" ]; then
        echo "Usage: get_student_url <student_number>"
        return 1
    fi
    
    local domain=$(kubectl get ingressroute -n student${student_id} -o jsonpath='{.items[0].spec.routes[0].match}' 2>/dev/null | grep -oP 'Host\(\K[^)]+' | tr -d '`')
    
    if [ -n "$domain" ]; then
        echo "https://${domain}"
    else
        echo "Could not find URL for student${student_id}"
    fi
}

list_all_urls() {
    echo -e "${BLUE}=== STUDENT ACCESS URLS ===${NC}"
    echo ""
    
    for i in $(seq 1 $NUM_STUDENTS); do
        local url=$(get_student_url $i)
        echo "Student ${i}: ${url}"
    done
}

# ========================================
# HELP
# ========================================

show_help() {
    cat << EOF
${BLUE}========================================
  LAB MANAGEMENT COMMANDS
========================================${NC}

${GREEN}MONITORING:${NC}
  view_all_pods              - Show all student pods
  view_resources             - Show resource usage (requires metrics-server)
  view_student_status <n>    - Detailed status for student N
  stats                      - Lab statistics
  health_check               - Check lab health
  list_all_urls              - List all student access URLs
  get_student_url <n>        - Get URL for specific student

${GREEN}MANAGEMENT:${NC}
  reset_student <n>          - Restart single student lab
  reset_all_students         - Restart all student pods
  
${GREEN}DEBUGGING:${NC}
  get_logs <n> <type> [container]     - View logs
      Example: get_logs 1 client
      Example: get_logs 1 client code-server
  exec_shell <n> <type>               - Open shell in Linux container
      Example: exec_shell 1 client
      Example: exec_shell 1 server1
  exec_code_server <n>                - Open shell in Code-Server container
      Example: exec_code_server 1
  test_ssh_connectivity <n>           - Test SSH between pods
  debug_pod <n> <type>                - Full debug info for pod

${GREEN}EXERCISES:${NC}
  deploy_exercise_files <name>        - Deploy exercise files to all students
  run_command_all_students '<cmd>'    - Run command on all client pods

${GREEN}BACKUP:${NC}
  backup_lab [name]          - Backup current configuration

${GREEN}Examples:${NC}
  ${CYAN}# Check student 1 status${NC}
  view_student_status 1
  
  ${CYAN}# Open shell in client Linux container${NC}
  exec_shell 1 client
  
  ${CYAN}# Open shell in Code-Server container${NC}
  exec_code_server 1
  
  ${CYAN}# View logs from code-server${NC}
  get_logs 1 client code-server
  
  ${CYAN}# Test SSH connectivity${NC}
  test_ssh_connectivity 1
  
  ${CYAN}# Deploy exercise files${NC}
  deploy_exercise_files "esercizio1"
  
  ${CYAN}# Run command on all students${NC}
  run_command_all_students 'uptime'
  
  ${CYAN}# Backup lab${NC}
  backup_lab my-backup

EOF
}

# ========================================
# MAIN
# ========================================

# Se chiamato con argomenti, esegui il comando
if [ $# -gt 0 ]; then
    "$@"
else
    show_help
fi