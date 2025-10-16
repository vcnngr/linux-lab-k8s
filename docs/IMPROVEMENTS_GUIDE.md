# Guida all'Implementazione dei Miglioramenti

Questo documento descrive i passaggi per rendere il progetto "Linux Lab su Kubernetes" più robusto, sicuro e resiliente, implementando le seguenti funzionalità:

1.  **Persistenza dei Dati**: Utilizzo di `PersistentVolumeClaim` per salvare il lavoro degli studenti.
2.  **Gestione Sicura delle Credenziali**: Eliminazione delle password hardcoded e generazione dinamica.
3.  **(Opzionale) Ottimizzazione dell'Immagine Docker**: Riduzione della dimensione dell'immagine con build multi-stage.

-----

## 1\. Persistenza dei Dati con `PersistentVolumeClaim` (PVC)

**Obiettivo**: Evitare la perdita dei dati nella directory `~/workspace` dello studente quando un pod viene riavviato.

**Prerequisiti**: Assicurati che il tuo cluster Kubernetes abbia uno `StorageClass` di default configurato o specificane uno nel file PVC.

### Passaggio 1: Creare il Manifest del PVC

Crea un nuovo file `kubernetes/04a-student-pvc.yaml` per definire la richiesta di storage.

```yaml
# kubernetes/04a-student-pvc.yaml

# Richiesta di volume persistente per la workspace dello studente
# Questo file sarà applicato per ogni namespace studente
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: student-workspace-pvc
  namespace: student1 # Verrà sostituito dinamicamente
spec:
  accessModes:
    - ReadWriteOnce # Accessibile da un solo nodo alla volta, standard per le workspace
  resources:
    requests:
      storage: 5Gi # Dimensione della workspace
  # storageClassName: "your-storage-class" # Decommenta e specifica se non usi la default
```

### Passaggio 2: Modificare il Deployment del Client

Aggiorna `kubernetes/04-student-lab-secure.yaml`. Nella sezione `volumes` del deployment `client`, sostituisci `emptyDir` con il nuovo `persistentVolumeClaim`.

```yaml
# kubernetes/04-student-lab-secure.yaml (sezione volumes del pod client)

# ...
      volumes:
      - name: ssh-config
        configMap:
          name: ssh-config
      # --- INIZIO MODIFICA ---
      # - name: workspace
      #   emptyDir:
      #     sizeLimit: 5Gi
      - name: workspace
        persistentVolumeClaim:
          claimName: student-workspace-pvc
      # --- FINE MODIFICA ---
      - name: ssh-keys
        secret:
          secretName: ssh-keys
# ...
```

### Passaggio 3: Aggiornare lo Script di Deploy

Modifica `scripts/deploy-lab.sh` per creare il PVC per ogni studente prima di deployare i pod.

Aggiungi questa nuova funzione:

```bash
# ========================================
# PERSISTENT VOLUMES
# ========================================

deploy_persistent_volumes() {
    print_header "CREATING PERSISTENT VOLUMES"
    
    for i in $(seq 1 $NUM_STUDENTS); do
        echo -e "${BLUE}[${i}/${NUM_STUDENTS}]${NC} Creating PVC for student${i}..."
        cat kubernetes/04a-student-pvc.yaml | \
            sed "s/namespace: student1/namespace: student${i}/g" | \
            kubectl apply -f - > /dev/null
    done
    
    print_step "PersistentVolumeClaims created"
}
```

Infine, richiama la nuova funzione nel `main()` dello script:

```bash
# scripts/deploy-lab.sh (dentro la funzione main)

# ...
    deploy_config_maps
    generate_ssh_keys
    deploy_persistent_volumes # <-- AGGIUNGI QUESTA RIGA
    deploy_student_labs
    deploy_traefik_ingress
# ...
```

-----

## 2\. Gestione Sicura delle Credenziali

**Obiettivo**: Rimuovere le password statiche (`student123`) dai Dockerfile e impostarle dinamicamente all'avvio del container.

