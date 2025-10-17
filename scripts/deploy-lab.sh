#!/bin/bash

# Script per deployare il lab completo per tutti gli studenti
# Versione MIGLIORATA con PVC e password dinamiche
# AGGIUNTO: Deploy automatico Cockpit IngressRoutes
# MODIFICATO: Usa immagini pre-built, non compila
# FIXED: Scelta interattiva StorageClass

set -e

# ========================================
# CONFIGURAZIONE
# ========================================

REGISTRY="${REGISTRY:-docker.io/vcnngr}"
IMAGE_BASE_NAME="${IMAGE_BASE_NAME:-linux-lab-k8s}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
NUM_STUDENTS="${NUM_STUDENTS:-6}"
BASE_DOMAIN="${BASE_DOMAIN:-lab.example.com}"
SUDO_MODE="${SUDO_MODE:-limited}"  # strict | limited | full
STORAGE_CLASS=""  # Verrà selezionato interattivamente

# Directory per salvare le password generate
CREDENTIALS_DIR="./credentials"

# ========================================
# COLORI OUTPUT
# ========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ========================================
# FUNZIONI UTILITY
# ========================================

print_header() {
    echo ""
    echo -e "${BLUE}=========================================="
    echo -e "  $1"
    echo -e "==========================================${NC}"
    echo ""
}

print_step() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[ℹ]${NC} $1"
}

# ========================================
# SCELTA DISTRIBUZIONE
# ========================================

choose_distro() {
    echo ""
    echo -e "${CYAN}Scegli la distribuzione Linux per i container:${NC}"
    echo ""
    echo "  1) Ubuntu 24.04 LTS (Debian-based)"
    echo "  2) Debian Trixie (testing)"
    echo "  3) Rocky Linux 10 (RHEL-compatible)"
    echo ""
    
    while true; do
        read -p "Scelta [1-3]: " choice
        case $choice in
            1)
                DISTRO="ubuntu"
                DISTRO_DISPLAY="Ubuntu 24.04 LTS"
                break
                ;;
            2)
                DISTRO="debian"
                DISTRO_DISPLAY="Debian Trixie"
                break
                ;;
            3)
                DISTRO="rocky"
                DISTRO_DISPLAY="Rocky Linux 10"
                break
                ;;
            *)
                echo -e "${RED}Scelta non valida. Riprova.${NC}"
                ;;
        esac
    done
    
    # Costruisci nome immagine completo con distro
    FULL_IMAGE="${REGISTRY}/${IMAGE_BASE_NAME}-${DISTRO}:${IMAGE_TAG}"
    
    print_info "Selezionato: ${DISTRO_DISPLAY}"
    print_info "Immagine: ${FULL_IMAGE}"
}

# ========================================
# SCELTA STORAGECLASS
# ========================================

