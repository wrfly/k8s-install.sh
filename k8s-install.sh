#!/bin/bash
# k8s installation in Ubuntu

echo "Installation start at `date`"
now=`date +%s`
function log() {
  echo "[$((`date +%s` - now ))] ## $@ ##"
}

# prepare
MASTER="Y"
SINGLE_MASTER="N"
read -p "Install as a master node?: " -ei $MASTER MASTER
if [[ "$MASTER" == "Y" ]];then
  PRIMARY_IP=$(ip route get 8.8.8.8 | head -1 | awk '{print $7}')
  read -p "The API server's address will be: " -ei $PRIMARY_IP PRIMARY_IP
  read -p "Run this cluster as a single node?: " -ei $SINGLE_MASTER SINGLE_MASTER
fi

# install docker
log "install docker"
apt-get update
apt-get -y install apt-transport-https ca-certificates curl software-properties-common
curl -fsSL http://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | apt-key add -
cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=amd64] https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable
EOF
apt-get -y update
apt-get -y install docker-ce

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
apt-get install -y apt-transport-https curl
## I built a reverse proxy here, but you can use aliyun for better donwload speed
# curl -fsSL https://packagescloudgooglecoms.kfd.me/apt/doc/apt-key.gpg | apt-key add -
# cat >/etc/apt/sources.list.d/kubernetes.list <<EOF
# deb [arch=amd64] http://packagescloudgooglecom.kfd.me/apt/ kubernetes-$(lsb_release -cs) main
# EOF

curl -fsSL https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | apt-key add -
cat >/etc/apt/sources.list.d/kubernetes.list <<EOF
deb [arch=amd64] https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-$(lsb_release -cs) main
EOF

apt-get update
apt-get install -y kubelet kubeadm kubectl
kubeadm completion bash > /etc/bash_completion.d/k8s

# turn off swap for k8s doesn't support it
log "turn off swap for k8s doesn't support it"
swapoff -a && sed -i "s/exit/\# for k8s\nswapoff -a\nexit/g" /etc/rc.local

# configure kubelet for downloading pause image
log "configure kubelet for downloading pause image"
sed -i "s/ExecStart=$/Environment=\"KUBELET_EXTRA_ARGS=--pod-infra-container-image=k8s-gcr.mirror.kfd.me\/pause-amd64:3.0\"\nExecStart=/g" \
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
log "we are ready to go!"
kubeadm init --config=kube-admin.conf

log "copy config files"
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config

log "init calico network"
wget 'u.kfd.me/2C8' -qO- | sed "s/quay.io/quay-io.mirror.kfd.me/g" > calico.yaml
kubectl apply -f calico.yaml

[[ "$SINGLE_MASTER" == "Y" ]] && \
  kubectl taint nodes --all node-role.kubernetes.io/master-
