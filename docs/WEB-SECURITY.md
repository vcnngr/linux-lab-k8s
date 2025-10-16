# Sicurezza Accesso Web - Student Lab

## 🔒 Panoramica

Il lab è accessibile via web tramite Code-Server. Questa guida spiega come proteggere l'accesso.

---

## Opzioni di Autenticazione

### 1. OAuth2 Proxy (⭐ RACCOMANDATO per produzione)

**Pro:**
- ✅ Single Sign-On (SSO)
- ✅ Integrazione Google/GitHub/Azure AD
- ✅ MFA support
- ✅ Audit logging completo
- ✅ Session management

**Contro:**
- ⚠️ Setup più complesso
- ⚠️ Richiede provider OAuth2

**Setup:**
```bash
# 1. Crea OAuth2 app (Google/GitHub/etc)
# 2. Configura secret
kubectl apply -f kubernetes/11-oauth2-authentication.yaml

# 3. Aggiorna domain e credentials
kubectl edit secret oauth2-proxy-secret -n auth-system
```

**Provider Setup:**

**Google OAuth:**
1. Vai a https://console.cloud.google.com
2. Crea nuovo progetto
3. APIs & Services → Credentials → Create OAuth 2.0 Client ID
4. Authorized redirect URI: `https://auth.lab.example.com/oauth2/callback`
5. Copia Client ID e Secret

**GitHub OAuth:**
1. Settings → Developer settings → OAuth Apps
2. New OAuth App
3. Callback URL: `https://auth.lab.example.com/oauth2/callback`
4. Copia Client ID e Secret

---

### 2. Basic Authentication (⭐ RACCOMANDATO per lab interni)

**Pro:**
- ✅ Setup semplicissimo
- ✅ No dipendenze esterne
- ✅ Funziona ovunque

**Contro:**
- ⚠️ Credenziali in chiaro (HTTPS necessario)
- ⚠️ No SSO
- ⚠️ Password management manuale

**Setup:**
```bash
# Genera credenziali
./scripts/generate-web-credentials.sh

# Applica ingress con auth
kubectl apply -f kubernetes/12-basic-auth.yaml

# Distribuisci credenziali agli studenti
cat credentials/ALL_CREDENTIALS.txt
```

---

### 3. Nessuna Autenticazione (⚠️ SOLO per lab privati)

Se il cluster è già dietro VPN o rete privata:

```yaml
# Ingress senza auth
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: student-labs-open
spec:
  # No auth annotations
  rules:
  - host: student1.lab.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: client
            port:
              number: 8080
```

---

## 🛡️ Protezioni Aggiuntive

### Rate Limiting

Protegge da brute force e DDoS:

```yaml
nginx.ingress.kubernetes.io/limit-rps: "10"
nginx.ingress.kubernetes.io/limit-connections: "5"
```

### IP Whitelisting

Limita accesso a IP specifici:

```yaml
nginx.ingress.kubernetes.io/whitelist-source-range: "10.0.0.0/8,192.168.1.0/24"
```

### WAF (Web Application Firewall)

ModSecurity per bloccare attacchi:

```bash
# Abilita ModSecurity
kubectl label namespace ingress-nginx modsecurity=enabled
kubectl apply -f kubernetes/13-security-web-access.yaml
```

---

## 🔐 HTTPS/TLS

### Con Cert-Manager (automatico)

```bash
# Installa cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Crea ClusterIssuer
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

# I certificati saranno generati automaticamente
```

### Con certificati custom

```bash
# Crea secret TLS
kubectl create secret tls lab-tls \
  --cert=path/to/cert.crt \
  --key=path/to/cert.key \
  -n student1
```

---

## 📊 Monitoring Accessi

### Log Accessi

```bash
# Visualizza log nginx ingress
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller -f

# Filtra per student1
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller | grep student1

# Export log
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller > access.log
```

### Prometheus Metrics

