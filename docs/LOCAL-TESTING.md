# Local Testing Guide

Questa guida spiega come testare le immagini Docker del progetto Linux Lab **prima** di effettuare il deploy su Kubernetes.

## 📋 Indice

- [Prerequisiti](#prerequisiti)
- [Test Rapido con Docker](#test-rapido-con-docker)
- [Test Automatico con Script](#test-automatico-con-script)
- [Test Ambiente Completo con Docker Compose](#test-ambiente-completo-con-docker-compose)
- [Test su Kubernetes Locale (Kind)](#test-su-kubernetes-locale-kind)
- [Test Manuali Approfonditi](#test-manuali-approfonditi)
- [Troubleshooting](#troubleshooting)
- [Checklist Pre-Deploy](#checklist-pre-deploy)

---

## Prerequisiti

Software necessario per i test locali:

```bash
# Docker (richiesto)
docker --version

# Docker Compose (opzionale, per test ambiente completo)
docker-compose --version

# Kind (opzionale, per test Kubernetes locale)
kind --version

# Kubectl (opzionale, per test Kubernetes)
kubectl version --client
```

---

## Test Rapido con Docker

### Build e Avvio Container

```bash
# 1. Build immagine Ubuntu
cd docker/
docker build -t linux-lab-ubuntu:test -f Dockerfile-ubuntu .

# 2. Build immagine Rocky Linux
docker build -t linux-lab-rocky:test -f Dockerfile-rocky .

# 3. Avvia container di test
docker run -d \
  --name lab-test \
  --privileged \
  --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  -p 2222:22 \
  -p 8080:8080 \
  -p 9090:9090 \
  linux-lab-ubuntu:test

# 4. Verifica che sia running
docker ps | grep lab-test
```

**Spiegazione parametri**:
- `--privileged`: Necessario per systemd
- `--cgroupns=host`: Permette a systemd di gestire i cgroups
- `-v /sys/fs/cgroup`: Mount necessario per systemd
- `-p`: Mapping porte (host:container)

### Test Servizi Base

```bash
# Attendi 10 secondi per l'inizializzazione di systemd
sleep 10

# Verifica systemd
docker exec lab-test systemctl is-system-running

# Verifica SSH
docker exec lab-test systemctl status ssh        # Ubuntu
docker exec lab-test systemctl status sshd       # Rocky

# Verifica Code-Server
docker exec lab-test systemctl status code-server@student

# Verifica Cockpit
docker exec lab-test systemctl status cockpit.socket
```

### Test Accesso Web

```bash
# Test Code-Server
curl -I http://localhost:8080
# Output atteso: HTTP/1.1 302 Found (redirect a /login)

# Test Cockpit
curl -k -I https://localhost:9090
# Output atteso: HTTP/1.1 401 Unauthorized (richiede login)

# Apri nel browser
xdg-open http://localhost:8080      # Code-Server
xdg-open https://localhost:9090     # Cockpit (accetta certificato)
```

### Test SSH

```bash
# Login con password
ssh -p 2222 student@localhost
# Password: student123

# Una volta dentro:
whoami              # Dovrebbe restituire: student
sudo whoami         # Dovrebbe restituire: root (dopo password)
systemctl status    # Verifica systemd funziona
exit
```

### Cleanup

```bash
# Stop e rimuovi container
docker stop lab-test
docker rm lab-test

# Rimuovi immagini (opzionale)
docker rmi linux-lab-ubuntu:test
docker rmi linux-lab-rocky:test
```

---

## Test Automatico con Script

### Script di Test Automatico

Crea il file `scripts/test-image.sh`:

```bash
#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DOCKERFILE=${1:-Dockerfile-ubuntu}
IMAGE_NAME="linux-lab-test"
CONTAINER_NAME="lab-test-$$"

print_test() { echo -e "${YELLOW}Testing: $1${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }

cleanup() {
    docker stop $CONTAINER_NAME 2>/dev/null || true
    docker rm $CONTAINER_NAME 2>/dev/null || true
}
trap cleanup EXIT

# Build
print_test "Building image from $DOCKERFILE"
docker build -t $IMAGE_NAME:latest -f docker/$DOCKERFILE docker/
print_success "Build completed"

# Run
print_test "Starting container"
docker run -d --name $CONTAINER_NAME --privileged --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  -p 8080:8080 -p 9090:9090 -p 2222:22 \
  $IMAGE_NAME:latest > /dev/null
print_success "Container started"

# Wait
print_test "Waiting for systemd (15s)"
sleep 15

# Tests
print_test "Container running"
docker ps | grep -q $CONTAINER_NAME && print_success "OK" || { print_error "Failed"; exit 1; }

print_test "Systemd status"
docker exec $CONTAINER_NAME systemctl is-system-running 2>/dev/null && print_success "OK" || print_error "Failed"

print_test "SSH service"
docker exec $CONTAINER_NAME systemctl is-active ssh 2>/dev/null || \
docker exec $CONTAINER_NAME systemctl is-active sshd 2>/dev/null
print_success "OK"

print_test "Student user"
docker exec $CONTAINER_NAME id student &>/dev/null && print_success "OK" || print_error "Failed"

print_test "Sudo permissions"
docker exec $CONTAINER_NAME sudo -u student sudo whoami | grep -q root && print_success "OK" || print_error "Failed"

print_test "Code-Server"
docker exec $CONTAINER_NAME systemctl is-active code-server@student 2>/dev/null && print_success "OK" || echo "Not active"

print_test "Cockpit"
docker exec $CONTAINER_NAME systemctl is-active cockpit.socket 2>/dev/null && print_success "OK" || echo "Not installed"

echo ""
echo "Access URLs:"
echo "  Code-Server: http://localhost:8080"
echo "  Cockpit:     https://localhost:9090"
echo "  SSH:         ssh -p 2222 student@localhost"
echo ""
echo "Container: $CONTAINER_NAME (will be cleaned up on exit)"
```

### Utilizzo

```bash
# Rendi eseguibile
chmod +x scripts/test-image.sh

# Test Ubuntu
./scripts/test-image.sh Dockerfile-ubuntu

# Test Rocky
./scripts/test-image.sh Dockerfile-rocky
```

---

## Test Ambiente Completo con Docker Compose

### File docker-compose.test.yml

Crea il file `docker-compose.test.yml` nella root del progetto:

```yaml
version: '3.8'

services:
  client:
    build:
      context: ./docker
      dockerfile: Dockerfile-ubuntu
    container_name: test-client
    privileged: true
    cgroupns: host
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:rw
      - test-workspace:/home/student
    ports:
      - "8080:8080"
      - "9090:9090"
      - "2222:22"
    networks:
      - test-net

  server1:
    build:
      context: ./docker
      dockerfile: Dockerfile-rocky
    container_name: test-server1
    privileged: true
    cgroupns: host
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:rw
    ports:
      - "2223:22"
    networks:
      - test-net
    hostname: server1

  server2:
    build:
      context: ./docker
      dockerfile: Dockerfile-ubuntu
    container_name: test-server2
    privileged: true
    cgroupns: host
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:rw
    ports:
      - "2224:22"
    networks:
      - test-net
    hostname: server2

volumes:
  test-workspace:

networks:
  test-net:
    driver: bridge
```

### Utilizzo Docker Compose

```bash
# Build e avvia ambiente completo
docker-compose -f docker-compose.test.yml up -d

# Verifica containers
docker-compose -f docker-compose.test.yml ps

# Logs in tempo reale
docker-compose -f docker-compose.test.yml logs -f

# Test connessione SSH tra containers
docker exec -it test-client bash
su - student
ping server1
ping server2
ssh server1  # (se SSH keys configurate)
exit

# Cleanup completo
docker-compose -f docker-compose.test.yml down -v
```

---

## Test su Kubernetes Locale (Kind)

### Installazione Kind

```bash
# Download Kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Verifica installazione
kind version
```

### Test con Kind

```bash
# 1. Crea cluster locale
kind create cluster --name lab-test

# 2. Build immagine
docker build -t linux-lab:test -f docker/Dockerfile-ubuntu docker/

# 3. Carica immagine in Kind
kind load docker-image linux-lab:test --name lab-test

# 4. Configura variabili per test
export NUM_STUDENTS=1
export BASE_DOMAIN="test.local"
export REGISTRY="local"
export IMAGE_NAME="linux-lab"
export IMAGE_TAG="test"

# 5. Deploy (solo 1 studente)
./scripts/deploy-lab.sh

# 6. Verifica pod
kubectl get pods -n student1
kubectl describe pod -n student1

# 7. Port-forward per accesso
kubectl port-forward -n student1 svc/client 8080:8080 &
kubectl port-forward -n student1 svc/client 9090:9090 &

# 8. Test browser
xdg-open http://localhost:8080
xdg-open https://localhost:9090

# 9. Cleanup
kind delete cluster --name lab-test
```

---

## Test Manuali Approfonditi

### Accesso Interattivo al Container

```bash
# Entra nel container
docker exec -it lab-test /bin/bash

# Test systemd
systemctl status
systemctl list-units --type=service --state=running

# Test utenti
id student
groups student
cat /etc/passwd | grep student
cat /etc/sudoers.d/student

# Test SSH
systemctl status ssh
cat /etc/ssh/sshd_config | grep -v "^#" | grep -v "^$"

# Test workspace
ls -la /home/student/
df -h /home/student/

# Test networking
ip addr
ping -c 3 google.com

# Exit
exit
```

### Test SSH Keys

```bash
# 1. Genera chiave di test
ssh-keygen -t ed25519 -f /tmp/test-key -N ""

# 2. Copia nel container
docker cp /tmp/test-key.pub lab-test:/tmp/

# 3. Configura authorized_keys
docker exec -it lab-test bash
su - student
mkdir -p ~/.ssh
chmod 700 ~/.ssh
cat /tmp/test-key.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
exit
exit

# 4. Test connessione con chiave
ssh -i /tmp/test-key -p 2222 student@localhost

# 5. Cleanup
rm /tmp/test-key*
```

### Test Performance e Dimensioni

```bash
# Dimensione immagine
docker images linux-lab-test

# Analizza layers
docker history linux-lab-test:latest --no-trunc

# Trova layers più pesanti
docker history linux-lab-test:latest --format "{{.Size}}\t{{.CreatedBy}}" | sort -hr | head -10

# Uso risorse container
docker stats lab-test --no-stream

# Uso memoria dettagliato
docker exec lab-test free -h

# Processi attivi
docker exec lab-test ps aux
```

### Test Sicurezza

```bash
# Scansione vulnerabilità con Trivy (se installato)
trivy image linux-lab-test:latest

# Oppure Docker Scout
docker scout cves linux-lab-test:latest

# Verifica capabilities
docker exec lab-test capsh --print

# Verifica AppArmor/SELinux
docker exec lab-test aa-status 2>/dev/null || echo "AppArmor not active"
```

---

## Troubleshooting

### Container Non Si Avvia

```bash
# Verifica logs
docker logs lab-test

# Avvia in modalità interattiva
docker run -it --rm --privileged --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  linux-lab-test:latest /bin/bash

# Se systemd non parte, prova:
exec /sbin/init
```

### Systemd Non Funziona

```bash
# Verifica cgroups v2
mount | grep cgroup

# Su host, abilita cgroups v2 se necessario
sudo grubby --update-kernel=ALL --args="systemd.unified_cgroup_hierarchy=1"
sudo reboot
```

### Porte Non Accessibili

```bash
# Verifica porte in ascolto nel container
docker exec lab-test netstat -tulpn

# Verifica mapping porte
docker port lab-test

# Test diretto
telnet localhost 8080
telnet localhost 9090
```

### Code-Server Non Risponde

```bash
# Verifica servizio
docker exec lab-test systemctl status code-server@student

# Verifica logs
docker exec lab-test journalctl -u code-server@student -n 50

# Restart manuale
docker exec lab-test systemctl restart code-server@student
```

### Cockpit Non Risponde

```bash
# Verifica servizio
docker exec lab-test systemctl status cockpit.socket

# Verifica porta
docker exec lab-test ss -tlnp | grep 9090

# Restart
docker exec lab-test systemctl restart cockpit.socket
```

---

## Checklist Pre-Deploy

Prima di fare deploy su Kubernetes, verifica:

### Build e Avvio
- [ ] Immagine builda senza errori
- [ ] Container parte e resta running per almeno 5 minuti
- [ ] Nessun errore critico nei logs (`docker logs`)

### Systemd e Servizi
- [ ] Systemd è operativo (`systemctl is-system-running`)
- [ ] SSH service è attivo e in ascolto sulla porta 22
- [ ] Code-Server è attivo sulla porta 8080
- [ ] Cockpit è attivo sulla porta 9090 (se installato)

### Utenti e Permessi
- [ ] Utente `student` esiste
- [ ] Utente `student` ha permessi sudo
- [ ] Home directory `/home/student` esiste ed è scrivibile
- [ ] SSH login con password funziona

### Networking
- [ ] Porte 22, 8080, 9090 rispondono
- [ ] Browser accede a Code-Server (http://localhost:8080)
- [ ] Browser accede a Cockpit (https://localhost:9090)
- [ ] SSH funziona (`ssh -p 2222 student@localhost`)

### Sicurezza
- [ ] Password di default sono configurate correttamente
- [ ] Capabilities limitate (no SYS_ADMIN se non necessario)
- [ ] No vulnerabilità critiche (scan con trivy/scout)

### Performance
- [ ] Immagine < 2GB (preferibilmente < 1GB)
- [ ] Container usa < 512MB RAM idle
- [ ] Avvio completo < 30 secondi

### Funzionalità Specifiche
- [ ] SSH keys (se configurate) funzionano
- [ ] Workspace persistente (se PVC configurato)
- [ ] Network tra client-server1-server2 funziona (test Docker Compose)

---

## Riferimenti Rapidi

### Comandi Utili

```bash
# Build rapido
docker build -t test -f docker/Dockerfile-ubuntu docker/

# Run rapido
docker run -d --name test --privileged --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  -p 8080:8080 -p 9090:9090 -p 2222:22 test

# Entra
docker exec -it test bash

# Cleanup
docker stop test && docker rm test && docker rmi test
```

### Porte Standard

| Servizio | Porta Container | Porta Host (test) | Protocollo |
|----------|----------------|-------------------|------------|
| SSH | 22 | 2222 | TCP |
| Code-Server | 8080 | 8080 | HTTP |
| Cockpit | 9090 | 9090 | HTTPS |

### Credenziali Default

- **Utente**: `student`
- **Password**: `student123`
- **Sudo**: Abilitato

---

## Note Finali

- Testa **sempre** localmente prima del deploy su Kubernetes
- Usa **Kind** per simulare ambiente Kubernetes reale
- Verifica **tutti** i servizi funzionino correttamente
- Controlla **logs** per errori anche se i servizi partono
- Esegui **scan sicurezza** prima di usare in produzione

Per domande o problemi, consulta la documentazione principale nel `README.md`.