# 🚀 Quick Start - Linux Lab Migliorato

Guida rapida per deployare il lab con le nuove funzionalità (PVC + password sicure).

---

## ⚡ Deploy in 5 Minuti

```bash
# 1. Clone del progetto
git clone <your-repo>
cd linux-lab-k8s

# 2. Sostituisci i file migliorati
# (Copia i file forniti nelle rispettive directory)

# 3. Configura variabili
export REGISTRY="your-registry.io"
export NUM_STUDENTS="6"
export BASE_DOMAIN="lab.example.com"

# 4. Deploy!
./scripts/deploy-lab.sh
```

**Durata stimata:** 5-10 minuti (dipende da pull immagini)

---

## 📋 Cosa Succede Durante il Deploy

```
┌──────────────────────────────────────┐
│  1. Scelta Distribuzione             │
│     → Ubuntu / Debian / Rocky        │
└──────────────────────────────────────┘
              ↓
┌──────────────────────────────────────┐
│  2. Build Immagine Docker            │
│     → Senza password hardcoded       │
└──────────────────────────────────────┘
              ↓
┌──────────────────────────────────────┐
│  3. Push Registry                    │
└──────────────────────────────────────┘
              ↓
┌──────────────────────────────────────┐
│  4. Crea Namespace                   │
│     → student1, student2, ...        │
└──────────────────────────────────────┘
              ↓
┌──────────────────────────────────────┐
│  5. Genera Chiavi SSH                │
│     → Job Kubernetes automatico      │
└──────────────────────────────────────┘
              ↓
┌──────────────────────────────────────┐
│  6. Crea PVC (NUOVO!)                │
│     → 5Gi per ogni studente          │
└──────────────────────────────────────┘
              ↓
┌──────────────────────────────────────┐
│  7. Genera Password (NUOVO!)         │
│     → Casuali e univoche             │
└──────────────────────────────────────┘
              ↓
┌──────────────────────────────────────┐
│  8. Deploy Pod + Patch Env           │
│     → Client, Server1, Server2       │
└──────────────────────────────────────┘
              ↓
┌──────────────────────────────────────┐
│  9. Deploy Traefik Ingress           │
│     → HTTPS con TLS                  │
└──────────────────────────────────────┘
              ↓
┌──────────────────────────────────────┐
│  10. Output Credenziali              │
│      → ./credentials/                │
└──────────────────────────────────────┘
```

---

## 🔑 Esempio Output Credenziali

Dopo il deploy, troverai i file in `./credentials/`:

### `ALL_CREDENTIALS.txt`
```
==========================================
  STUDENT LAB - CREDENTIALS
==========================================

Student 1:
  URL: https://student1.lab.example.com
  Code-Server Password: xY9kM3nP8qL2aB4c
  Linux Password: aB3xK9mP2qL7

Student 2:
  URL: https://student2.lab.example.com
  Code-Server Password: pQ7rS2tU9vW1xY4z
  Linux Password: cD5eF8gH1iJ3
...
```

### `student1.txt`
```
Student 1 Credentials
========================

Web Access:
  URL: https://student1.lab.example.com
  Password: xY9kM3nP8qL2aB4c

Linux System:
  Username: student
  Password: aB3xK9mP2qL7

SSH Connection (from client container):
  ssh server1
  ssh server2

Notes:
  - Access via browser with Code-Server password
  - Use Linux password for sudo and terminal login
  - SSH keys are pre-configured for server1/server2

Generated: 2025-01-15 10:30:00
```

---

## 👨‍🎓 Esperienza Studente

### 1. Accesso Web

Lo studente apre il browser:

```
https://student1.lab.example.com
```

Inserisce la **Code-Server Password** → Vede VS Code nel browser!

### 2. Terminale Integrato

Clicca `Terminal → New Terminal` in Code-Server:

```bash
student@client:~$ whoami
student

student@client:~$ pwd
/home/student

student@client:~$ ls
exercises/  README.txt  workspace/
```

### 3. Test Connessione SSH

