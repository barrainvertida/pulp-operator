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

CI_TEST=${CI_TEST:-pulp}
API_ROOT=${API_ROOT:-"/pulp/"}
OPERATOR_NAMESPACE=${OPERATOR_NAMESPACE:-"pulp-operator-system"}
PULP_INSTANCE="ocp-example"
INGRESS_DEFAULT_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath={.spec.domain})

######################
# Update ingress_type
######################
echo "Updating pulp CR with: ingress_type=ingress ..."
oc -n $OPERATOR_NAMESPACE patch pulp $PULP_INSTANCE --type=merge  -p "{\"spec\": {\"ingress_type\": \"ingress\"}}"

echo "Waiting until operator finishes its execution ..."
check_and_wait_operator_running $OPERATOR_NAMESPACE $PULP_INSTANCE

echo "Starting tests ..."

# none of the routes are getting deleted and ocp is creating
# a new one to the ingress
# echo "Verifying if the routes were deleted ..."
# if [[ ! $(oc get routes) ]] ; then exit 64 ;fi

echo "Verifying if pulp-web ingress was created ..."
if [[ ! $(oc -n $OPERATOR_NAMESPACE get ingress "$PULP_INSTANCE-ingress") ]] ; then exit 65 ; fi

echo "Verifying if pulp-web deployment was created ..."
if [[ ! $(oc -n $OPERATOR_NAMESPACE get deployment -l app.kubernetes.io/component=webserver) ]] ; then exit 66 ; fi

echo "Verifying if pulp-web svc was created ..."
if [[ ! $(oc -n $OPERATOR_NAMESPACE get svc -l app.kubernetes.io/component=webserver) ]] ; then exit 67 ; fi