### Passaggio 1: Rimuovere la Password dai Dockerfile

Modifica **tutti e 3 i Dockerfile** (`Dockerfile-ubuntu`, `Dockerfile-debian`, `Dockerfile-rocky`) e rimuovi la riga che imposta la password.

```dockerfile
# Esempio per Dockerfile-ubuntu

# ...
RUN useradd -m -s /bin/bash -u 1001 -G sudo student && \
    # RIMUOVI LA RIGA SEGUENTE
    # echo "student:student123" | chpasswd && \
    mkdir -p /home/student/.ssh && \
    chown -R student:student /home/student && \
    chmod 700 /home/student/.ssh
# ...
```

### Passaggio 2: Aggiornare `entrypoint.sh`

Aggiungi un blocco di codice all'inizio di `docker/entrypoint.sh` per leggere la password da una variabile d'ambiente e impostarla.

```bash
#!/bin/bash
set -e

# ==========================================
#  DYNAMIC PASSWORD SETUP
# ==========================================
# Imposta la password dello studente se fornita tramite variabile d'ambiente
if [ -n "$STUDENT_PASSWORD" ]; then
    echo "student:${STUDENT_PASSWORD}" | chpasswd
    echo "[*] Student password has been set dynamically."
fi
# ==========================================

echo "=========================================="
echo "  LINUX LAB CONTAINER STARTING"
# ... resto dello script
```

### Passaggio 3: Aggiornare lo Script di Deploy

Modifica la funzione `deploy_student_labs` in `scripts/deploy-lab.sh` per generare password sicure, salvarle nei secret e passarle ai container.

> **Nota**: Rimuovi la definizione del secret `student-credentials` dal file `04-student-lab-secure.yaml`, poiché ora viene gestito interamente dallo script.

```bash
# scripts/deploy-lab.sh

# ...
deploy_student_labs() {
    print_header "DEPLOYING STUDENT LABS"
    
    local full_image="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
    
    for i in $(seq 1 $NUM_STUDENTS); do
        echo -e "${BLUE}[${i}/${NUM_STUDENTS}]${NC} Deploying student${i} lab..."

        # 1. Genera password sicure
        STUDENT_LINUX_PASSWORD=$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-12)
        CODE_SERVER_PASSWORD="student${i}pass" # Manteniamo questa per semplicità, ma potrebbe essere generata
        
        # 2. Crea/aggiorna il secret con entrambe le password
        kubectl create secret generic student-credentials \
          --from-literal=code-server-password="${CODE_SERVER_PASSWORD}" \
          --from-literal=student-password="${STUDENT_LINUX_PASSWORD}" \
          -n "student${i}" --dry-run=client -o yaml | kubectl apply -f - > /dev/null

        # 3. Applica il manifest YAML base
        cat kubernetes/04-student-lab-secure.yaml | \
            sed "s|namespace: student1|namespace: student${i}|g" | \
            sed "s|student: \"1\"|student: \"${i}\"|g" | \
            sed "s|vcnngr.io/linux-lab:latest|${full_image}|g" | \
            sed "s|value: \"limited\"|value: \"${SUDO_MODE}\"|g" | \
            kubectl apply -f - > /dev/null
        
        # 4. Aggiungi la variabile d'ambiente ai container 'linux' con kubectl patch
        PATCH_DATA=$(cat <<EOF
spec:
  template:
    spec:
      containers:
      - name: linux
        env:
        - name: STUDENT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: student-credentials
              key: student-password
EOF
)
        # Applica la patch a tutti e 3 i deployment
        kubectl patch deployment client -n "student${i}" --patch "${PATCH_DATA}"
        kubectl patch deployment server1 -n "student${i}" --patch "${PATCH_DATA}"
        kubectl patch deployment server2 -n "student${i}" --patch "${PATCH_DATA}"
        
        print_step "Lab deployed for student${i}. Linux password: ${STUDENT_LINUX_PASSWORD}"
    done
}
# ...
```

