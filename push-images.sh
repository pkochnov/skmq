DIR=${dirname $0}

discli --insecure push ${DIR}/images/arangodb-3.11.12.tar registry:5000/arangodb:3.11.12

discli --insecure push ${DIR}/images/postgres-16.6.tar registry:5000/postgres:16.6

discli --insecure push ${DIR}/images/redis-7.4.2.tar registry:5000/redis:7.4.2

discli --insecure push ${DIR}/images/victoria-metrics-v1.108.1.tar registry:5000/victoriametrics/victoria-metrics:v1.108.1
