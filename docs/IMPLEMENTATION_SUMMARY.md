# Riepilogo Implementazione Miglioramenti

## ✅ Modifiche Implementate

### 1. ✅ Persistenza Dati con PVC (COMPLETATO)

**File Creati:**
- `kubernetes/04a-student-pvc.yaml` - Nuovo file per PersistentVolumeClaim

**File Modificati:**
- `kubernetes/04-student-lab-secure.yaml` - Workspace ora usa PVC invece di emptyDir
- `scripts/deploy-lab.sh` - Aggiunta funzione `deploy_persistent_volumes()`
- `scripts/cleanup-lab.sh` - Gestione backup e cleanup PVC

**Funzionalità:**
- Workspace studente (5Gi) persistente tra restart
- Supporto backup automatico prima del cleanup
- Compatibile con qualsiasi StorageClass del cluster

---

### 2. ✅ Gestione Sicura Credenziali (COMPLETATO)

**File Modificati:**
- `docker/Dockerfile-ubuntu` - Rimossa password hardcoded
- `docker/Dockerfile-debian` - Rimossa password hardcoded
- `docker/Dockerfile-rocky` - Rimossa password hardcoded
- `docker/entrypoint.sh` - Gestione dinamica password via env var
- `kubernetes/04-student-lab-secure.yaml` - Rimosso Secret statico
- `scripts/deploy-lab.sh` - Generazione password casuali + patch deployment

**Funzionalità:**
- Password Linux generate casualmente (12 caratteri)
- Password Code-Server generate casualmente (16 caratteri)
- Credenziali salvate in `./credentials/`
- File individuali per ogni studente
- Secret Kubernetes creati dinamicamente

---

### 3. ❌ Multi-stage Docker Build (SALTATO)

Come da richiesta, questa ottimizzazione non è stata implementata.

---

## 📋 Checklist Pre-Deploy

Prima di eseguire il deploy, assicurati di:

- [ ] Cluster Kubernetes 1.24+ attivo
- [ ] StorageClass configurato (verifica con `kubectl get storageclass`)
- [ ] Traefik installato
- [ ] Docker registry accessibile
- [ ] `openssl` installato localmente

---

## 🚀 Procedura di Deploy

### 1. Backup del Progetto Esistente (se presente)

```bash
# Backup configurazione attuale
kubectl get all,pvc,secrets -A -o yaml > backup-before-upgrade.yaml

# Backup credenziali vecchie (se presenti)
cp -r credentials credentials-backup-$(date +%Y%m%d)
```

### 2. Aggiorna i File

Sostituisci i file nel progetto con le versioni migliorate:

```bash
# Copia i nuovi file nelle rispettive directory
cp 04a-student-pvc.yaml kubernetes/
cp entrypoint.sh docker/
cp Dockerfile-ubuntu docker/
cp Dockerfile-debian docker/
cp Dockerfile-rocky docker/
cp deploy-lab.sh scripts/
cp cleanup-lab.sh scripts/
cp 04-student-lab-secure.yaml kubernetes/
```

### 3. Rendi Eseguibili gli Script

```bash
chmod +x scripts/deploy-lab.sh
chmod +x scripts/cleanup-lab.sh
chmod +x docker/entrypoint.sh
```

### 4. Deploy

```bash
# Esegui il deploy
./scripts/deploy-lab.sh
```

Lo script ti chiederà:
1. Quale distribuzione Linux usare (Ubuntu/Debian/Rocky)
2. Conferma per procedere

---

## 📊 Cosa Cambia per gli Studenti

### Vantaggi

✅ **Dati persistenti**: Il lavoro non si perde al restart
✅ **Sicurezza**: Ogni studente ha password univoche
✅ **Accesso semplice**: URL e credenziali chiare

### Credenziali

**Vecchio sistema:**
- Linux: `student123` (uguale per tutti)
- Code-Server: `studentNpass` (prevedibile)

**Nuovo sistema:**
- Linux: Password casuale 12 caratteri (es: `aB3xK9mP2qL7`)
- Code-Server: Password casuale 16 caratteri (es: `xY9kM3nP8qL2aB4c`)
- Salvate in `./credentials/studentN.txt`

### Distribuzione Credenziali

