#!/bin/bash
# Script per generare chiavi SSH localmente e creare secrets K8s

set -e

NUM_STUDENTS=6
KEYS_DIR="./ssh-keys"

echo "=========================================="
echo "  GENERAZIONE CHIAVI SSH STUDENTI"
echo "=========================================="

# Crea directory per le chiavi
mkdir -p $KEYS_DIR

for i in $(seq 1 $NUM_STUDENTS); do
    STUDENT_KEY_DIR="${KEYS_DIR}/student${i}"
    
    echo ""
    echo "Generando chiavi per student${i}..."
    
    # Crea directory studente
    mkdir -p $STUDENT_KEY_DIR
    
    # Genera coppia di chiavi SSH
    ssh-keygen -t rsa -b 4096 \
               -f ${STUDENT_KEY_DIR}/id_rsa \
               -N "" \
               -C "student${i}@lab" \
               -q
    
    # Crea known_hosts vuoto
    touch ${STUDENT_KEY_DIR}/known_hosts
    
    # Crea secret Kubernetes
    kubectl create secret generic ssh-keys \
        --from-file=id_rsa=${STUDENT_KEY_DIR}/id_rsa \
        --from-file=id_rsa.pub=${STUDENT_KEY_DIR}/id_rsa.pub \
        --from-file=known_hosts=${STUDENT_KEY_DIR}/known_hosts \
        --namespace=student${i} \
        --dry-run=client -o yaml | kubectl apply -f -
    
    echo "✓ Chiavi generate e secret creato per student${i}"
    
    # Mostra fingerprint per verifica
    ssh-keygen -lf ${STUDENT_KEY_DIR}/id_rsa.pub
done

echo ""
echo "=========================================="
echo "  COMPLETATO!"
echo "=========================================="
echo ""
echo "Chiavi salvate in: $KEYS_DIR/"
echo "Secrets creati in namespace student1-${NUM_STUDENTS}"
echo ""
echo "Per visualizzare i secret:"
echo "  kubectl get secrets -n student1"
echo ""
echo "Per verificare contenuto:"
echo "  kubectl get secret ssh-keys -n student1 -o yaml"
echo ""