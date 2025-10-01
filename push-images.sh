DIR=${dirname $0}

discli --insecure push ${DIR}/images/arangodb-3.11.12.tar registry:5000/arangodb:3.11.12
discli --insecure push ${DIR}/images/postgres-16.6.tar registry:5000/postgres:16.6
discli --insecure push ${DIR}/images/redis-7.4.2.tar registry:5000/redis:7.4.2
discli --insecure push ${DIR}/images/victoria-metrics-v1.108.1.tar registry:5000/victoriametrics/victoria-metrics:v1.108.1
discli --insecure push ${DIR}/images/rabbitmq-4.0.5.tar registry:5000/rabbitmq:4.0.5-management
discli --insecure push ${DIR}/images/consul-1.8.tar registry:5000/hashicorp/consul:1.8

# k8s
discli --insecure push ${DIR}/images/kube-apiserver-v1.31.13.tar registry:5000/kube-apiserver:v1.31.13
discli --insecure push ${DIR}/images/kube-controller-manager-v1.31.13.tar registry:5000/kube-controller-manager:v1.31.13
discli --insecure push ${DIR}/images/kube-proxy-v1.31.13.tar registry:5000/kube-proxy:v1.31.13
discli --insecure push ${DIR}/images/kube-scheduler-v1.31.13.tar registry:5000/kube-scheduler:v1.31.13

discli --insecure push ${DIR}/images/pause-3.8.tar registry:5000/pause:3.8

# Cilium
discli --insecure push ${DIR}/images/cilium-v1.16.5.tar registry:5000/quay.io/cilium/cilium:v1.16.5
discli --insecure push ${DIR}/images/cilium-operator-generic-v1.16.5.tar registry:5000/quay.io/cilium/operator-generic:v1.16.5
