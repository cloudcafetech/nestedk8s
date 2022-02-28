#!/usr/bin/env bash
# Kubernetes host setup script for Linux (Ubuntu)

master=$1
K8S_VER=1.20.15-00
#K8S_VER=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt | cut -d v -f2)
#curl -s https://packages.cloud.google.com/apt/dists/kubernetes-xenial/main/binary-amd64/Packages | grep Version | awk '{print $2}' | more
DATE=$(date +"%d%m%y")
TOKEN=$DATE.1a7dd4cc8d1f4cc5

OS=`egrep '^(NAME)=' /etc/os-release | cut -d "=" -f2 | tr -d '"'`
echo $OS

if [[ ! $master =~ ^( |master|node)$ ]]; then 
 echo "Usage: $0 <master or node>"
 echo "Example: $0 master/node"
 echo "curl -s https://raw.githubusercontent.com/cloudcafetech/nestedk8s/main/host-setup.sh | KUBEMASTER=<MASTER-IP> bash -s master"
 echo "curl -s https://raw.githubusercontent.com/cloudcafetech/nestedk8s/main/host-setup.sh | KUBEMASTER=<MASTER-IP> bash -s node"
 exit
fi

####### Ubuntu Linux Function ##############
ubulinux() {

echo "Update apt repo"
sudo apt update
sudo apt -y install apt-transport-https ca-certificates curl software-properties-common jq git libvirt-clients 
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
echo "Add Docker bionic Repository"
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable"
sudo apt update
apt-cache policy docker-ce
virt-host-validate qemu
echo "Install docker-ce"
sudo apt -y install docker-ce

echo "Install Kubeadm"
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF

cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

sudo sysctl --system

sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update

if [[ "$K8S_VER" == "" ]]; then
 sudo apt-get install -qy kubelet kubeadm kubectl
else
 sudo apt-get install -qy kubelet=$K8S_VER kubectl=$K8S_VER kubeadm=$K8S_VER
fi
sudo apt-mark hold kubelet kubeadm kubectl
sudo swapoff -a
}
#-------------------------------------------------------#

####### CentOS, RHEL Amazon Linux Function ##############
cralinux() {

# Stopping and disabling firewalld by running the commands on all servers:
systemctl stop firewalld
systemctl disable firewalld

# Disable swap. Kubeadm will check to make sure that swap is disabled when we run it, so lets turn swap off and disable it for future reboots.
swapoff -a
sed -i.bak -r 's/(.+ swap .+)/#\1/' /etc/fstab

# Disable SELinux
setenforce 0
sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux

# Add the kubernetes repository to yum so that we can use our package manager to install the latest version of kubernetes. 
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF

# Install some of the tools (including CRI-O, kubeadm & kubelet) we’ll need on our servers.
yum install -y git curl wget bind-utils jq httpd-tools zip unzip nfs-utils go nmap telnet dos2unix java-1.7.0-openjdk qemu-kvm libvirt libvirt-python libguestfs-tools virt-install
virt-host-validate qemu

# Install Docker
if ! command -v docker &> /dev/null;
then
  echo "MISSING REQUIREMENT: docker engine could not be found on your system. Please install docker engine to continue: https://docs.docker.com/get-docker/"
  echo "Trying to Install Docker..."
  if [[ $(uname -a | grep amzn) ]]; then
    echo "Installing Docker for Amazon Linux"
    amazon-linux-extras install docker -y
  else
    curl -s https://releases.rancher.com/install-docker/19.03.sh | sh
  fi    
fi
systemctl start docker; systemctl status docker; systemctl enable docker

cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

sysctl --system
systemctl restart docker

# Installation with specefic version
#yum install -y kubelet-$K8S_VER kubeadm-$K8S_VER kubectl-$K8S_VER kubernetes-cni-0.6.0 --disableexcludes=kubernetes
if [[ "$K8S_VER" == "" ]]; then
 yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
else
 yum install -y kubelet-$K8S_VER kubeadm-$K8S_VER kubectl-$K8S_VER --disableexcludes=kubernetes
fi

# After installing crio and our kubernetes tools, we’ll need to enable the services so that they persist across reboots, and start the services so we can use them right away.
systemctl enable --now kubelet; systemctl start kubelet; systemctl status kubelet

}
#-------------------------------------------------------#

# Excuting Function based on OS
if [[ "$OS" == "Ubuntu" ]]; then
 ubulinux
else
 cralinux
fi

