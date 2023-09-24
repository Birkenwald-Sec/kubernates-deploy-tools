#! /bin/bash

# scp -r svr4@192.168.227.129:/home/svr4/kube-deploy ./

# before you run this script.
# you need set your hostname first
# case: hostnamectl set-hostname k8s-worker1
#       sed -i -e "s/127.0.1.1.*/127.0.1.1 k8s-worker1/g" /etc/hosts
#       echo "hostip k8s-worker1" >> /etc/hosts
# this script need ubuntu 20.04 or a higher version to run
# the script must executed by the root user

# variable defined
timeout_duration=180
ip_addr="$(ip -br addr | awk '{print $1" "$3}' | grep -v lo | awk '{print $2}' | rev | cut -d'/' -f2- | rev)"

# change apt source
# do not change the repo!
function change_repo(){
    read -p "Do you need to change the APT source?(y/n): " answer
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        echo "Which source do you like to change to?"
        echo "1) aliyun"
        echo "2) tsinghua"
        echo "3) zhongkeda"
        read -p "Option: " option
        case "$option" in
            "1" | "aliyun")
                sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list.d/original.list
                echo "aliyun repo changed successfully."
                ;;
            "2" | "tsinghua")
                sed -i 's/archive.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list.d/original.list
                echo "tsinghua repo changed successfully."
                ;;
            "3" | "zhongkeda")
                sed -i 's/archive.ubuntu.com/mirrors.ustc.edu.cn/g' /etc/apt/sources.list.d/original.list
                echo "zhongkeda repo changed successfully."
                ;;
            *)
                ;;
        esac
    fi
    apt-get update
}

function change_hostname(){
    read -p "hostname: " hostname
    hostnamectl set-hostname $hostname
    sed -i -e "s/127.0.1.1.*/127.0.1.1 $hostname/g" /etc/hosts
    echo $ip_addr" "$hostname >> /etc/hosts
}

# setting your envirenment
function set_environment(){
    change_repo
    change_hostname
    swapoff -a
    sed -i -e "s/.*\(\/swap.img.*\)/#\1/g" /etc/fstab
    systemctl disable ufw --now
    apt install -y resolvconf
    echo "nameserver 8.8.8.8" >> /etc/resolvconf/resolv.conf.d/head
    systemctl enable --now resolvconf
    resolvconf -u
}

function check_docker(){
    if ! which docker > /dev/null 2>&1; then
        apt-get install -y ca-certificates curl gnupg lsb-release
        curl -fsSL http://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
        add-apt-repository "deb [arch=amd64] http://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable"
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io
        mkdir /etc/docker
        touch /etc/docker/daemon.json
        echo '{"registry-mirrors": ["https://docker.mirrors.ustc.edu.cn","https://hub-mirror.c.163.com","https://reg-mirror.qiniu.com","https://registry.docker-cn.com"],"exec-opts": ["native.cgroupdriver=systemd"]}' > /etc/docker/daemon.json
        systemctl daemon-reload > /dev/null 2>&1
        systemctl restart docker > /dev/null 2>&1
        systemctl enable docker > /dev/null 2>&1
    fi
}

function check_cri_docker(){
    if ! which cri-dockerd > /dev/null 2>&1; then
        apt install -y "./"$(ls | grep cri-dockerd)
        sed -i -e 's#ExecStart=.*#ExecStart=/usr/bin/cri-dockerd --pod-infra-container-image=registry.aliyuncs.com/google_containers/pause:3.8 --container-runtime-endpoint fd:// --network-plugin=cni --cni-bin-dir=/opt/cni/bin --cni-cache-dir=/var/lib/cni/cache --cni-conf-dir=/etc/cni/net.d#g' /usr/lib/systemd/system/cri-docker.service
        systemctl daemon-reload
        systemctl enable --now cri-docker
        sed -i -e "s/disabled_plugins(.*)/#disabled_plugins\1/g" /etc/containerd/config.toml
    fi
}

function check_k8s_tools(){
    if ! which kubeadm > /dev/null 2>&1; then
        apt-get install -y apt-transport-https
        curl https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | apt-key add - 
        cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main
EOF
        apt-get update
        apt-get install -y kubelet=1.25.0-00 kubeadm=1.25.0-00 kubectl=1.25.0-00
        apt-mark hold kubelet kubeadm kubectl
        mkdir /etc/sysconfig
        echo "KUBELET_KUBEADM_ARGS=\"--container-runtime=remote --container-runtime-endpoint=/run/cri-dockerd.sock\"" > /etc/sysconfig/kubelet
        systemctl enable --now kubelet
    fi
}

function init_k8s_master(){
    kubeadm config images pull --image-repository=registry.aliyuncs.com/google_containers --cri-socket unix:///run/cri-dockerd.sock
    kubeadm init --control-plane-endpoint=$ip_addr --kubernetes-version=v1.25.0 --pod-network-cidr=10.244.0.0/16 --service-cidr=10.96.0.0/12 --token-ttl=0 --cri-socket=unix:///run/cri-dockerd.sock --upload-certs --image-repository registry.aliyuncs.com/google_containers
    export KUBECONFIG=/etc/kubernetes/admin.conf
    mkdir -p $HOME/.kube
    cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    chown $(id -u):$(id -g) $HOME/.kube/config
    kubectl apply -f ./kube-flannel.yml
    # 经过上述步骤之后即可将master节点初始化成功
    # 之后执行最后的输出：kubeadm join...即可
}

function init_k8s_worker(){
    kubeadm config images pull --image-repository=registry.aliyuncs.com/google_containers --cri-socket unix:///run/cri-dockerd.sock
    docker load -i ./flannel1.tar
    docker load -i ./flannel2.tar
}


function main(){
    set_environment
    check_docker
    check_cri_docker
    check_k8s_tools
    init_k8s_master
}

if [ -n "SUDO_USER" ]; then
    main
else
    echo "This script requires sudo privileges tp execute."
    exit
fi
