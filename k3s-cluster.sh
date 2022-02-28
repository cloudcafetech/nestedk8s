#!/usr/bin/env bash
# K3S Cluster Creation on Linux (Ubuntu)

MASTERIP=`kubectl get vmi | grep k3s-master | grep -v NAME | awk '{print $4}'`
NODEIP=`kubectl get vmi | grep k3s-worker | grep -v NAME | awk '{print $4}'`
MASTERNAME=k3s-master
USER=root

# Master Setup
ssh -o StrictHostKeyChecking=no $USER@$MASTERIP "curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=v1.20 sh -"
ssh -o StrictHostKeyChecking=no $USER@$MASTERIP "systemctl status k3s"
ssh -o StrictHostKeyChecking=no $USER@$MASTERIP "mkdir -p /root/.kube"
ssh -o StrictHostKeyChecking=no $USER@$MASTERIP "ln -s /etc/rancher/k3s/k3s.yaml /root/.kube/config"
ssh -o StrictHostKeyChecking=no $USER@$MASTERIP "chmod 600 /root/.kube/config"
ssh -o StrictHostKeyChecking=no $USER@$MASTERIP "echo 'alias oc=/usr/bin/kubectl' >> /root/.bash_profile"
ssh -o StrictHostKeyChecking=no $USER@$MASTERIP "wget -q https://raw.githubusercontent.com/cloudcafetech/nestedk8s/main/kube-ingress.yaml"
scp -o StrictHostKeyChecking=no employee.yaml $USER@$MASTERIP:/root/employee.yaml
scp -o StrictHostKeyChecking=no wordpress.yaml $USER@$MASTERIP:/root/wordpress.yaml

# Node Setup
TOKEN=`ssh -o StrictHostKeyChecking=no $USER@$MASTERIP "cat /var/lib/rancher/k3s/server/node-token"`
ssh -o StrictHostKeyChecking=no $USER@$NODEIP "curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=v1.20 K3S_URL=https://$MASTERIP:6443 K3S_TOKEN=$TOKEN sh -"
ssh -o StrictHostKeyChecking=no $USER@$NODEIP "systemctl status k3s-agent"