# Setting up Kubernetes Node using Kubeadm
if [[ "$master" == "node" ]]; then
  echo ""
  sudo hostnamectl set-hostname node
  echo "Waiting for Master ($KUBEMASTER) API response .."
  while ! echo break | nc $KUBEMASTER 6443 &> /dev/null; do printf '.'; sleep 2; done
  kubeadm join --discovery-token-unsafe-skip-ca-verification --token=$TOKEN $KUBEMASTER:6443
  exit
fi

# Setting up Kubernetes Master using Kubeadm
sudo hostnamectl set-hostname master
kubeadm init --token=$TOKEN --pod-network-cidr=10.244.0.0/16 --kubernetes-version $(kubeadm version -o short) --ignore-preflight-errors=all | grep -Ei "kubeadm join|discovery-token-ca-cert-hash" 2>&1 | tee kubeadm-output.txt

sudo cp /etc/kubernetes/admin.conf $HOME/
sudo chown $(id -u):$(id -g) $HOME/admin.conf
export KUBECONFIG=$HOME/admin.conf
echo "export KUBECONFIG=$HOME/admin.conf" >> $HOME/.bash_profile
echo "alias oc=/usr/bin/kubectl" >> /root/.bash_profile

kubectl  wait --for=condition=Ready node --all --timeout 60s
alias oc=kubectl
kubectl get no
kubectl taint node master node-role.kubernetes.io/master:NoSchedule-

# Setting krew
curl -fsSLO https://github.com/kubernetes-sigs/krew/releases/latest/download/krew-linux_amd64.tar.gz
tar zxvf krew-linux_amd64.tar.gz
mv krew-linux_amd64 /usr/local/bin/kubectl-krew
rm -rf krew-linux_amd64.tar.gz
echo 'export PATH="${PATH}:${HOME}/.krew/bin"' >> $HOME/.bash_profile
kubectl krew install ns ctx virt
. $HOME/.bash_profile

# Setting Network
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml

# Setting Multus CNI Plugins
wget -q wget https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick-plugin.yml
cat multus-daemonset-thick-plugin.yml | kubectl apply -f -

# Setting Storage
wget -q https://raw.githubusercontent.com/cloudcafetech/nestedk8s/main/hostpath-storage.yaml
kubectl create -f hostpath-storage.yaml
kubectl annotate sc hostpath-storage storageclass.kubernetes.io/is-default-class=true
kubectl wait po `kubectl get po -n hostpath-storage | grep hostpath-storage | awk '{print $1}'` --for=condition=Ready --timeout=2m -n hostpath-storage
kubectl get sc
kubectl get po -A

# Setup Ingress
wget -q https://raw.githubusercontent.com/cloudcafetech/kubesetup/master/kube-ingress.yaml
#sed -i "s/kube-master/$MASTER/g" kube-ingress.yaml
kubectl create ns kube-router
kubectl create -f kube-ingress.yaml
kubectl delete -A ValidatingWebhookConfiguration ingress-nginx-admission

# Setup Helm Chart
wget -q https://raw.githubusercontent.com/cloudcafetech/kubesetup/master/misc/helm-setup.sh
chmod +x ./helm-setup.sh
./helm-setup.sh

