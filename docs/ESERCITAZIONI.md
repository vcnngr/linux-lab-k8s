# Esercitazioni Lab Linux su Kubernetes

## Setup Studente

1. Accedi al tuo URL: `https://studentX.lab.tuodominio.com`
2. Inserisci password: `studentXpass`
3. Vedrai Code-Server con un terminale integrato
4. Hai accesso a 3 macchine:
   - **client** (quella su cui lavori)
   - **server1** (accessibile via SSH)
   - **server2** (accessibile via SSH)

---

## Esercitazione 1: Comandi Base Linux

**Obiettivo:** Familiarizzare con filesystem e comandi base

### Task:

1. **Esplora il filesystem**
   ```bash
   pwd
   ls -la
   cd /etc
   ls
   cd ~
   ```

2. **Crea una struttura di directory**
   ```bash
   mkdir -p ~/progetti/esercizio1/{docs,scripts,data}
   tree ~/progetti
   ```

3. **Crea e modifica file**
   ```bash
   echo "Questo è il mio primo file" > ~/progetti/esercizio1/README.txt
   nano ~/progetti/esercizio1/docs/note.txt
   cat ~/progetti/esercizio1/README.txt
   ```

4. **Gestisci permessi**
   ```bash
   chmod 755 ~/progetti/esercizio1/scripts
   chmod 644 ~/progetti/esercizio1/README.txt
   ls -la ~/progetti/esercizio1/
   ```

5. **Cerca file**
   ```bash
   find ~ -name "*.txt"
   grep "primo" ~/progetti/esercizio1/README.txt
   ```

**Verifica:** Il docente controllerà la struttura creata.

---

## Esercitazione 2: Connessioni SSH

**Obiettivo:** Imparare a connettersi e gestire macchine remote via SSH

### Task:

1. **Prima connessione a server1**
   ```bash
   # Dal client
   ssh student@server1
   # Password: student123
   
   # Una volta connesso
   hostname
   whoami
   exit
   ```

2. **Configura SSH key-based authentication**
   ```bash
   # Genera chiave SSH sul client
   ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ""
   
   # Copia la chiave su server1
   ssh-copy-id student@server1
   
   # Ora connettiti senza password
   ssh server1
   exit
   ```

3. **Ripeti per server2**
   ```bash
   ssh-copy-id student@server2
   ssh server2 "echo 'Connessione riuscita da $(hostname)'"
   ```

4. **Trasferisci file con SCP**
   ```bash
   # Crea file locale
   echo "File da trasferire" > ~/test.txt
   
   # Copia su server1
   scp ~/test.txt student@server1:/home/student/
   
   # Verifica
   ssh server1 "cat ~/test.txt"
   ```

5. **Usa rsync per sincronizzazione**
   ```bash
   # Crea directory con file
   mkdir ~/sync_test
   echo "File 1" > ~/sync_test/file1.txt
   echo "File 2" > ~/sync_test/file2.txt
   
   # Sincronizza su server1
   rsync -avz ~/sync_test/ student@server1:~/sync_test/
   
   # Verifica
   ssh server1 "ls ~/sync_test/"
   ```

**Challenge:** Connettiti da client a server1, poi da server1 a server2, e copia un file attraverso entrambi.

---

## Esercitazione 3: Gestione Processi

**Obiettivo:** Monitorare e gestire processi Linux

### Task:

1. **Visualizza processi attivi**
   ```bash
   ps aux
   ps aux | grep sshd
   top
   # (premi 'q' per uscire)
   htop
   # (premi F10 per uscire)
   ```

2. **Gestisci processi in background**
   ```bash
   # Avvia processo lungo
   sleep 300 &
   
   # Lista jobs
   jobs
   
   # Porta in foreground
   fg
   # (premi Ctrl+Z per sospendere)
   
   # Riprendi in background
   bg
   
   # Termina
   kill %1
   ```

3. **Monitora risorse di sistema**
   ```bash
   # CPU e memoria
   free -h
   
   # Uso disco
   df -h
   
   # Processi per uso CPU
   ps aux --sort=-%cpu | head -10
   
   # Processi per uso memoria
   ps aux --sort=-%mem | head -10
   ```

4. **Gestisci servizi con systemctl**
   ```bash
   # Status SSH
   sudo systemctl status ssh
   
   # Lista tutti i servizi
   sudo systemctl list-units --type=service
   
   # Restart SSH (attenzione!)
   sudo systemctl restart ssh
   ```

5. **Crea script che gira in background**
   ```bash
   # Crea script
   cat > ~/monitor.sh << 'EOF'
   #!/bin/bash
   while true; do
       date >> ~/monitor.log
       uptime >> ~/monitor.log
       sleep 10
   done
   EOF
   
   chmod +x ~/monitor.sh
   
   # Esegui in background
   nohup ~/monitor.sh &
   
   # Monitora il log
   tail -f ~/monitor.log
   # (Ctrl+C per interrompere tail)
   
   # Termina lo script
   pkill -f monitor.sh
   ```

**Challenge:** Crea uno script che monitora l'uso CPU ogni 5 secondi e scrive un alert nel log se supera 80%.

---

## Esercitazione 4: Networking e Connettività

**Obiettivo:** Comprendere networking di base in Linux

### Task:

1. **Verifica configurazione rete**
   ```bash
   # Interfacce di rete
   ip addr show
   
   # Routing table
   ip route show
   
   # DNS configuration
   cat /etc/resolv.conf
   ```

