#!/usr/bin/env bash

set -ex #fail in case of non zero return

CI_TEST=${CI_TEST:-pulp}
API_ROOT=${API_ROOT:-"/pulp/"}
OPERATOR_NAMESPACE=${OPERATOR_NAMESPACE:-"pulp-operator-system"}
PULP_INSTANCE="ocp-example"
INGRESS_DEFAULT_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath={.spec.domain})
ROUTE_HOST=${1:-"${PULP_INSTANCE}.${INGRESS_DEFAULT_DOMAIN}"}

# check route certificates
route_secret=$(oc -n $OPERATOR_NAMESPACE get pulp $PULP_INSTANCE -ojsonpath='{.spec.route_tls_secret}')
if [[ $route_secret != "" ]] ; then
  for route in $(oc -n $OPERATOR_NAMESPACE get routes -oname) ; do
    route_certificate=$(oc -n $OPERATOR_NAMESPACE get $route -ogo-template='{{.spec.tls.certificate}}{{"\n"}}' | md5sum)
    secret_certificate=$(oc -n $OPERATOR_NAMESPACE extract "secret/$route_secret" --keys=tls.crt  --to=- | md5sum)
    if [[ $secret_certificate != $route_certificate ]] ; then exit 21 ; fi

    route_cert_key=$(oc -n $OPERATOR_NAMESPACE get $route -ogo-template='{{.spec.tls.key}}{{"\n"}}' | md5sum)
    secret_cert_key=$(oc -n $OPERATOR_NAMESPACE extract "secret/$route_secret" --keys=tls.key  --to=- | md5sum)
    if [[ $route_cert_key != $secret_cert_key ]] ; then exit 22 ; fi
  done
  echo "[OK] route certificates ..."
fi

# validate route hostname and certificate
check_host_cert=$(echo | openssl s_client -verify_hostname ${ROUTE_HOST} -connect ${ROUTE_HOST}:443 2>/dev/null | awk -F': ' '/Verification/ {print $2}')
if [[ "$check_host_cert" != "OK" ]] ; then exit 23 ; fi
echo "[OK] hostname matching certificate subject ..."