```bash
# Visualizza tutte le credenziali
cat credentials/ALL_CREDENTIALS.txt

# Credenziali individuali
cat credentials/student1.txt
cat credentials/student2.txt
```

**Raccomandazioni:**
- Distribuisci via canale sicuro (email criptata, password manager)
- Non condividere in chat pubbliche
- Considera rotazione dopo ogni sessione lab

---

## 🔍 Verifica Post-Deploy

### Test Base

```bash
# 1. Verifica PVC creati e bound
kubectl get pvc -A | grep student

# Output atteso:
# student1   student-workspace-pvc   Bound    pvc-xxx   5Gi        RWO
# student2   student-workspace-pvc   Bound    pvc-yyy   5Gi        RWO
# ...

# 2. Verifica secret con password
kubectl get secret student-credentials -n student1 -o yaml

# Deve contenere:
#   code-server-password: <base64>
#   student-password: <base64>

# 3. Verifica variabile d'ambiente nel pod
kubectl get pod -n student1 -l app=client -o yaml | grep STUDENT_PASSWORD

# Output atteso:
# - name: STUDENT_PASSWORD
#   valueFrom:
#     secretKeyRef:
#       key: student-password
#       name: student-credentials

# 4. Test accesso web
curl -I https://student1.lab.example.com
# Deve rispondere 200 o redirect HTTPS

# 5. Test SSH interno
./scripts/test-ssh-setup.sh 1
```

### Test Persistenza

```bash
# 1. Crea file in workspace
kubectl exec -n student1 deployment/client -c linux -- \
  bash -c "echo 'Test persistenza' > /home/student/workspace/test.txt"

# 2. Leggi contenuto
kubectl exec -n student1 deployment/client -c linux -- \
  cat /home/student/workspace/test.txt

# 3. Riavvia pod
kubectl delete pod -n student1 -l app=client

# 4. Aspetta che riparta
kubectl wait --for=condition=ready pod -l app=client -n student1 --timeout=120s

# 5. Verifica file ancora presente
kubectl exec -n student1 deployment/client -c linux -- \
  cat /home/student/workspace/test.txt

# Output atteso: "Test persistenza"
```

---

## 🛠️ Troubleshooting

### PVC in stato Pending

**Problema:** `kubectl get pvc` mostra PVC in stato "Pending"

**Causa:** Nessun StorageClass disponibile o configurato male

**Soluzione:**
```bash
# Verifica StorageClass
kubectl get storageclass

# Se nessuno è (default), impostane uno:
kubectl patch storageclass <nome> -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Oppure specifica nel PVC:
# Edita kubernetes/04a-student-pvc.yaml e decommenta:
# storageClassName: "standard"  # o il nome della tua SC
```

### Password non funziona

**Problema:** La password Linux non funziona

**Causa:** Variabile d'ambiente non passata al container

**Soluzione:**
```bash
# Verifica che il patch sia stato applicato
kubectl get deployment client -n student1 -o yaml | grep -A5 STUDENT_PASSWORD

# Se non c'è, applica manualmente:
kubectl set env deployment/client -n student1 \
  STUDENT_PASSWORD="$(kubectl get secret student-credentials -n student1 -o jsonpath='{.data.student-password}' | base64 -d)"

# Riavvia pod
kubectl rollout restart deployment/client -n student1
```

### Container in CrashLoopBackOff

**Problema:** Pod non parte, errore nel log "chpasswd: PAM: Authentication token manipulation error"

**Causa:** Permessi mancanti o entrypoint non eseguibile

**Soluzione:**
```bash
# Verifica logs
kubectl logs -n student1 -l app=client -c linux --tail=50

# Rebuilda immagine assicurandoti che entrypoint.sh sia +x
docker build -f docker/Dockerfile-ubuntu -t vcnngr.io/linux-lab:latest docker/
docker push vcnngr.io/linux-lab:latest

# Forza re-pull
kubectl rollout restart deployment/client -n student1
```

### Credenziali perse

**Problema:** File `credentials/` eliminato per errore

