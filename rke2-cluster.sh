#!/usr/bin/env bash
# RKE2 Cluster Creation on Linux (Ubuntu)

MASTERIP=`kubectl get vmi | grep k8s-master | grep -v NAME | awk '{print $4}'`
NODEIP=`kubectl get vmi | grep k8s-worker | grep -v NAME | awk '{print $4}'`
MASTERNAME=k8s-master
USER=root

# Master Setup
cat << EOF > config.yaml
token: pkls-secret
write-kubeconfig-mode: "0644"
node-label:
- "region=master"
tls-san:
  - "$MASTERNAME"
  - "$MASTERIP"
# Disable Nginx Ingress
disable: rke2-ingress-nginx
EOF

ssh -o StrictHostKeyChecking=no $USER@$MASTERIP "mkdir -p /etc/rancher/rke2"
scp -o StrictHostKeyChecking=no config.yaml $USER@$MASTERIP:/etc/rancher/rke2/config.yaml
ssh -o StrictHostKeyChecking=no $USER@$MASTERIP "curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL=v1.20 sh -"
ssh -o StrictHostKeyChecking=no $USER@$MASTERIP "systemctl enable rke2-server"
ssh -o StrictHostKeyChecking=no $USER@$MASTERIP "systemctl start rke2-server"
ssh -o StrictHostKeyChecking=no $USER@$MASTERIP "systemctl status rke2-server"
ssh -o StrictHostKeyChecking=no $USER@$MASTERIP "mkdir -p /root/.kube"
ssh -o StrictHostKeyChecking=no $USER@$MASTERIP "ln -s /etc/rancher/rke2/rke2.yaml /root/.kube/config"
ssh -o StrictHostKeyChecking=no $USER@$MASTERIP "chmod 600 /root/.kube/config"
ssh -o StrictHostKeyChecking=no $USER@$MASTERIP "echo 'export PATH=/var/lib/rancher/rke2/bin:$PATH' >> /root/.bash_profile"
ssh -o StrictHostKeyChecking=no $USER@$MASTERIP "echo 'alias oc=/var/lib/rancher/rke2/bin/kubectl' >> /root/.bash_profile"
ssh -o StrictHostKeyChecking=no $USER@$MASTERIP "ln -s /var/lib/rancher/rke2/agent/etc/crictl.yaml /etc/crictl.yaml"
ssh -o StrictHostKeyChecking=no $USER@$MASTERIP "wget -q https://raw.githubusercontent.com/cloudcafetech/nestedk8s/main/kube-ingress.yaml"

# Node Setup
cat << EOF > confign.yaml
server: https://$MASTERIP:9345
token: pkls-secret
node-label:
- "region=worker"
EOF

ssh -o StrictHostKeyChecking=no $USER@$NODEIP "mkdir -p /etc/rancher/rke2"
scp -o StrictHostKeyChecking=no configb.yaml $USER@$NODEIP:/etc/rancher/rke2/config.yaml
ssh -o StrictHostKeyChecking=no $USER@$NODEIP "curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL=v1.20 sh -"
ssh -o StrictHostKeyChecking=no $USER@$NODEIP "systemctl enable rke2-agent"
ssh -o StrictHostKeyChecking=no $USER@$NODEIP "systemctl start rke2-agent"
ssh -o StrictHostKeyChecking=no $USER@$NODEIP "systemctl status rke2-agent"
ssh -o StrictHostKeyChecking=no $USER@$NODEIP "ln -s /var/lib/rancher/rke2/agent/etc/crictl.yaml /etc/crictl.yaml"
