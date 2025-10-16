#!/bin/bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

DOCKERFILE=${1:-Dockerfile-ubuntu}
IMAGE_NAME="linux-lab-test"
CONTAINER_NAME="lab-test-$$"

echo -e "${YELLOW}Testing $DOCKERFILE...${NC}"

# Build
echo -e "${YELLOW}1. Building image...${NC}"
docker build -t $IMAGE_NAME:latest -f docker/$DOCKERFILE docker/

# Run
echo -e "${YELLOW}2. Starting container...${NC}"
docker run -d \
  --name $CONTAINER_NAME \
  --privileged \
  --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  -p 8080:8080 \
  -p 9090:9090 \
  -p 2222:22 \
  $IMAGE_NAME:latest

# Wait for systemd
echo -e "${YELLOW}3. Waiting for systemd to initialize...${NC}"
sleep 10

# Tests
echo -e "${YELLOW}4. Running tests...${NC}"

# Test 1: Container is running
if docker ps | grep -q $CONTAINER_NAME; then
    echo -e "${GREEN}✓ Container is running${NC}"
else
    echo -e "${RED}✗ Container failed to start${NC}"
    exit 1
fi

# Test 2: Systemd is working
if docker exec $CONTAINER_NAME systemctl is-system-running --wait 2>/dev/null; then
    echo -e "${GREEN}✓ Systemd is working${NC}"
else
    echo -e "${YELLOW}⚠ Systemd still initializing (might be OK)${NC}"
fi

# Test 3: SSH service
if docker exec $CONTAINER_NAME systemctl is-active ssh 2>/dev/null || \
   docker exec $CONTAINER_NAME systemctl is-active sshd 2>/dev/null; then
    echo -e "${GREEN}✓ SSH service is active${NC}"
else
    echo -e "${RED}✗ SSH service is not active${NC}"
fi

# Test 4: Student user exists
if docker exec $CONTAINER_NAME id student &>/dev/null; then
    echo -e "${GREEN}✓ Student user exists${NC}"
else
    echo -e "${RED}✗ Student user does not exist${NC}"
fi

# Test 5: Sudo works
if docker exec $CONTAINER_NAME sudo -u student sudo whoami | grep -q root; then
    echo -e "${GREEN}✓ Sudo works for student${NC}"
else
    echo -e "${RED}✗ Sudo does not work${NC}"
fi

# Test 6: Code-Server (if present)
if docker exec $CONTAINER_NAME systemctl is-active code-server@student 2>/dev/null; then
    echo -e "${GREEN}✓ Code-Server is active${NC}"
else
    echo -e "${YELLOW}⚠ Code-Server not active (might need manual start)${NC}"
fi

# Test 7: Cockpit (if present)
if docker exec $CONTAINER_NAME systemctl is-active cockpit.socket 2>/dev/null; then
    echo -e "${GREEN}✓ Cockpit is active${NC}"
else
    echo -e "${YELLOW}⚠ Cockpit not installed/active${NC}"
fi

# Test 8: Port 8080 responds
sleep 5
if curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 | grep -q "200\|302"; then
    echo -e "${GREEN}✓ Port 8080 (Code-Server) responds${NC}"
else
    echo -e "${YELLOW}⚠ Port 8080 not responding yet${NC}"
fi

# Test 9: Port 9090 responds
if curl -k -s -o /dev/null -w "%{http_code}" https://localhost:9090 | grep -q "200\|302\|401"; then
    echo -e "${GREEN}✓ Port 9090 (Cockpit) responds${NC}"
else
    echo -e "${YELLOW}⚠ Port 9090 not responding (Cockpit might not be installed)${NC}"
fi

echo ""
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Tests completed!${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo "Access URLs:"
echo "  - Code-Server: http://localhost:8080"
echo "  - Cockpit: https://localhost:9090"
echo "  - SSH: ssh -p 2222 student@localhost"
echo ""
echo "Enter container: docker exec -it $CONTAINER_NAME bash"
echo ""
echo "Cleanup: docker stop $CONTAINER_NAME && docker rm $CONTAINER_NAME"