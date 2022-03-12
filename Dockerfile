FROM ubuntu:20.04

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install krb5-user curl apt-transport-https gnupg expect -y && \
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - && \
    echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list && \
    apt-get update && \
    apt-get install kubectl -y && \
    apt-get -y remove curl apt-transport-https gnupg && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN groupadd -r container-user && \
    useradd --no-log-init -r -m -g container-user container-user 

COPY ./scripts /home/container-user

WORKDIR /home/container-user

USER container-user

ENTRYPOINT ["./generate-keytab-secret.sh"]

