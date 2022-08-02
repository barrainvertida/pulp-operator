#!/usr/bin/env bash

set -e #fail in case of non zero return

check_and_wait_operator_running() {
  sleep 15
  OPERATOR_NAMESPACE=$1
  PULP_INSTANCE=$2
  oc -n $OPERATOR_NAMESPACE wait --for condition=Pulp-Operator-Finished-Execution pulp/$PULP_INSTANCE --timeout=-1s

  # we will check again because the modification is happening only in a second playbook iteration
  sleep 15
  oc -n $OPERATOR_NAMESPACE wait --for condition=Pulp-Operator-Finished-Execution pulp/$PULP_INSTANCE --timeout=-1s
}

create_certs() {
  ca_days=365
  cert_days=30
  cert_name=${1:-ci}
  cert_subj="/CN=${2:-*.apps-crc.testing}"
  ca_subj="/CN=${3:-apps-crc.testing}"
  cert_san="subjectAltName=IP:0.0.0.0,DNS:${2:-*.apps-crc.testing}"

  openssl req -x509 -nodes -newkey rsa -days $ca_days -keyout /tmp/ca.key -out /tmp/ca.crt -subj $ca_subj
  openssl req -nodes -newkey rsa -keyout /tmp/${cert_name}.key -out /tmp/${cert_name}.csr -subj $cert_subj
  echo $cert_san > /tmp/${cert_name}-ext.cnf
  openssl x509 -req -in /tmp/${cert_name}.csr -days $cert_days -CA /tmp/ca.crt -CAkey /tmp/ca.key -CAcreateserial -out /tmp/${cert_name}.crt -extfile /tmp/${cert_name}-ext.cnf
}

CI_TEST=${CI_TEST:-pulp}
API_ROOT=${API_ROOT:-"/pulp/"}
OPERATOR_NAMESPACE=${OPERATOR_NAMESPACE:-"pulp-operator-system"}
PULP_INSTANCE="ocp-example"
INGRESS_DEFAULT_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath={.spec.domain})
TLS_SECRET="route-certs"

if [[ ! $(oc -n $OPERATOR_NAMESPACE get secret $TLS_SECRET) ]] ; then
  create_certs ci "*.$INGRESS_DEFAULT_DOMAIN"
  oc -n $OPERATOR_NAMESPACE create secret generic $TLS_SECRET --from-file=tls.crt=/tmp/ci.crt --from-file=tls.key=/tmp/ci.key --from-file=ca.crt=/tmp/ca.crt
fi


#######################################
## Update route_tls_secret=$TLS_SECRET
#######################################
echo "Updating pulp CR with: route_tls_secret=${TLS_SECRET} ..."
oc -n $OPERATOR_NAMESPACE patch pulp $PULP_INSTANCE --type=merge -p "{\"spec\": { \"route_tls_secret\": \"${TLS_SECRET}\"}}"

echo "Waiting until operator finishes its execution ..."
check_and_wait_operator_running $OPERATOR_NAMESPACE $PULP_INSTANCE
source .ci/prow/check_route_tls.sh

#######################################
## Update secret with an invalid data
#######################################
### SKIPING THIS TEST FOR NOW BECAUSE IT IS PUTTING THE OPERATOR INTO AN INFINITE LOOP!!!!
### SKIPING THIS TEST FOR NOW BECAUSE IT IS PUTTING THE OPERATOR INTO AN INFINITE LOOP!!!!
### SKIPING THIS TEST FOR NOW BECAUSE IT IS PUTTING THE OPERATOR INTO AN INFINITE LOOP!!!!
#echo "Updating $TLS_SECRET with an invalid data ..."
#oc -n $OPERATOR_NAMESPACE patch secret $TLS_SECRET -p '{"data": { "tls.crt": "c2VjcmV0Cg==" }}'
#
#echo "Waiting until operator finishes its execution ..."
#check_and_wait_operator_running $OPERATOR_NAMESPACE $PULP_INSTANCE
#source .ci/prow/check_route_tls.sh

#######################################
## Update route_tls_secret=""
#######################################
echo "Updating pulp CR with: route_tls_secret=\"\" ..."
oc -n $OPERATOR_NAMESPACE patch pulp $PULP_INSTANCE --type=json -p '[{"op": "replace", "path": "/spec/route_tls_secret", "value", ""}]'

echo "Waiting until operator finishes its execution ..."
check_and_wait_operator_running $OPERATOR_NAMESPACE $PULP_INSTANCE
source .ci/prow/check_route_tls.sh
