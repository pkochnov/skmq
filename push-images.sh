DIR=${dirname $0}

discli --insecure push ${DIR}/images/arangodb:3.11.12 registry:5000/arangodb:3.11.12

discli --insecure push ${DIR}/images/postgres:16.6 registry:5000/postgres:16.6