choose_storage_class() {
    echo ""
    echo -e "${CYAN}Seleziona StorageClass per i PVC:${NC}"
    echo ""
    
    # Ottieni lista StorageClass disponibili
    local storage_classes=($(kubectl get storageclass -o jsonpath='{.items[*].metadata.name}' 2>/dev/null))
    local default_sc=$(kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' 2>/dev/null)
    
    if [ ${#storage_classes[@]} -eq 0 ]; then
        print_warning "No StorageClass found in cluster!"
        print_info "You can still specify a custom StorageClass name or continue without one"
        echo ""
        read -p "Enter custom StorageClass name (or leave empty for no storageClassName): " custom_sc
        STORAGE_CLASS="$custom_sc"
        if [ -z "$STORAGE_CLASS" ]; then
            print_info "PVCs will be created without storageClassName"
        else
            print_info "Using custom StorageClass: ${STORAGE_CLASS}"
        fi
        return
    fi
    
    # Mostra dettagli StorageClass in formato tabella
    echo -e "${CYAN}Available StorageClasses:${NC}"
    echo ""
    printf "  %-3s %-30s %-25s %s\n" "ID" "NAME" "PROVISIONER" "DEFAULT"
    printf "  %s\n" "$(printf '%.0s─' {1..80})"
    
    echo -e "  ${YELLOW}0${NC}   Use cluster default (omit storageClassName)"
    
    local i=1
    for sc in "${storage_classes[@]}"; do
        local provisioner=$(kubectl get storageclass "$sc" -o jsonpath='{.provisioner}' 2>/dev/null)
        local is_default=""
        if [ "$sc" == "$default_sc" ]; then
            is_default="${GREEN}✓${NC}"
        else
            is_default=" "
        fi
        printf "  ${YELLOW}%-3s${NC} %-30s %-25s %b\n" "$i" "$sc" "${provisioner:0:25}" "$is_default"
        ((i++))
    done
    
    echo -e "  ${YELLOW}c${NC}   Enter custom StorageClass name"
    echo ""
    
    while true; do
        read -p "Scelta [0-$((${#storage_classes[@]}))/c]: " choice
        
        # Opzione 0: usa default del cluster
        if [ "$choice" == "0" ]; then
            STORAGE_CLASS=""
            if [ -n "$default_sc" ]; then
                print_info "Using cluster default StorageClass: ${default_sc}"
            else
                print_info "No storageClassName specified (cluster will use default)"
            fi
            break
        
        # Opzione 'c': custom name
        elif [ "$choice" == "c" ] || [ "$choice" == "C" ]; then
            echo ""
            read -p "Enter StorageClass name: " custom_sc
            if [ -z "$custom_sc" ]; then
                print_warning "Empty name, using cluster default"
                STORAGE_CLASS=""
            else
                # Verifica se esiste
                if kubectl get storageclass "$custom_sc" &> /dev/null; then
                    STORAGE_CLASS="$custom_sc"
                    print_info "Selected: ${STORAGE_CLASS}"
                else
                    print_warning "StorageClass '${custom_sc}' not found in cluster"
                    read -p "Use it anyway? (y/N) " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        STORAGE_CLASS="$custom_sc"
                        print_info "Using custom StorageClass: ${STORAGE_CLASS} (not verified)"
                    else
                        continue
                    fi
                fi
            fi
            break
        
        # Opzione numerica: scelta dalla lista
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#storage_classes[@]}" ]; then
            STORAGE_CLASS="${storage_classes[$((choice-1))]}"
            print_info "Selected: ${STORAGE_CLASS}"
            break
        
        else
            echo -e "${RED}Scelta non valida. Riprova (0-$((${#storage_classes[@]})) o 'c' per custom).${NC}"
        fi
    done
    
    # Mostra info dettagliate sulla StorageClass scelta
    if [ -n "$STORAGE_CLASS" ]; then
        echo ""
        echo -e "${CYAN}StorageClass Details:${NC}"
        kubectl get storageclass "$STORAGE_CLASS" 2>/dev/null || echo "  (Custom name - not verified)"
    fi
}

# ========================================
# CHECK PREREQUISITI
# ========================================

check_requirements() {
    print_header "CHECKING REQUIREMENTS"
    
    local missing=0
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found"
        missing=1
    else
        local kubectl_version=$(kubectl version --client --short 2>/dev/null || kubectl version --client 2>&1 | head -1)
        print_step "kubectl found: ${kubectl_version}"
    fi
    
    # Check docker (per pull immagini)
    if ! command -v docker &> /dev/null; then
        print_error "docker not found"
        missing=1
    else
        print_step "docker found: $(docker --version)"
    fi
    
    # Check openssl (per generazione password)
    if ! command -v openssl &> /dev/null; then
        print_error "openssl not found (needed for password generation)"
        missing=1
    else
        print_step "openssl found"
    fi
    
    # Check cluster connection
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        missing=1
    else
        print_step "Connected to Kubernetes cluster"
    fi
    
    # Check Traefik
    if ! kubectl get crd ingressroutes.traefik.containo.us &> /dev/null; then
        print_warning "Traefik CRDs not found - will try to continue but Ingress may fail"
    else
        print_step "Traefik CRDs found"
    fi
    
    if [ $missing -eq 1 ]; then
        print_error "Missing requirements. Please install missing tools."
        exit 1
    fi
}

# ========================================
# PULL IMMAGINE
# ========================================

pull_image() {
    print_header "PULLING DOCKER IMAGE"
    
    print_info "Pulling ${DISTRO_DISPLAY} image from registry..."
    print_info "Image: ${FULL_IMAGE}"
    echo ""
    
    if docker pull "${FULL_IMAGE}"; then
        print_step "Image pulled successfully"
    else
        print_error "Failed to pull image: ${FULL_IMAGE}"
        echo ""
        print_info "Available options:"
        echo "  1. Check if image exists: docker search ${REGISTRY}/${IMAGE_BASE_NAME}"
        echo "  2. Build image yourself: ./scripts/build-images.sh ${DISTRO}"
        echo "  3. Use different registry: export REGISTRY=your-registry.io"
        exit 1
    fi
}

# ========================================
# NAMESPACES
# ========================================

create_namespaces() {
    print_header "CREATING NAMESPACES"
    
    if kubectl apply -f kubernetes/01-namespaces.yaml; then
        print_step "Namespaces created"
    else
        print_error "Failed to create namespaces"
        exit 1
    fi
    
    # Wait for namespaces to be ready
    sleep 2
}

# ========================================
# PERSISTENT VOLUMES
# ========================================

deploy_persistent_volumes() {
    print_header "CREATING PERSISTENT VOLUMES"
    
    if [ -n "$STORAGE_CLASS" ]; then
        print_info "Using StorageClass: ${STORAGE_CLASS}"
    else
        print_info "Using cluster default StorageClass"
    fi
    echo ""
    
    for i in $(seq 1 $NUM_STUDENTS); do
        echo -e "${BLUE}[${i}/${NUM_STUDENTS}]${NC} Creating PVC for student${i}..."
        
        # Costruisci YAML PVC dinamicamente
        if [ -n "$STORAGE_CLASS" ]; then
            # Con StorageClass specificata
            cat kubernetes/04a-student-pvc.yaml | \
                sed "s/namespace: student1/namespace: student${i}/g" | \
                sed "s/student-id: \"1\"/student-id: \"${i}\"/g" | \
                sed "s|# storageClassName viene omesso.*|storageClassName: \"${STORAGE_CLASS}\"|g" | \
                kubectl apply -f - > /dev/null
        else
            # Senza StorageClass (usa default)
            cat kubernetes/04a-student-pvc.yaml | \
                sed "s/namespace: student1/namespace: student${i}/g" | \
                sed "s/student-id: \"1\"/student-id: \"${i}\"/g" | \
                kubectl apply -f - > /dev/null
        fi
    done
    
    print_step "PersistentVolumeClaims created"
    
    # Verifica che almeno un PVC sia stato creato
    sleep 2
    if kubectl get pvc -n student1 student-workspace-pvc &> /dev/null; then
        local pvc_status=$(kubectl get pvc -n student1 student-workspace-pvc -o jsonpath='{.status.phase}')
        if [ "$pvc_status" == "Bound" ]; then
            print_info "PVC verification: OK (Bound)"
        else
            print_warning "PVC status: ${pvc_status} (provisioning...)"
        fi
    else
        print_warning "PVC not found - may take time to provision"
    fi
}

# ========================================
# SSH KEYS
# ========================================

generate_ssh_keys() {
    print_header "GENERATING SSH KEYS"
    
    for i in $(seq 1 $NUM_STUDENTS); do
        echo -e "${BLUE}[${i}/${NUM_STUDENTS}]${NC} Generating keys for student${i}..."
        
        # Applica Job per generare chiavi
        cat kubernetes/03-ssh-keygen-job.yaml | \
            sed "s/namespace: student1/namespace: student${i}/g" | \
            sed "s/student1@lab/student${i}@lab/g" | \
            kubectl apply -f - > /dev/null
        
        # Aspetta completamento job (max 60s)
        if kubectl wait --for=condition=complete --timeout=60s \
            job/generate-ssh-keys -n student${i} &> /dev/null; then
            print_step "Keys generated for student${i}"
        else
            print_warning "Job timeout for student${i}, continuing..."
        fi
        
        # Elimina job completato
        kubectl delete job generate-ssh-keys -n student${i} &> /dev/null || true
    done
}

# ========================================
# CONFIG MAPS
# ========================================

deploy_config_maps() {
    print_header "DEPLOYING CONFIG MAPS"
    
    for i in $(seq 1 $NUM_STUDENTS); do
        kubectl apply -f kubernetes/02-ssh-config.yaml -n student${i} > /dev/null
    done
    
    print_step "SSH ConfigMaps created"
}

# ========================================
# STUDENT LABS CON PASSWORD DINAMICHE
# ========================================

deploy_student_labs() {
    print_header "DEPLOYING STUDENT LABS"
    
    # Crea directory per credenziali se non esiste
    mkdir -p "$CREDENTIALS_DIR"
    
    # File riepilogo credenziali
    local cred_file="${CREDENTIALS_DIR}/ALL_CREDENTIALS.txt"
    cat > "$cred_file" << EOF
==========================================
  STUDENT LAB - CREDENTIALS
==========================================

IMPORTANT: Keep these credentials secure!
Distribute to students via secure channel.

Generated on: $(date)
Distribution: ${DISTRO_DISPLAY}
Image: ${FULL_IMAGE}
Sudo mode: ${SUDO_MODE}
StorageClass: ${STORAGE_CLASS:-<cluster default>}

EOF
    
    for i in $(seq 1 $NUM_STUDENTS); do
        echo -e "${BLUE}[${i}/${NUM_STUDENTS}]${NC} Deploying student${i} lab..."
        
        # ==========================================
        # 1. GENERA PASSWORD SICURE
        # ==========================================
        # Password Linux (12 caratteri alfanumerici)
        STUDENT_LINUX_PASSWORD=$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-12)
        
        # Password Code-Server (16 caratteri per maggiore sicurezza)
        CODE_SERVER_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)
        
        # ==========================================
        # 2. CREA/AGGIORNA SECRET
        # ==========================================
        kubectl create secret generic student-credentials \
          --from-literal=code-server-password="${CODE_SERVER_PASSWORD}" \
          --from-literal=student-password="${STUDENT_LINUX_PASSWORD}" \
          -n "student${i}" \
          --dry-run=client -o yaml | kubectl apply -f - > /dev/null
        
        # ==========================================
        # 3. SALVA CREDENZIALI IN FILE
        # ==========================================
        cat >> "$cred_file" << EOF
Student ${i}:
  Code-Server URL: https://student${i}.${BASE_DOMAIN}
  Code-Server Password: ${CODE_SERVER_PASSWORD}
  
  Cockpit URL: https://student${i}.${BASE_DOMAIN}/cockpit
  Cockpit Username: student
  Cockpit Password: ${STUDENT_LINUX_PASSWORD}
  
  Linux Password: ${STUDENT_LINUX_PASSWORD}
  SSH: ssh student@student${i}.${BASE_DOMAIN} (if exposed)

EOF
        
        # Salva anche in file individuale
        cat > "${CREDENTIALS_DIR}/student${i}.txt" << EOF
Student ${i} Credentials
========================

Code-Server (IDE):
  URL: https://student${i}.${BASE_DOMAIN}
  Password: ${CODE_SERVER_PASSWORD}

Cockpit (System Admin GUI):
  URL: https://student${i}.${BASE_DOMAIN}/cockpit
  Username: student
  Password: ${STUDENT_LINUX_PASSWORD}

Linux System:
  Username: student
  Password: ${STUDENT_LINUX_PASSWORD}

SSH Connection (from client container):
  ssh server1
  ssh server2

Notes:
  - Access Code-Server (IDE) with Code-Server password
  - Access Cockpit (System GUI) with Linux username/password
  - Use Linux password for sudo and terminal login
  - SSH keys are pre-configured for server1/server2

Generated: $(date)
Distribution: ${DISTRO_DISPLAY}
StorageClass: ${STORAGE_CLASS:-<cluster default>}
EOF
        
        # ==========================================
        # 4. APPLICA DEPLOYMENT BASE
        # ==========================================
        cat kubernetes/04-student-lab-secure.yaml | \
            # Sostituzioni namespace e immagine
            sed "s|namespace: student1|namespace: student${i}|g" | \
            sed "s|student: \"1\"|student: \"${i}\"|g" | \
            sed "s|vcnngr.io/linux-lab:latest|${FULL_IMAGE}|g" | \
            sed "s|value: \"limited\"|value: \"${SUDO_MODE}\"|g" | \
            kubectl apply -f - > /dev/null
        
        # ==========================================
        # 5. AGGIUNGI VARIABILE D'AMBIENTE STUDENT_PASSWORD
        # ==========================================
        # Patch per aggiungere la variabile d'ambiente ai container linux
        
        # Client
        kubectl patch deployment client -n "student${i}" --type='json' -p='[
          {
            "op": "add",
            "path": "/spec/template/spec/containers/1/env/-",
            "value": {
              "name": "STUDENT_PASSWORD",
              "valueFrom": {
                "secretKeyRef": {
                  "name": "student-credentials",
                  "key": "student-password"
                }
              }
            }
          }
        ]' > /dev/null 2>&1 || true
        
        # Server1
        kubectl patch deployment server1 -n "student${i}" --type='json' -p='[
          {
            "op": "add",
            "path": "/spec/template/spec/containers/0/env/-",
            "value": {
              "name": "STUDENT_PASSWORD",
              "valueFrom": {
                "secretKeyRef": {
                  "name": "student-credentials",
                  "key": "student-password"
                }
              }
            }
          }
        ]' > /dev/null 2>&1 || true
        
        # Server2
        kubectl patch deployment server2 -n "student${i}" --type='json' -p='[
          {
            "op": "add",
            "path": "/spec/template/spec/containers/0/env/-",
            "value": {
              "name": "STUDENT_PASSWORD",
              "valueFrom": {
                "secretKeyRef": {
                  "name": "student-credentials",
                  "key": "student-password"
                }
              }
            }
          }
        ]' > /dev/null 2>&1 || true
        
        # ==========================================
        # 6. APPLICA NETWORK POLICIES E RESOURCE LIMITS
        # ==========================================
        cat kubernetes/05-network-policies.yaml | \
            sed "s/namespace: student1/namespace: student${i}/g" | \
            kubectl apply -f - > /dev/null
        
        cat kubernetes/06-resource-limits.yaml | \
            sed "s/namespace: student1/namespace: student${i}/g" | \
            kubectl apply -f - > /dev/null
        
        print_step "Lab deployed for student${i}"
    done
    
    print_info "Credentials saved to: ${CREDENTIALS_DIR}/"
}

