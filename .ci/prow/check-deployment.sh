#!/usr/bin/env bash

# exit codes:
# 1..5 - a wrong configuration on root route
# 6..10 - a wrong configuration on /api/v3/ route
# 11..15 - a wrong configuration on /auth/login/ route
# 16..20 - a wrong configuration on /pulp/content/ route
# 21 - a wrong certificate configured on route
# 22 - a wrong key cert configured on route
# 23 - the hostname does not match certificate subject SAN or common name
# 24 - found a pulp-web resource when it should not be deployed
# 25 - failed to authenticate in pulp-container
# 26 - failed to push image to pulp-container
# 27 - failed to pull image from pulp-container

set -e #fail in case of non zero return

CI_TEST=${CI_TEST:-pulp}
API_ROOT=${API_ROOT:-"/pulp/"}
OPERATOR_NAMESPACE=${OPERATOR_NAMESPACE:-"pulp-operator-system"}
PULP_INSTANCE="ocp-example"


echo "Waiting pulp instance ..."
while true ; do if [ $(oc -n $OPERATOR_NAMESPACE get pulp $PULP_INSTANCE -oname) ] ; then break ; else sleep 30 ; fi ; done

INGRESS_DEFAULT_DOMAIN=$(oc -n $OPERATOR_NAMESPACE get ingresses.config/cluster -o jsonpath={.spec.domain})

echo "Waiting operator finishes its execution ..."
# wait until operator finishes its execution to start the tests
oc -n $OPERATOR_NAMESPACE wait --for condition=Pulp-Operator-Finished-Execution pulp/$PULP_INSTANCE --timeout=-1s

source .ci/prow/check_route_paths.sh

# should also tests things like:
# - if deployment type=galaxy and /pulp_cookbook/content/ route is present ERROR
# - if deployment type=galaxy and /pypi/ route is present ERROR
# ...

# check route certificates
route_secret=$(oc -n $OPERATOR_NAMESPACE get pulp $PULP_INSTANCE -ojsonpath='{.spec.route_tls_secret}')
if [[ $route_secret != "" ]] ; then
  for route in $(oc -n $OPERATOR_NAMESPACE get routes -oname) ; do
    route_certificate=$(oc -n $OPERATOR_NAMESPACE get route $route -ogo-template='{{.spec.tls.certificate}}{{"\n"}}' | md5sum)
    secret_certificate=$(oc -n $OPERATOR_NAMESPACE extract "secret/$route_secret" --keys=tls.crt  --to=- | md5sum)
    if [[ $secret_certificate != $route_certificate ]] ; then exit 21 ; fi

    route_cert_key=$(oc -n $OPERATOR_NAMESPACE get route $route -ogo-template='{{.spec.tls.key}}{{"\n"}}' | md5sum)
    secret_cert_key=$(oc -n $OPERATOR_NAMESPACE extract "secret/$route_secret" --keys=tls.key  --to=- | md5sum)
    if [[ $route_cert_key != $secret_cert_key ]] ; then exit 22 ; fi
  done
  echo "[OK] route certificates ..."
fi


# validate route hostname and certificate
check_host_cert=$(echo | openssl s_client -verify_hostname  "${PULP_INSTANCE}.${INGRESS_DEFAULT_DOMAIN}"  -connect "${PULP_INSTANCE}.${INGRESS_DEFAULT_DOMAIN}":443 2>/dev/null | awk -F': ' '/Verification/ {print $2}')
if [[ "$check_host_cert" != "OK" ]] ; then exit 23 ; fi
echo "[OK] hostname matching certificate subject ..."

# check pulp-web components
if [[ $(oc -n $OPERATOR_NAMESPACE get svc,deployment,cm -l "app.kubernetes.io/name=nginx" -o name | wc -l) > 0 ]] ; then exit 24 ;fi
echo "[OK] no pulp-web resource found ..."

#############
# e2e tests
#############
# skipping tls verification as we already checked it
# pointing the authfile to /tmp because by default it writes a file into /run/containers which is not allowed in our prow-test image
skopeo login --authfile=/tmp/test-skopeo --tls-verify=false -u admin -p $(oc -n $OPERATOR_NAMESPACE extract secret/example-pulp-admin-password --to=-) "${PULP_INSTANCE}.${INGRESS_DEFAULT_DOMAIN}"
if [ $? != 0 ] ; then exit 25 ; fi
echo "[OK] skopeo login ..."

skopeo copy --authfile=/tmp/test-skopeo --dest-tls-verify=false docker://quay.io/operator-framework/opm docker://"${PULP_INSTANCE}.${INGRESS_DEFAULT_DOMAIN}"/${OPERATOR_NAMESPACE}/test:latest
if [ $? != 0 ] ; then exit 26 ; fi
echo "[OK] skopeo copy ..."

oc -n $OPERATOR_NAMESPACE create secret docker-registry pulp-test --docker-server="${PULP_INSTANCE}.${INGRESS_DEFAULT_DOMAIN}" --docker-username=admin --docker-password="$(oc -n $OPERATOR_NAMESPACE extract secret/example-pulp-admin-password --to=-)"
oc -n $OPERATOR_NAMESPACE import-image --insecure=true test-image --from=${PULP_INSTANCE}.${INGRESS_DEFAULT_DOMAIN}/${OPERATOR_NAMESPACE}/test:latest --confirm
if [[ ! $(oc -n $OPERATOR_NAMESPACE get is test-image -ojsonpath='{.status.tags[0].items[0].generation}') > 0 ]] ; then exit 27 ; fi
echo "[OK] image pulled ..."

source .ci/prow/modify_route.sh

echo "All route configurations OK!"
