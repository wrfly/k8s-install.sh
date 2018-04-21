#!/bin/bash
# k8s installation in Ubuntu

echo "Installation start at `date`"
now=`date +%s`
function log() {
  echo "[$((`date +%s` - now ))] ## $@ ##"
}

# install docker
log "install docker"
apt-get update
apt-get -y install apt-transport-https ca-certificates curl software-properties-common
curl -fsSL http://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] http://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable"
apt-get -y update
apt-get -y install docker-ce

# congifure mirror and registries
log "congifure mirror and registries"
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
# curl -s https://packagescloudgooglecoms.kfd.me/apt/doc/apt-key.gpg | apt-key add -
# cat >/etc/apt/sources.list.d/kubernetes.list <<EOF
# deb http://packagescloudgooglecom.kfd.me/apt/ kubernetes-xenial main
# EOF

curl https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | apt-key add -
cat >/etc/apt/sources.list.d/kubernetes.list <<EOF
deb https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main
EOF

apt-get update
apt-get install -y kubelet kubeadm kubectl
kubeadm completion bash > /etc/bash_completion.d/k8s

# configure kubelet for downloading pause image
log "configure kubelet for downloading pause image"
sed -i "s/ExecStart=$/Environment=\"KUBELET_EXTRA_ARGS=--pod-infra-container-image=k8s-gcr.mirror.kfd.me\/pause-amd64:3.0\"\nExecStart=/g" \
    /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
log "and restart kubelet"
systemctl daemon-reload && systemctl restart kubelet

# turn off swap for k8s doesn't support it
log "turn off swap for k8s doesn't support it"
swapoff -a && sed -i "s/exit/\# for k8s\nswapoff -a\nexit/g" /etc/rc.local

# set k8s configuration
log "set k8s configuration"
PRIMARY_IP=$(ip route get 8.8.8.8 | head -1 | awk '{print $7}')
read -p "The API server's address will be: " -ei $PRIMARY_IP PRIMARY_IP
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

# uncaomment this line for running pods in master node,
# if you only have one node
# kubectl taint nodes --all node-role.kubernetes.io/master-