```bash
student@client:~$ ssh server1
Welcome to server1!

student@server1:~$ hostname
server1

student@server1:~$ exit
logout

student@client:~$ ssh server2
Welcome to server2!
```

### 4. Lavoro Persistente

```bash
# Crea file nella workspace
student@client:~$ cd workspace/
student@client:~/workspace$ echo "Il mio lavoro" > progetto.txt

# Anche se il pod viene riavviato, il file rimane!
# (Grazie al PVC)
```

---

## 🔒 Distribuzione Sicura Credenziali

### Opzione 1: Email (Raccomandata)

```bash
# Per ogni studente, invia email con:
# - Allegato: student1.txt (criptato con password)
# - Corpo: Istruzioni per decifrare

# Esempio script invio (richiede mailx o simile)
for i in {1..6}; do
  # Cripta file
  gpg -c credentials/student${i}.txt
  
  # Invia email
  echo "Credenziali lab Linux in allegato" | \
    mail -s "Linux Lab - Credenziali" \
         -a credentials/student${i}.txt.gpg \
         student${i}@university.edu
done
```

### Opzione 2: Stampa e Consegna

```bash
# Stampa ogni file individualmente
for i in {1..6}; do
  lp credentials/student${i}.txt
done

# Consegna in busta chiusa
```

### Opzione 3: Password Manager Condiviso

```bash
# Usa tool come Bitwarden, 1Password, LastPass
# Crea folder condiviso per il corso
# Importa credenziali come secure notes
```

---

## 📊 Verifica Rapida

### Check 1: PVC Esistono e sono Bound

```bash
kubectl get pvc -A | grep student
```

✅ Output atteso:
```
student1   student-workspace-pvc   Bound    pvc-abc123   5Gi   RWO   standard
student2   student-workspace-pvc   Bound    pvc-def456   5Gi   RWO   standard
...
```

### Check 2: Pod Running

```bash
kubectl get pods -A | grep student
```

✅ Output atteso (per ogni studente):
```
student1   client-xxx    2/2   Running   0   2m
student1   server1-xxx   1/1   Running   0   2m
student1   server2-xxx   1/1   Running   0   2m
```

### Check 3: Credenziali Create

```bash
ls -lh credentials/
```

✅ Output atteso:
```
ALL_CREDENTIALS.txt
student1.txt
student2.txt
...
student6.txt
```

### Check 4: Test Accesso

```bash
# Prova login studente 1
curl -I https://student1.lab.example.com
```

✅ Output atteso:
```
HTTP/2 200
...
```

### Check 5: Test SSH

```bash
./scripts/test-ssh-setup.sh 1
```

✅ Output atteso:
```
==========================================
  TEST SSH SETUP - Student 1
==========================================

Testing: Namespace student1... ✓ OK
Testing: SSH keys secret... ✓ OK
Testing: Client pod running... ✓ OK
...
Client → Server1: ✓ Connection successful
Client → Server2: ✓ Connection successful
...
✓ All tests passed!
```

---

## 🧪 Test Persistenza Dati

### Scenario: Verifica che i dati NON si perdano

```bash
# 1. Entra nel pod client
kubectl exec -it -n student1 deployment/client -c linux -- bash

# 2. Crea file nella workspace
echo "Test persistenza $(date)" > /home/student/workspace/test-persist.txt
cat /home/student/workspace/test-persist.txt
exit

# 3. Elimina il pod (simula crash)
kubectl delete pod -n student1 -l app=client

# 4. Aspetta che riprenda
kubectl wait --for=condition=ready pod -l app=client -n student1 --timeout=120s

# 5. Verifica file ancora presente
kubectl exec -it -n student1 deployment/client -c linux -- \
  cat /home/student/workspace/test-persist.txt

# ✅ Se vedi il contenuto → PERSISTENZA OK!
```

---

## 🔄 Scenari Comuni

### Scenario 1: Aggiungere Altri Studenti

