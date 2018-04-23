#!/bin/bash
# k8s installation
# wrfly@1524493922

now=`date +%s`
function log() {
  echo "[$((`date +%s` - now ))] ## $@ ##"
}

log "Installation start at `date`"

# check
[[ `whoami` != "root" ]] && echo "Root Privilege needed, use sudo please." && exit 1
OS=`awk -F= '/^NAME/{print $2}' /etc/os-release | sed "s/\"//g"`
if [[ "$OS" == "Ubuntu" ]];then
  :
elif [[ "$OS" == "CentOS Linux" ]];then
  OS="CentOS"
else
  echo "Unknown OS: \"$OS\", exit"
  exit 2
fi

# prepare
MASTER="Y"
SINGLE_MASTER="N"
read -p "Install as a master node?: " -ei $MASTER MASTER
if [[ "$MASTER" == "Y" ]];then
  PRIMARY_IP=$(ip route get 8.8.8.8 | head -1 | awk '{print $7}')
  echo "All your IP addresses: `hostname --all-ip-addresses || hostname -I`"
  read -p "The API server's address will be: " -ei $PRIMARY_IP PRIMARY_IP
  read -p "Run this cluster as a single node?: " -ei $SINGLE_MASTER SINGLE_MASTER
fi

# install docker
log "install docker"
if [[ "$OS" == "Ubuntu" ]];then
  apt-get update
  apt-get -y install apt-transport-https ca-certificates curl software-properties-common
  curl -fsSL http://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | apt-key add -
  add-apt-repository -u "deb [arch=amd64] http://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable"
  apt-get -y install docker-ce
fi

if [[ "$OS" == "CentOS" ]];then
  yum install -y yum-utils device-mapper-persistent-data lvm2
  yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
  yum makecache fast
  yum -y install docker-ce
  service docker start
fi

# congifure mirror and insecure registries
log "congifure mirror and insecure registries"
cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["https://m.mirror.aliyuncs.com"],
  "insecure-registries" : ["quay-io.mirror.kfd.me", "k8s-gcr.mirror.kfd.me"]
}
EOF
systemctl daemon-reload && systemctl restart docker

# install k8s
log "install k8s"
if [[ "$OS" == "Ubuntu" ]];then
  apt-get install -y apt-transport-https curl wget
  ## I built a reverse proxy here, but you can use aliyun for better donwload speed
  # curl -fsSL https://packagescloudgooglecoms.kfd.me/apt/doc/apt-key.gpg | apt-key add -
  # cat >/etc/apt/sources.list.d/kubernetes.list <<EOF
  # deb [arch=amd64] http://packagescloudgooglecom.kfd.me/apt/ kubernetes-xenial main
  # EOF
  curl -fsSL https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | apt-key add -
  add-apt-repository -u "deb [arch=amd64] https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main"  
  apt-get install -y kubelet kubeadm kubectl
fi

if [[ "$OS" == "CentOS" ]];then
  cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF
  setenforce 0
  yum install -y kubelet kubeadm kubectl wget
  systemctl enable kubelet && systemctl start kubelet
fi

kubeadm completion bash > /etc/bash_completion.d/k8s

# turn off swap for k8s doesn't support it
log "turn off swap for k8s doesn't support it"
[[ "$OS" == "Ubuntu" ]] && \
  swapoff -a && sed -i "s/exit/\# for k8s\nswapoff -a\nexit/g" /etc/rc.local
[[ "$OS" == "CentOS" ]] && \
  swapoff -a && echo -e "# for k8s\nswapoff -a" >> /etc/rc.local
chmod +x /etc/rc.local

# configure kubelet for downloading pause image
log "configure kubelet for downloading pause image"
[[ "$OS" == "Ubuntu" ]] && \
  sed -i "s/ExecStart=$/Environment=\"KUBELET_EXTRA_ARGS=--pod-infra-container-image=k8s-gcr.mirror.kfd.me\/pause-amd64:3.0\"\nExecStart=/g" \
    /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
[[ "$OS" == "CentOS" ]] && \
  sed -i "s/ExecStart=$/Environment=\"KUBELET_EXTRA_ARGS=--pod-infra-container-image=k8s-gcr.mirror.kfd.me\/pause-amd64:3.0\"\nExecStart=/g; \
    s/cgroup-driver=systemd/cgroup-driver=cgroupfs/g" \
    /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

log "and restart kubelet"
systemctl daemon-reload && systemctl restart kubelet

if [[ "$MASTER" != "Y" ]];then
  log "install this node as a normal node, not master. exit."
  exit 0
fi

# set k8s configuration
cat > kube-admin.conf <<EOF
apiVersion: kubeadm.k8s.io/v1alpha1
kind: MasterConfiguration
api:
  advertiseAddress: "$PRIMARY_IP"
etcd:
  image: "k8s-gcr.mirror.kfd.me/etcd-amd64:3.0.4"
imageRepository: k8s-gcr.mirror.kfd.me
networking:
  podSubnet: "192.168.0.0/16"
EOF

# start to install
log "we are ready to go"
kubeadm init --config=kube-admin.conf

log "copy config files"
mkdir $HOME/.kube/
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config

log "init calico network"
wget 'u.kfd.me/2C8' -qO- | sed "s/quay.io/quay-io.mirror.kfd.me/g" > calico.yaml
kubectl apply -f calico.yaml

[[ "$SINGLE_MASTER" == "Y" ]] && \
  kubectl taint nodes --all node-role.kubernetes.io/master-
