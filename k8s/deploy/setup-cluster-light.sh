#!/bin/bash
# Optimized setup script for YAS infrastructure on Minikube (without Observability)
set -x

# Add chart repos and update
helm repo add postgres-operator-charts https://opensource.zalando.com/postgres-operator/charts/postgres-operator
helm repo add strimzi https://strimzi.io/charts/
helm repo add akhq https://akhq.io/
helm repo add elastic https://helm.elastic.co
helm repo update

# Read configuration values from cluster-config.yaml
read -rd '' DOMAIN POSTGRESQL_REPLICAS POSTGRESQL_USERNAME POSTGRESQL_PASSWORD \
KAFKA_REPLICAS ZOOKEEPER_REPLICAS ELASTICSEARCH_REPLICAS \
< <(yq -r '.domain, .postgresql.replicas, .postgresql.username,
 .postgresql.password, .kafka.replicas, .zookeeper.replicas,
 .elasticsearch.replicas' ./cluster-config.yaml)

# Install the postgres-operator
helm upgrade --install postgres-operator postgres-operator-charts/postgres-operator \
 --create-namespace --namespace postgres

# Install postgresql
helm upgrade --install postgres ./postgres/postgresql \
 --create-namespace --namespace postgres \
 --set replicas="$POSTGRESQL_REPLICAS" \
 --set username="$POSTGRESQL_USERNAME" \
 --set password="$POSTGRESQL_PASSWORD"

# Install pgadmin
pg_admin_hostname="pgadmin.$DOMAIN" yq -i '.hostname=env(pg_admin_hostname)' ./postgres/pgadmin/values.yaml
helm upgrade --install pgadmin ./postgres/pgadmin \
 --create-namespace --namespace postgres

# Install strimzi-kafka-operator
helm upgrade --install kafka-operator strimzi/strimzi-kafka-operator \
 --create-namespace --namespace kafka

# Install kafka and postgresql connector
helm upgrade --install kafka-cluster ./kafka/kafka-cluster \
 --create-namespace --namespace kafka \
 --set kafka.replicas="$KAFKA_REPLICAS" \
 --set zookeeper.replicas="$ZOOKEEPER_REPLICAS" \
 --set postgresql.username="$POSTGRESQL_USERNAME" \
 --set postgresql.password="$POSTGRESQL_PASSWORD"

# Install akhq
akhq_hostname="akhq.$DOMAIN" yq -i '.hostname=env(akhq_hostname)' ./kafka/akhq.values.yaml
helm upgrade --install akhq akhq/akhq \
 --create-namespace --namespace kafka \
 --values ./kafka/akhq.values.yaml

# Install elastic-operator
helm upgrade --install elastic-operator elastic/eck-operator \
 --create-namespace --namespace elasticsearch

# Install elasticsearch-cluster
helm upgrade --install elasticsearch-cluster ./elasticsearch/elasticsearch-cluster \
 --create-namespace --namespace elasticsearch \
 --set elasticsearch.replicas="$ELASTICSEARCH_REPLICAS" \
 --set kibana.ingress.hostname="kibana.$DOMAIN"

# Install zookeeper
helm upgrade --install zookeeper ./zookeeper \
 --namespace zookeeper --create-namespace

echo "Core infrastructure setup completed successfully!"