2. **Test connettività**
   ```bash
   # Ping server1
   ping -c 4 server1
   
   # Ping server2
   ping -c 4 server2
   
   # Test porta SSH
   nc -zv server1 22
   ```

3. **Analizza connessioni attive**
   ```bash
   # Connessioni SSH attive
   sudo netstat -tnp | grep ssh
   
   # O con ss (più moderno)
   ss -tnp | grep ssh
   
   # Porte in ascolto
   sudo netstat -tlnp
   ```

4. **Trasferimento dati con netcat**
   ```bash
   # Su server1, avvia listener
   ssh server1
   nc -l 9999 > received_file.txt
   
   # Dal client, invia file
   echo "Test data transfer" | nc server1 9999
   
   # Verifica su server1
   ssh server1 "cat received_file.txt"
   ```

5. **Port forwarding con SSH**
   ```bash
   # Avvia un server web su server1
   ssh server1 "python3 -m http.server 8000 &"
   
   # Dal client, crea tunnel SSH
   ssh -L 8080:localhost:8000 server1 -N &
   
   # Accedi al server via tunnel
   curl http://localhost:8080
   
   # Termina tunnel
   pkill -f "ssh -L 8080"
   ```

**Challenge:** Crea una catena: client → server1 → server2 usando SSH tunneling.

---

## Esercitazione 5: Script e Automazione

**Obiettivo:** Creare script bash per automazione

### Task:

1. **Script di backup**
   ```bash
   cat > ~/backup.sh << 'EOF'
   #!/bin/bash
   
   BACKUP_DIR=~/backups
   DATE=$(date +%Y%m%d_%H%M%S)
   
   mkdir -p $BACKUP_DIR
   
   tar czf $BACKUP_DIR/backup_$DATE.tar.gz ~/progetti/
   
   echo "Backup creato: backup_$DATE.tar.gz"
   
   # Mantieni solo ultimi 5 backup
   cd $BACKUP_DIR
   ls -t | tail -n +6 | xargs rm -f
   EOF
   
   chmod +x ~/backup.sh
   ./backup.sh
   ```

2. **Script di monitoraggio multi-server**
   ```bash
   cat > ~/check_servers.sh << 'EOF'
   #!/bin/bash
   
   SERVERS="server1 server2"
   
   for server in $SERVERS; do
       echo "=== Checking $server ==="
       ssh $server "hostname && uptime && df -h /"
       echo ""
   done
   EOF
   
   chmod +x ~/check_servers.sh
   ./check_servers.sh
   ```

3. **Cron job per task schedulati**
   ```bash
   # Visualizza crontab
   crontab -l
   
   # Edita crontab
   crontab -e
   
   # Aggiungi job che esegue backup ogni giorno alle 2am
   # 0 2 * * * /home/student/backup.sh >> /home/student/backup.log 2>&1
   
   # Job ogni 5 minuti per test
   # */5 * * * * echo "Test $(date)" >> /home/student/cron_test.log
   ```

4. **Script interattivo**
   ```bash
   cat > ~/deploy.sh << 'EOF'
   #!/bin/bash
   
   echo "=== Deploy Script ==="
   echo ""
   
   read -p "Su quale server vuoi deployare? (server1/server2): " SERVER
   read -p "Nome del file da deployare: " FILE
   
   if [ ! -f "$FILE" ]; then
       echo "Errore: File $FILE non trovato!"
       exit 1
   fi
   
   echo "Deploying $FILE su $SERVER..."
   scp $FILE student@$SERVER:/tmp/
   
   if [ $? -eq 0 ]; then
       echo "Deploy completato con successo!"
   else
       echo "Errore durante il deploy!"
       exit 1
   fi
   EOF
   
   chmod +x ~/deploy.sh
   ```

**Challenge:** Crea uno script che sincronizza automaticamente una directory tra client, server1 e server2.

---

## Esercitazione Finale: Progetto Completo

**Obiettivo:** Integrare tutto ciò che hai imparato

### Progetto: Sistema di Log Centralizzato

1. **Sul client:**
   - Crea script che raccoglie log da server1 e server2
   - Salva log centralizzati con timestamp
   - Schedula raccolta automatica

2. **Su server1 e server2:**
   - Genera log di sistema fake per test
   - Configura permessi SSH appropriati

3. **Requisiti:**
   - Usa SSH key authentication
   - Implementa gestione errori
   - Log rotation automatica
   - Report giornaliero via cron

**Verifica finale:** Il docente verificherà funzionalità completa del sistema.

---

## Tips & Tricks

- Usa `Ctrl+R` per cercare nella history dei comandi
- `!!` ripete ultimo comando
- `sudo !!` ripete ultimo comando con sudo
- `Ctrl+L` pulisce lo schermo (come `clear`)
- `Ctrl+C` termina comando corrente
- `Ctrl+Z` sospende comando (poi `bg` per background)
- `man <comando>` per manuale del comando
- `<comando> --help` per help veloce

## Troubleshooting

**SSH non funziona:**
```bash
# Verifica servizio SSH
sudo systemctl status ssh

# Test connettività
ping server1

# Verifica chiavi
ls -la ~/.ssh/
```

**Permessi negati:**
```bash
# Controlla owner e permessi
ls -la <file>

# Correggi se necessario
sudo chown student:student <file>
chmod 644 <file>
```

**Script non eseguibile:**
```bash
chmod +x script.sh
```