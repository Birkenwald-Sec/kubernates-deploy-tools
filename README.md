# kubernates-deploy-tools

`A deployment tool for quickly deploying k8s master nodes and worker nodes, suitable for Ubuntu 20.04`

#### 注意

``` python
# before you run this script.
# you need set your hostname first
# case: hostnamectl set-hostname k8s-worker1
#       sed -i -e "s/127.0.1.1.*/127.0.1.1 k8s-worker1/g" /etc/hosts
#       echo "hostip k8s-worker1" >> /etc/hosts
# this script need ubuntu 20.04 or a higher version to run
# the script must executed by the root user
```

极速部署！