```bash
# Modifica variabile
export NUM_STUDENTS="10"

# Re-run deploy (salta studenti esistenti)
./scripts/deploy-lab.sh
```

### Scenario 2: Reset Singolo Studente

```bash
# Cancella solo i pod (mantiene PVC)
kubectl delete pod -n student2 -l app=client
kubectl delete pod -n student2 -l app=server1
kubectl delete pod -n student2 -l app=server2

# I pod ripartono automaticamente con dati intatti
```

### Scenario 3: Cambio Password

```bash
# Genera nuova password
NEW_PASS=$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-12)

# Aggiorna secret
kubectl create secret generic student-credentials \
  --from-literal=code-server-password="newCodePass123" \
  --from-literal=student-password="${NEW_PASS}" \
  -n student3 --dry-run=client -o yaml | kubectl apply -f -

# Riavvia pod
kubectl rollout restart deployment/client -n student3
kubectl rollout restart deployment/server1 -n student3
kubectl rollout restart deployment/server2 -n student3

# Comunica nuova password allo studente
echo "Student 3 - New Password: ${NEW_PASS}"
```

### Scenario 4: Backup Prima di Manutenzione

```bash
# Backup automatico di tutti i workspace
./scripts/cleanup-lab.sh
# → Rispondere "y" quando chiede se fare backup
# → Rispondere "N" quando chiede se cancellare

# I backup saranno in ./pvc-backups-YYYYMMDD-HHMMSS/
```

---

## 🛑 Cleanup Completo

Quando il corso è finito:

```bash
./scripts/cleanup-lab.sh
```

Lo script chiederà:
1. **Backup PVC?** → Consigliato rispondere `y`
2. **Conferma cancellazione** → Digitare `DELETE`
3. **Cancellare credenziali?** → Scegli in base alle policy

---

## 💡 Tips & Tricks

### Visualizza Password di uno Studente

```bash
# Password Linux
kubectl get secret student-credentials -n student1 \
  -o jsonpath='{.data.student-password}' | base64 -d
echo

# Password Code-Server
kubectl get secret student-credentials -n student1 \
  -o jsonpath='{.data.code-server-password}' | base64 -d
echo
```

### Accedi Direttamente al Container

```bash
# Shell nel container Linux del client
kubectl exec -it -n student1 deployment/client -c linux -- /bin/bash

# Shell nel container Code-Server
kubectl exec -it -n student1 deployment/client -c code-server -- /bin/sh
```

### Logs in Real-Time

```bash
# Segui i log del client
kubectl logs -n student1 -l app=client -c linux -f

# Logs di tutti i pod student1
kubectl logs -n student1 --all-containers --prefix -f
```

### Verifica Spazio PVC

```bash
# Necessita metric-server installato
kubectl exec -n student1 deployment/client -c linux -- df -h /home/student/workspace
```

---

## ❓ FAQ Rapide

**Q: Le password sono sicure?**  
A: Sì, generate con `openssl` (12-16 caratteri casuali alfanumerici).

**Q: Posso usare password personalizzate?**  
A: Sì, modifica lo script prima di eseguirlo o aggiorna i secret manualmente dopo.

**Q: I dati persistono per sempre?**  
A: Finché non cancelli i PVC. Usa `cleanup-lab.sh` con backup per conservarli.

**Q: Posso usare un registry privato?**  
A: Sì, imposta `REGISTRY` e assicurati che il cluster abbia ImagePullSecret configurato.

**Q: Funziona su minikube/k3s/kind?**  
A: Sì! Assicurati solo che abbiano uno StorageClass (solitamente `standard` o `local-path`).

---

## 📞 Supporto

Se qualcosa non funziona:

1. Controlla i log: `kubectl logs -n student1 -l app=client`
2. Verifica eventi: `kubectl get events -n student1 --sort-by='.lastTimestamp'`
3. Test SSH: `./scripts/test-ssh-setup.sh 1`
4. Consulta `IMPLEMENTATION_SUMMARY.md` sezione Troubleshooting

---

**Ready to go!** 🚀

Buon lab!