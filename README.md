# k8s-install.sh

一行命令安装 *docker-ce* & *kubernetes(1.10)*

```bash
bash <(curl -fSsL https://git.io/vpY6k)
```

## Requirements

- N台虚拟机,1核1G及以上, N>=1
- Ubuntu 14.04+
- 得联网

## Feature

- 用代理的镜像仓库(`k8s-gcr.mirror.kfd.me`)替换`k8s.gcr.io`
- 用代理的镜像仓库(`quay-io.mirror.kfd.me`)替换`quay.io`
- 使用aliyun的mirror安装*docker-ce*, *kubeadm*, *kubelet* 以及 *kubectl*

## TODO

- [x] Ubuntu Support
- [ ] CentOS Support