# Setup Kubevirt
export KUBEVIRT_VERSION=$(curl -s https://api.github.com/repos/kubevirt/kubevirt/releases/latest | jq -r .tag_name)
echo $KUBEVIRT_VERSION
kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml
kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml
#kubectl -n kubevirt patch kubevirt kubevirt --type=merge --patch '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}'
kubectl get kubevirt -n kubevirt
kubectl get pods -n kubevirt
kubectl wait po `kubectl get po -n kubevirt | grep virt-operator | awk '{print $1}'` --for=condition=Ready --timeout=5m -n kubevirt
sleep 90
kubectl wait po `kubectl get po -n kubevirt | grep virt-api | awk '{print $1}'` --for=condition=Ready --timeout=2m -n kubevirt
sleep 10
kubectl wait po `kubectl get po -n kubevirt | grep virt-controller | awk '{print $1}'` --for=condition=Ready --timeout=2m -n kubevirt
kubectl wait po `kubectl get po -n kubevirt | grep virt-handler | awk '{print $1}'` --for=condition=Ready --timeout=2m -n kubevirt
kubectl get po -n kubevirt

export VERSION=v1.30.0
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/$VERSION/cdi-operator.yaml
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/$VERSION/cdi-cr.yaml
sleep 20
kubectl get po -n cdi
kubectl wait po `kubectl get po -n cdi | grep cdi-operator | awk '{print $1}'` --for=condition=Ready --timeout=5m -n cdi
sleep 10
kubectl wait po `kubectl get po -n cdi | grep cdi-apiserver | awk '{print $1}'` --for=condition=Ready --timeout=2m -n cdi
sleep 10
kubectl wait po `kubectl get po -n cdi | grep cdi-deployment | awk '{print $1}'` --for=condition=Ready --timeout=2m -n cdi
kubectl wait po `kubectl get po -n cdi | grep cdi-uploadproxy | awk '{print $1}'` --for=condition=Ready --timeout=2m -n cdi
kubectl get po -n cdi

# VM Preparation
NODE1=master
NODE2=worker

ssh-keygen -q -t rsa -N '' -f ~/.ssh/id_rsa <<<y >/dev/null 2>&1
PUBKEY=`cat ~/.ssh/id_rsa.pub`
echo $PUBKEY

# PVC & VM yaml generate
for N in $NODE1 $NODE2
do
cat <<EOF > $N-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: "$N-data-volume"
  labels:
    app: containerized-data-importer
  annotations:
    #cdi.kubevirt.io/storage.import.endpoint: "https://cloud.centos.org/centos/8/x86_64/images/CentOS-8-GenericCloud-8.3.2011-20201204.2.x86_64.qcow2"
    cdi.kubevirt.io/storage.import.endpoint: "https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img"
    kubevirt.io/provisionOnNode: node
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 15Gi
EOF

cat <<EOF > $N-eth0.yaml
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: $N-eth0
spec:
  config: >
    {
        "cniVersion": "0.3.1",
        "name": "$N-eth0",
        "plugins": [{
            "type": "bridge",
            "bridge": "eth0",
            "ipam": {}
        }]
    }
EOF

cat <<EOF > vm-$N.yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  labels:
    kubevirt.io/os: linux
  name: k8s-$N
spec:
  running: true
  template:
    metadata:
      labels:
        kubevirt.io/domain: k8s-$N
    spec:
      domain:
        devices:
          disks:
          - disk:
              bus: virtio
            name: disk0
          - cdrom:
              bus: sata
              readonly: true
            name: cloudinitdisk
          interfaces:
          - name: default
            bridge: {}
          - name: eth0
            bridge: {}
        machine:
          type: q35
        resources:
          requests:
            memory: 4096M
            cpu: "2000m"            
      networks:
      - name: default
        pod: {}
      - name: eth0
        multus:
          networkName: default/$N-eth0
      volumes:
      - name: disk0
        persistentVolumeClaim:
          claimName: $N-data-volume
      - cloudInitNoCloud:
          userData: |
            #cloud-config
            hostname: k8s-$N
            user: root
            password: passwd
            chpasswd: { expire: False }
            ssh_pwauth: True
            disable_root: false
            ssh_authorized_keys:
            - ssh-rsa PUBLIC_SSH_KEY
        name: cloudinitdisk
EOF

sed -i "s%ssh-rsa.*%$PUBKEY%" vm-$N.yaml
kubectl create -f $N-eth0.yaml 
done

# Service for VMS

cat <<EOF > vm-svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: k8s-$NODE1
spec:
  externalTrafficPolicy: Cluster
  type: NodePort
  selector:
    kubevirt.io/domain: k8s-$NODE1
  ports:
  - name: ssh
    nodePort: 30022
    port: 27017
    protocol: TCP
    targetPort: 22
  - name: http
    nodePort: 30080
    port: 27018
    protocol: TCP
    targetPort: 80
  - name: https
    nodePort: 30043
    port: 27019
    protocol: TCP
    targetPort: 443
---
apiVersion: v1
kind: Service
metadata:
  name: k8s-$NODE2
spec:
  externalTrafficPolicy: Cluster
  type: NodePort
  selector:
    kubevirt.io/domain: k8s-$NODE2
  ports:
  - name: ssh
    nodePort: 31022
    port: 28017
    protocol: TCP
    targetPort: 22
  - name: http
    nodePort: 31080
    port: 28018
    protocol: TCP
    targetPort: 80
  - name: https
    nodePort: 31043
    port: 28019
    protocol: TCP
    targetPort: 443
EOF

# Download sample application
wget -q https://raw.githubusercontent.com/cloudcafetech/nestedk8s/main/smaple-app.yaml