# ========================================
# TRAEFIK INGRESS
# ========================================

deploy_traefik_ingress() {
    print_header "DEPLOYING TRAEFIK INGRESS"
    
    # Deploy middleware globali
    print_info "Deploying Traefik middleware..."
    kubectl apply -f kubernetes/07-traefik-middleware.yaml > /dev/null
    
    # Deploy TLS configuration
    print_info "Configuring TLS..."
    kubectl apply -f kubernetes/08-traefik-tls.yaml > /dev/null
    
    # Deploy IngressRoute per ogni studente
    for i in $(seq 1 $NUM_STUDENTS); do
        echo -e "${BLUE}[${i}/${NUM_STUDENTS}]${NC} Creating IngressRoute for student${i}..."
        
        cat <<EOF | kubectl apply -f - > /dev/null
---
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: student${i}-http
  namespace: student${i}
spec:
  entryPoints:
    - web
  routes:
  - match: Host(\`student${i}.${BASE_DOMAIN}\`)
    kind: Rule
    services:
    - name: client
      port: 8080
    middlewares:
    - name: https-redirect
      namespace: default
---
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: student${i}-https
  namespace: student${i}
spec:
  entryPoints:
    - websecure
  routes:
  - match: Host(\`student${i}.${BASE_DOMAIN}\`)
    kind: Rule
    services:
    - name: client
      port: 8080
    middlewares:
    - name: student-lab-chain
      namespace: default
  tls:
    secretName: lab-wildcard-tls
EOF
    done
    
    print_step "Traefik IngressRoutes created"
}

# ========================================
# COCKPIT INGRESS ROUTES
# ========================================

deploy_cockpit_routes() {
    print_header "DEPLOYING COCKPIT INGRESS ROUTES"
    
    for i in $(seq 1 $NUM_STUDENTS); do
        echo -e "${BLUE}[${i}/${NUM_STUDENTS}]${NC} Creating Cockpit route for student${i}..."
        
        cat <<EOF | kubectl apply -f - > /dev/null
---
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: cockpit-route
  namespace: student${i}
spec:
  entryPoints:
    - websecure
  routes:
  - match: Host(\`student${i}.${BASE_DOMAIN}\`) && PathPrefix(\`/cockpit\`)
    kind: Rule
    services:
    - name: client
      port: 9090
  tls:
    secretName: lab-wildcard-tls
EOF
    done
    
    print_step "Cockpit IngressRoutes created"
    print_info "Cockpit accessible at: https://studentN.${BASE_DOMAIN}/cockpit"
}

# ========================================
# WAIT FOR PODS
# ========================================

wait_for_pods() {
    print_header "WAITING FOR PODS TO BE READY"
    
    print_info "This may take a few minutes..."
    echo ""
    
    for i in $(seq 1 $NUM_STUDENTS); do
        echo -e "${BLUE}[${i}/${NUM_STUDENTS}]${NC} Waiting for student${i} pods..."
        
        # Client
        if kubectl wait --for=condition=ready --timeout=180s \
            pod -l app=client -n student${i} &> /dev/null; then
            echo -e "  ${GREEN}✓${NC} Client ready"
        else
            echo -e "  ${YELLOW}⚠ ${NC} Client timeout"
        fi
        
        # Server1
        if kubectl wait --for=condition=ready --timeout=180s \
            pod -l app=server1 -n student${i} &> /dev/null; then
            echo -e "  ${GREEN}✓${NC} Server1 ready"
        else
            echo -e "  ${YELLOW}⚠ ${NC} Server1 timeout"
        fi
        
        # Server2
        if kubectl wait --for=condition=ready --timeout=180s \
            pod -l app=server2 -n student${i} &> /dev/null; then
            echo -e "  ${GREEN}✓${NC} Server2 ready"
        else
            echo -e "  ${YELLOW}⚠ ${NC} Server2 timeout"
        fi
    done
    
    echo ""
    print_step "Pod startup phase completed"
}

# ========================================
# SUMMARY
# ========================================

print_summary() {
    print_header "DEPLOYMENT SUMMARY"
    
    echo -e "${GREEN}✓ Lab deployment completed!${NC}"
    echo ""
    echo -e "${CYAN}Configuration:${NC}"
    echo "  • Students: $NUM_STUDENTS"
    echo "  • Distribution: $DISTRO_DISPLAY"
    echo "  • Sudo mode: $SUDO_MODE"
    echo "  • Image: ${FULL_IMAGE}"
    echo "  • Base domain: $BASE_DOMAIN"
    echo "  • Ingress: Traefik"
    echo "  • Persistent Storage: Enabled (PVC)"
    echo "  • StorageClass: ${STORAGE_CLASS:-<cluster default>}"
    echo "  • Dynamic Passwords: Enabled"
    echo "  • Cockpit System GUI: Enabled (port 9090)"
    echo ""
    echo -e "${CYAN}Credentials:${NC}"
    echo "  • Saved in: ${CREDENTIALS_DIR}/"
    echo "  • All credentials: ${CREDENTIALS_DIR}/ALL_CREDENTIALS.txt"
    echo "  • Individual files: ${CREDENTIALS_DIR}/student[1-${NUM_STUDENTS}].txt"
    echo ""
    echo -e "${YELLOW}⚠ IMPORTANT SECURITY NOTES:${NC}"
    echo "  1. Distribute credentials securely to students"
    echo "  2. Backup credentials directory: ${CREDENTIALS_DIR}/"
    echo "  3. Each student has unique passwords"
    echo "  4. Consider rotating passwords after each lab session"
    echo ""
    echo -e "${CYAN}Student Access:${NC}"
    for i in $(seq 1 3); do
        echo "  Student ${i}:"
        echo "    - Code-Server: https://student${i}.${BASE_DOMAIN}"
        echo "    - Cockpit GUI: https://student${i}.${BASE_DOMAIN}/cockpit"
    done
    if [ $NUM_STUDENTS -gt 3 ]; then
        echo "  ... (see ${CREDENTIALS_DIR}/ALL_CREDENTIALS.txt for all)"
    fi
    echo ""
    echo -e "${CYAN}Useful commands:${NC}"
    echo "  • View all pods:        kubectl get pods --all-namespaces | grep student"
    echo "  • View PVCs:            kubectl get pvc -A | grep student"
    echo "  • Check credentials:    cat ${CREDENTIALS_DIR}/ALL_CREDENTIALS.txt"
    echo "  • Test SSH:             ./scripts/test-ssh-setup.sh 1"
    echo "  • Management:           ./scripts/management-commands.sh"
    echo ""
}

# ========================================
# MAIN
# ========================================

main() {
    print_header "LINUX LAB K8S DEPLOYMENT"
    
    # Scegli distribuzione
    choose_distro
    
    # Scegli StorageClass
    choose_storage_class
    
    echo ""
    echo -e "${CYAN}Configuration Summary:${NC}"
    echo "  Registry: $REGISTRY"
    echo "  Image: ${FULL_IMAGE}"
    echo "  Distribution: $DISTRO_DISPLAY"
    echo "  Students: $NUM_STUDENTS"
    echo "  Base domain: $BASE_DOMAIN"
    echo "  Sudo mode: $SUDO_MODE"
    echo "  Ingress: Traefik"
    echo "  Persistent Storage: YES (PVC)"
    echo "  StorageClass: ${STORAGE_CLASS:-<cluster default>}"
    echo "  Dynamic Passwords: YES"
    echo "  Cockpit GUI: YES (port 9090)"
    echo ""
    
    read -p "Continue with deployment? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled."
        exit 0
    fi
    
    # Deployment steps
    check_requirements
    pull_image
    create_namespaces
    deploy_config_maps
    generate_ssh_keys
    deploy_persistent_volumes
    deploy_student_labs
    deploy_traefik_ingress
    deploy_cockpit_routes
    wait_for_pods
    print_summary
}

# Run main
main "$@"
