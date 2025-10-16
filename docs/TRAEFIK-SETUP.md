# Guida Traefik per Student Lab

## 🎯 Architettura

```
Internet
   ↓
Traefik Ingress (HTTPS/TLS)
   ↓ (middleware: headers, rate-limit, auth)
Code-Server Container :8080
   ↓ (Web IDE + Terminal)
Linux Container :22
   ↓ (SSH)
Server1 & Server2
```

## 📦 Componenti

### 1. Code-Server
- **Ruolo**: Web IDE + Terminale nel browser
- **Porta**: 8080
- **Autenticazione**: Password integrata
- **Features**: VS Code, terminal, file editor
- **WebSocket**: Per terminale interattivo

### 2. Traefik
- **Ruolo**: Ingress controller & reverse proxy
- **Gestisce**: HTTPS, routing, middleware, metrics
- **Porta**: 80 (HTTP), 443 (HTTPS)

## 🚀 Deploy Rapido

```bash
# 1. Deploy lab con Traefik
./scripts/deploy-traefik-lab.sh

# 2. Verifica
kubectl get ingressroute -A
kubectl get middleware -n default

# 3. Test accesso
curl -I https://student1.lab.example.com
```

## 🔧 Configurazione Code-Server

### Password Code-Server

**Opzione 1: Secret (raccomandato)**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: code-server-password
  namespace: student1
stringData:
  password: "$(openssl rand -base64 16)"
```

**Opzione 2: Variabile ambiente**
```yaml
env:
- name: PASSWORD
  value: "student1pass"
```

**Opzione 3: Disabilita password (⚠️ non raccomandato)**
```yaml
env:
- name: PASSWORD
  value: ""
args:
- --auth
- none
```

### Estensioni VS Code

Installare estensioni in Code-Server:

```bash
# Da terminale Code-Server
code-server --install-extension ms-python.python
code-server --install-extension dbaeumer.vscode-eslint

# O via UI Code-Server
Extensions → Search → Install
```

### Configurazione Workspace

```yaml
volumeMounts:
- name: workspace
  mountPath: /home/coder/project
- name: settings
  mountPath: /home/coder/.local/share/code-server
```

## 🔒 Sicurezza con Traefik

### Livelli di Sicurezza

**Livello 1: Solo Code-Server Password**
```yaml
# Nessun middleware auth aggiuntivo
# Studenti usano password Code-Server
```

**Livello 2: Code-Server + Basic Auth**
```yaml
middlewares:
- name: basic-auth  # Traefik Basic Auth
- name: security-headers
```

**Livello 3: Code-Server + OAuth2**
```yaml
middlewares:
- name: oauth2-proxy  # SSO con Google/GitHub
- name: security-headers
```

### Middleware Raccomandati

```yaml
# Chain completa sicurezza
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: student-lab-secure
spec:
  chain:
    middlewares:
    - name: https-redirect
    - name: rate-limit
    - name: security-headers
    - name: compress
    # - name: ip-whitelist  # opzionale
    # - name: basic-auth    # opzionale
```

## 📊 Monitoring Traefik

### Metriche Disponibili

```promql
# Requests per studente
sum(rate(traefik_service_requests_total{service=~"student.*-client"}[5m])) by (service)

# Latency P99
histogram_quantile(0.99, 
  sum(rate(traefik_service_request_duration_seconds_bucket[5m])) by (service, le)
)

# Errori 5xx
sum(rate(traefik_service_requests_total{code=~"5.."}[5m])) by (service)

# Bandwidth
sum(rate(traefik_service_response_bytes_total[5m])) by (service)
```

### Dashboard Grafana

Importa dashboard ufficiale Traefik:
- **ID: 11462** - Traefik 2 Dashboard

Oppure usa quello custom in `kubernetes/10-grafana-dashboard.yaml`

## 🐛 Troubleshooting

### Code-Server non risponde

```bash
# Check pod
kubectl get pods -n student1 -l app=client

# Check logs
kubectl logs -n student1 -l app=client -c code-server

# Test interno
kubectl run test --rm -it --image=busybox -- \
  wget -O- http://client.student1:8080
```

### WebSocket non funziona

```yaml
# Verifica Service sessionAffinity
spec:
  sessionAffinity: ClientIP
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 10800

# Verifica Traefik sticky sessions
annotations:
  traefik.ingress.kubernetes.io/service.sticky.cookie: "true"
```

### Certificato SSL invalido

```bash
# Check certificate
kubectl get certificate -A

# Check secret
kubectl get secret lab-wildcard-tls -n default -o yaml

# Rigenera
kubectl delete certificate lab-wildcard-cert
kubectl apply -f kubernetes/16-traefik-tls.yaml
```

### Rate limit troppo restrittivo

```yaml
# Aumenta limite
spec:
  rateLimit:
    average: 200  # da 100 a 200
    burst: 100    # da 50 a 100
```

### Traefik non instrada correttamente

```bash
# Check IngressRoute
kubectl get ingressroute -n student1

# Describe per vedere status
kubectl describe ingressroute student1-https -n student1

# Check Traefik logs
kubectl logs -n traefik deployment/traefik -f

# Debug mode
kubectl set env -n traefik deployment/traefik LOG_LEVEL=DEBUG
```

## 🔍 Debug Code-Server

### Accesso Diretto al Container

```bash
# Shell in code-server container
kubectl exec -it -n student1 <pod> -c code-server -- /bin/sh

# Check configurazione
cat /home/coder/.config/code-server/config.yaml

# Check logs
tail -f /home/coder/.local/share/code-server/coder-logs/*.log
```

### Terminale non funziona

```bash
# Verifica permessi
ls -la /home/coder/.local/share/code-server

# Verifica processo
ps aux | grep code-server

# Test terminale
curl http://localhost:8080/vscode/terminal
```

### Performance Code-Server

```yaml
# Aumenta risorse
resources:
  limits:
    memory: "2Gi"  # da 1Gi a 2Gi
    cpu: "2000m"   # da 1000m a 2000m
```

## ✅ Checklist Deploy

- [ ] Traefik installato e funzionante
- [ ] Cert-manager configurato
- [ ] Wildcard certificate creato
- [ ] Middleware security-headers attivo
- [ ] Rate limiting configurato
- [ ] IngressRoute per ogni studente
- [ ] Code-Server password configurate
- [ ] Monitoring Prometheus attivo
- [ ] Dashboard Grafana importata
- [ ] Test accesso da browser
- [ ] WebSocket terminale funzionante
- [ ] SSH tra container funzionante

## 📚 Risorse

- Traefik Docs: https://doc.traefik.io/traefik/
- Code-Server Docs: https://coder.com/docs/code-server
- Traefik CRDs: https://doc.traefik.io/traefik/routing/providers/kubernetes-crd/

## 🎓 FAQ

**Q: Posso usare Traefik e NGINX insieme?**
A: Sì, ma non raccomandato. Scegli uno solo per evitare conflitti.

**Q: Code-Server supporta più terminali?**
A: Sì, Code-Server supporta tab multipli di terminale.

**Q: Posso personalizzare Code-Server?**
A: Sì, puoi montare configurazioni custom e installare estensioni.

**Q: WebSocket funziona attraverso Traefik?**
A: Sì, Traefik supporta WebSocket nativamente, assicurati di usare sessionAffinity.

**Q: Posso disabilitare la password di Code-Server?**
A: Tecnicamente sì (`--auth none`), ma NON è raccomandato senza altro layer di auth.

**Q: Code-Server è sicuro per produzione?**
A: Sì, con HTTPS e password strong. Meglio ancora con Basic Auth o OAuth2 aggiuntivo.