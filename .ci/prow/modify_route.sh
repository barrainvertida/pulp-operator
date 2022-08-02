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

####################
# Update route_host
####################
NEW_TEST_ROUTE="pulp.${INGRESS_DEFAULT_DOMAIN}"
echo "Updating pulp CR with: route_host=${NEW_TEST_ROUTE} ..."
oc -n $OPERATOR_NAMESPACE patch pulp $PULP_INSTANCE --type=merge  -p "{\"spec\": {\"route_host\": \"${NEW_TEST_ROUTE}\"}}"

echo "Waiting until operator finishes its execution ..."
check_and_wait_operator_running $OPERATOR_NAMESPACE $PULP_INSTANCE

echo "starting tests ..."
# re-test
source .ci/prow/check_route_paths.sh "${NEW_TEST_ROUTE}"

###########################
# Define route_host as ""
###########################
echo "Updating pulp CR with: route_host=\"\" ..."
oc -n $OPERATOR_NAMESPACE patch pulp $PULP_INSTANCE --type=json -p '[{"op": "replace", "path": "/spec/route_host", "value", ""}]'

echo "Waiting until operator finishes its execution ..."
check_and_wait_operator_running $OPERATOR_NAMESPACE $PULP_INSTANCE

# re-test
source .ci/prow/check_route_paths.sh

#######################
# Update route_host
#######################
NEW_TEST_ROUTE="pulp-test-2.${INGRESS_DEFAULT_DOMAIN}"
echo "Updating pulp CR with: route_host=${NEW_TEST_ROUTE} ..."
oc -n $OPERATOR_NAMESPACE patch pulp $PULP_INSTANCE --type=merge  -p "{\"spec\": {\"route_host\": \"${NEW_TEST_ROUTE}\"}}"

echo "Waiting until operator finishes its execution ..."
check_and_wait_operator_running $OPERATOR_NAMESPACE $PULP_INSTANCE

# re-test
source .ci/prow/check_route_paths.sh "${NEW_TEST_ROUTE}"

#############################################
# Delete route_host definition from pulp CR
#############################################
# check if operator is not running before proceeding
echo "Removing route_host definition from pulp CR ..."
oc -n $OPERATOR_NAMESPACE patch pulp $PULP_INSTANCE --type=json -p '[{"op": "remove", "path": "/spec/route_host"}]'

echo "Waiting until operator finishes its execution ..."
check_and_wait_operator_running $OPERATOR_NAMESPACE $PULP_INSTANCE

# re-test
source .ci/prow/check_route_paths.sh