-----

## 3\. (Opzionale) Ottimizzazione dell'Immagine Docker

**Obiettivo**: Ridurre la dimensione dell'immagine Docker finale utilizzando un build "multi-stage".

Questo approccio utilizza uno stage intermedio (`builder`) per installare i pacchetti e poi copia solo i file necessari in un'immagine finale pulita, scartando cache e metadati di `apt`.

### Esempio: `Dockerfile-ubuntu` con Multi-stage

```dockerfile
# ================= STAGE 1: BUILDER =================
# Usiamo un'immagine completa per installare tutto il necessario
FROM ubuntu:24.04 as builder

LABEL stage=builder

# Evita prompt interattivi
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Rome

# Installa tutti i pacchetti in un unico layer per ottimizzare
RUN apt-get update && apt-get install -y --no-install-recommends \
    systemd systemd-sysv openssh-server sudo vim nano htop \
    net-tools iputils-ping curl wget git rsync man-db less \
    tmux screen netcat-openbsd dnsutils tree cron rsyslog \
    procps psmisc lsof strace tcpdump iproute2 iptables \
    ca-certificates gnupg tzdata locales \
    && rm -rf /var/lib/apt/lists/*

# ================= STAGE 2: FINAL IMAGE =================
# Partiamo dalla stessa immagine base pulita
FROM ubuntu:24.04

# Metadata
LABEL maintainer="lab@example.com"
LABEL description="Ubuntu 24.04 container for Linux training lab (Optimized)"
LABEL version="1.1"

# Copia solo i file binari e le configurazioni necessarie dallo stage builder
COPY --from=builder /etc /etc
COPY --from=builder /lib /lib
COPY --from=builder /usr /usr
COPY --from=builder /var /var
# Aggiungi /bin e /sbin per completezza, anche se spesso sono symlink
COPY --from=builder /bin /bin
COPY --from=builder /sbin /sbin

# Imposta le variabili d'ambiente necessarie
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Rome
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Esegui le configurazioni che modificano il sistema
RUN locale-gen en_US.UTF-8

# Cleanup e configurazioni (systemd, ssh, user, etc.)
# ... (Copia qui tutte le sezioni RUN dal tuo Dockerfile originale) ...
# Esempio:
RUN systemctl mask getty.target console-getty.service && \
    systemctl enable ssh cron
RUN useradd -m -s /bin/bash -u 1001 -G sudo student && \
    mkdir -p /home/student/.ssh && \
    chown -R student:student /home/student && \
    chmod 700 /home/student/.ssh

# Copia gli script di entrypoint e configurazione
COPY entrypoint.sh setup-ssh-keys.sh sudoers-config.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh

# ... (Banner, README, etc.) ...
COPY motd.txt /etc/motd
COPY README.txt /home/student/README.txt
RUN chown student:student /home/student/README.txt

VOLUME [ "/sys/fs/cgroup" ]
EXPOSE 22

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD systemctl is-active ssh || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/lib/systemd/systemd"]
```

-----

### Comandi di Verifica post-implementazione

Dopo aver applicato le modifiche, usa questi comandi per verificare che tutto funzioni correttamente:

```bash
# Verifica che il PVC sia stato creato e sia 'Bound' (associato a un volume)
kubectl get pvc -n student1

# Verifica che i secret contengano la nuova chiave 'student-password'
kubectl get secret student-credentials -n student1 -o yaml

# Controlla che la variabile d'ambiente STUDENT_PASSWORD sia presente nel container 'linux'
kubectl describe pod -n student1 -l app=client | grep STUDENT_PASSWORD

# Accedi al container e verifica che la password funzioni
# 1. Trova la password generata nei log dello script di deploy
# 2. Esegui una shell nel container
kubectl exec -it -n student1 deployment/client -c linux -- /bin/bash
# 3. Cambia utente e inserisci la password
su - student
```