Query utili:

```promql
# Richieste per studente
sum(rate(nginx_ingress_controller_requests[5m])) by (namespace, host)

# Errori 4xx/5xx
sum(rate(nginx_ingress_controller_requests{status=~"[45].."}[5m])) by (host)

# Bandwidth
sum(rate(nginx_ingress_controller_request_size_sum[5m])) by (host)
```

### Grafana Dashboard

Importa dashboard ID: **9614** (NGINX Ingress Controller)

---

## 🚨 Alert Configurati

Gli alert Prometheus ti notificano per:

- ✅ Troppe richieste fallite (possibile attacco)
- ✅ Rate limit exceeded
- ✅ Certificato in scadenza
- ✅ Pod non raggiungibile
- ✅ Alta latenza

---

## 🔍 Troubleshooting

### "Connection refused"

```bash
# Verifica pod
kubectl get pods -n student1

# Verifica service
kubectl get svc -n student1

# Test interno
kubectl run test --rm -it --image=busybox -- wget -O- http://client.student1:8080
```

### "SSL certificate problem"

```bash
# Verifica certificato
kubectl get certificate -n student1
kubectl describe certificate student1-tls -n student1

# Rigenera certificato
kubectl delete secret student1-tls -n student1
# Cert-manager lo ricreerà automaticamente
```

### "Too many requests"

Rate limit attivo. Aumenta limiti:

```yaml
nginx.ingress.kubernetes.io/limit-rps: "20"  # aumenta da 10 a 20
```

### "403 Forbidden"

Check autenticazione:

```bash
# Verifica secret auth
kubectl get secret basic-auth -n student1
kubectl get secret basic-auth -n student1 -o yaml

# Test manualmente
curl -u student1:password https://student1.lab.example.com
```

---

## ✅ Checklist Sicurezza

Prima di andare in produzione:

- [ ] HTTPS abilitato con certificati validi
- [ ] Autenticazione configurata (OAuth2 o Basic Auth)
- [ ] Rate limiting attivo
- [ ] Security headers configurati
- [ ] WAF abilitato (opzionale ma raccomandato)
- [ ] IP whitelist se necessario
- [ ] Monitoring e alerting attivi
- [ ] Backup credenziali fatto
- [ ] Documentazione distribuita agli studenti
- [ ] Test di penetration fatto
- [ ] Logs retention configurato

---

## 📧 Distribuzione Credenziali Studenti

### Email Template

```
Subject: Linux Lab - Credenziali Accesso

Ciao Student,

Ecco le tue credenziali per accedere al laboratorio Linux:

URL: https://student1.lab.example.com
Username: student1
Password: [GENERATA_AUTOMATICAMENTE]

IMPORTANTE:
- Cambia la password al primo accesso (se configurato)
- Non condividere le credenziali
- Usa sempre HTTPS
- In caso di problemi contatta: lab-admin@example.com

Buon lavoro!
```

### Alternative Sicure

1. **Portal di self-service** (integra con LDAP/AD)
2. **Password manager** aziendale
3. **One-time links** con scadenza
4. **QR code** con credenziali temporanee

---

## 🎯 Best Practices

1. **Usa OAuth2** per ambienti multi-utente
2. **Ruota password** regolarmente
3. **Abilita MFA** quando possibile
4. **Monitora accessi** via Grafana
5. **Limita rate** per prevenire abusi
6. **Usa HTTPS** SEMPRE
7. **Backup secrets** regolarmente
8. **Audit logs** per compliance
9. **Test sicurezza** periodici
10. **Documenta tutto** per gli studenti

---

## 📚 Risorse

- OAuth2 Proxy: https://oauth2-proxy.github.io/oauth2-proxy/
- NGINX Ingress: https://kubernetes.github.io/ingress-nginx/
- Cert-Manager: https://cert-manager.io/
- ModSecurity: https://github.com/SpiderLabs/ModSecurity