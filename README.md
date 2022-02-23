## Setup Nested Kubernetes Cluster using Kuevirt

KubeVirt, a tool that can be used to create and manage Virtual Machines (VM) within a Kubernetes cluster. 
Using KubeVirt to create a Kubernetes Cluster within a Kubernetes Cluster (Nested Kubernetes Cluster)

### Install K8S Cluster or use [Katakoda](https://www.katacoda.com/kubevirt/scenarios/kubevirt-cdi)

```
kubectl  wait --for=condition=Ready node --all --timeout 60s
alias oc=kubectl
oc get no
kubectl taint node controlplane node-role.kubernetes.io/master:NoSchedule-
```

### Install Local Persistent Storage 

```
wget https://raw.githubusercontent.com/kubevirt/hostpath-provisioner/main/deploy/kubevirt-hostpath-provisioner.yaml
kubectl create -f kubevirt-hostpath-provisioner.yaml
kubectl annotate storageclass kubevirt-hostpath-provisioner storageclass.kubernetes.io/is-default-class=true
kubectl get sc
```

### Install Kubevirt Operator and CRD

```
export KUBEVIRT_VERSION=$(curl -s https://api.github.com/repos/kubevirt/kubevirt/releases/latest | jq -r .tag_name)
echo $KUBEVIRT_VERSION
kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml
kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml
kubectl -n kubevirt patch kubevirt kubevirt --type=merge --patch '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}'
kubectl get kubevirt -n kubevirt
kubectl get pods -n kubevirt
kubectl wait po `kubectl get po -n kubevirt | grep virt-operator | awk '{print $1}'` --for=condition=Ready --timeout=5m -n kubevirt
sleep 90
kubectl wait po `kubectl get po -n kubevirt | grep virt-api | awk '{print $1}'` --for=condition=Ready --timeout=2m -n kubevirt
sleep 10
kubectl wait po `kubectl get po -n kubevirt | grep virt-controller | awk '{print $1}'` --for=condition=Ready --timeout=2m -n kubevirt
kubectl wait po `kubectl get po -n kubevirt | grep virt-handler | awk '{print $1}'` --for=condition=Ready --timeout=2m -n kubevirt
kubectl get po -n kubevirt
```

### Install Kubevirt Tool

```
wget -O virtctl https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/virtctl-${KUBEVIRT_VERSION}-linux-amd64
chmod +x virtctl
sudo cp virtctl /usr/bin/
```

### Install Kubevirt Containerized Data Importer

```
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
```

### Import Cloud Image (Ubuntu 20.04 / CentOS 8) using Data Importer 

```
cat <<EOF > vm-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: "vm-data-volume"
  labels:
    app: containerized-data-importer
  annotations:
    #cdi.kubevirt.io/storage.import.endpoint: "https://cloud.centos.org/centos/8/x86_64/images/CentOS-8-GenericCloud-8.3.2011-20201204.2.x86_64.qcow2"
    cdi.kubevirt.io/storage.import.endpoint: "https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img"
    kubevirt.io/provisionOnNode: node01
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 15Gi
EOF

kubectl create -f vm-pvc.yaml
kubectl wait po `kubectl get po | grep importer | awk '{print $1}'` --for=condition=Ready --timeout=2m 
kubectl logs -f `kubectl get po | grep importer | awk '{print $1}'`
```

### Deploy VM using the DataVolume

- Create VM manifest

```
cat <<EOF > vm.yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  labels:
    kubevirt.io/os: linux
  name: kubevm
spec:
  running: true
  template:
    metadata:
      labels:
        kubevirt.io/domain: kubevm
    spec:
      domain:
        cpu:
          cores: 2
        devices:
          disks:
          - disk:
              bus: virtio
            name: disk0
          - cdrom:
              bus: sata
              readonly: true
            name: cloudinitdisk
        machine:
          type: q35
        resources:
          requests:
            memory: 1024M
      volumes:
      - name: disk0
        persistentVolumeClaim:
          claimName: vm-data-volume
      - cloudInitNoCloud:
          userData: |
            #cloud-config
            hostname: kubevm
            user: root
            password: passwd
            chpasswd: { expire: False }
            ssh_pwauth: True
            disable_root: false
            ssh_authorized_keys:
            - ssh-rsa PUBLIC_SSH_KEY
        name: cloudinitdisk
EOF
```

- Generate a password less SSH key and add in VM manifest

```
ssh-keygen -q -t rsa -N '' -f ~/.ssh/id_rsa <<<y >/dev/null 2>&1

PUBKEY=`cat ~/.ssh/id_rsa.pub`
echo $PUBKEY
sed -i "s%ssh-rsa.*%$PUBKEY%" vm.yaml
more vm.yaml
```

- Deploy VM

```
kubectl create -f vm.yaml
sleep 5
kubectl wait po `kubectl get po | grep virt-launcher | awk '{print $1}'` --for=condition=Ready --timeout=2m 
```

- Check the Virtual Machine Instance (VMI) has been created

```
kubectl get vms,vmi,po
kubectl wait vm `kubectl get vm | grep -v NAME | awk '{print $1}'` --for=condition=Ready --timeout=2m
```

- Connect to the Console of the VM

```virtctl console `kubectl get vm | grep -v NAME | awk '{print $1}'` ```

- Access VM using SSH

```
VMIP=`kubectl get vmi | grep -v NAME | awk '{print $4}'`
ssh root@$VMIP 
```

####  Update CentOS repo (Due to Error: Failed to download metadata for repo 'appstream')

```
cd /etc/yum.repos.d/
sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*
sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*
yum update -y
```

#### Setup RKE2

```
curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL=v1.20 sh -

mkdir -p /etc/rancher/rke2
cat << EOF >  /etc/rancher/rke2/config.yaml
write-kubeconfig-mode: "0644"
tls-san:
  - "k8s.kubevm.intra"
EOF

systemctl enable rke2-server.service
systemctl start rke2-server.service
systemctl status rke2-server.service

mkdir ~/.kube
ln -s /etc/rancher/rke2/rke2.yaml ~/.kube/config
chmod 600 /root/.kube/config
ln -s /var/lib/rancher/rke2/agent/etc/crictl.yaml /etc/crictl.yaml
export PATH=/var/lib/rancher/rke2/bin:$PATH
echo "export PATH=/var/lib/rancher/rke2/bin:$PATH" >> $HOME/.bash_profile
echo "alias oc=/var/lib/rancher/rke2/bin/kubectl" >> $HOME/.bash_profile
```