**Soluzione:**
```bash
# Le password sono ancora nei secret!
# Recuperale:
for i in {1..6}; do
  echo "=== Student $i ==="
  echo -n "Code-Server: "
  kubectl get secret student-credentials -n student${i} \
    -o jsonpath='{.data.code-server-password}' | base64 -d
  echo
  echo -n "Linux: "
  kubectl get secret student-credentials -n student${i} \
    -o jsonpath='{.data.student-password}' | base64 -d
  echo
  echo
done > credentials-recovered.txt
```

---

## 📈 Monitoraggio

### PVC Usage

```bash
# Spazio usato dai PVC (richiede metric-server)
kubectl top pod -n student1 | grep client

# Dettagli PVC
kubectl describe pvc student-workspace-pvc -n student1
```

### Prometheus Queries

Se hai monitoring attivo:

```promql
# Storage usage per studente
kubelet_volume_stats_used_bytes{namespace=~"student.*"}

# Storage disponibile
kubelet_volume_stats_available_bytes{namespace=~"student.*"}

# % usage
(kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes) * 100
```

---

## 🔄 Rotazione Password

Per cambiare le password dopo una sessione:

```bash
# Script di rotazione password
for i in {1..6}; do
  NEW_PASSWORD=$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-12)
  
  kubectl create secret generic student-credentials \
    --from-literal=code-server-password="$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)" \
    --from-literal=student-password="${NEW_PASSWORD}" \
    -n student${i} --dry-run=client -o yaml | kubectl apply -f -
  
  # Riavvia pod per applicare nuova password
  kubectl rollout restart deployment/client -n student${i}
  kubectl rollout restart deployment/server1 -n student${i}
  kubectl rollout restart deployment/server2 -n student${i}
  
  echo "Student ${i}: ${NEW_PASSWORD}"
done
```

---

## 📚 Documentazione Aggiuntiva

### Per gli Studenti

Aggiorna il README.txt nei container con info sulle password:

```bash
# Esempio di nota da aggiungere
cat >> /home/student/README.txt << 'EOF'

CREDENZIALI:
La tua password è stata generata casualmente per sicurezza.
Trovala nel file fornito dal docente.
Non condividerla con altri studenti.

EOF
```

### Per il Docente

Crea una guida rapida:

```markdown
# Guida Rapida Docente

## Accesso Credenziali
- File master: `./credentials/ALL_CREDENTIALS.txt`
- File individuali: `./credentials/studentN.txt`

## Distribuzione
1. Stampa credenziali individuali
2. Consegna in busta chiusa
3. O invia via email criptata

## Reset Ambiente Studente
kubectl delete pod -n studentN -l app=client

## Backup Workspace
kubectl exec -n studentN deployment/client -c linux -- \
  tar czf - -C /home/student workspace | \
  cat > backup-studentN.tar.gz

## Restore Workspace
cat backup-studentN.tar.gz | \
  kubectl exec -i -n studentN deployment/client -c linux -- \
  tar xzf - -C /home/student
```

---

## ✅ Checklist Finale

Dopo il deploy, verifica:

- [ ] Tutti i PVC sono Bound
- [ ] Tutti i pod sono Running
- [ ] File credenziali creati in `./credentials/`
- [ ] Test SSH funziona (`./scripts/test-ssh-setup.sh 1`)
- [ ] Accesso web funziona con nuove password
- [ ] Persistenza testata (crea file, riavvia pod, file ancora presente)
- [ ] Credenziali distribuite agli studenti
- [ ] Backup credenziali fatto

---

## 🎓 Best Practices

1. **Backup regolari**: Esegui backup PVC prima di ogni manutenzione
2. **Rotazione password**: Cambia password tra sessioni diverse
3. **Monitoring**: Controlla uso storage PVC
4. **Documentazione**: Mantieni log di quali studenti hanno accesso
5. **Cleanup**: Usa `./scripts/cleanup-lab.sh` con backup alla fine del corso

---

## 📞 Supporto

In caso di problemi:

1. Controlla i log: `kubectl logs -n studentN -l app=client`
2. Verifica eventi: `kubectl get events -n studentN`
3. Test SSH: `./scripts/test-ssh-setup.sh N`
4. Consulta troubleshooting sopra

---

**Versione:** 1.1 (con PVC e password dinamiche)  
**Data:** 2025-01-XX  
**Autore:** Linux Lab Team