#!/usr/bin/env bash

set -e #fail in case of non zero return

CI_TEST=${CI_TEST:-pulp}
API_ROOT=${API_ROOT:-"/pulp/"}
OPERATOR_NAMESPACE=${OPERATOR_NAMESPACE:-"pulp-operator-system"}
PULP_INSTANCE="ocp-example"
INGRESS_DEFAULT_DOMAIN=$(oc -n $OPERATOR_NAMESPACE get ingresses.config/cluster -o jsonpath={.spec.domain})

# Update route_host
oc -n $OPERATOR_NAMESPACE patch pulp $PULP_INSTANCE --type=merge  -p "{\"spec\": {\"route_host\": \"pulp.${INGRESS_DEFAULT_DOMAIN}\"}}"

echo "Waiting operator finishes its execution ..."
sleep 10 # give sometime to operator start reconcile process
# wait until operator finishes its execution to start the tests
oc -n $OPERATOR_NAMESPACE wait --for condition=Pulp-Operator-Finished-Execution pulp/$PULP_INSTANCE --timeout=-1s

# re-test
source .ci/prow/check_route_paths.sh "pulp.${INGRESS_DEFAULT_DOMAIN}"

# Update route_host
oc -n $OPERATOR_NAMESPACE patch pulp $PULP_INSTANCE --type=json -p '[{"op": "replace", "path": "/spec/route_host", "value", ""}]'

echo "Waiting operator finishes its execution ..."
# wait until operator finishes its execution to start the tests
sleep 10 # give sometime to operator start reconcile process
oc -n $OPERATOR_NAMESPACE wait --for condition=Pulp-Operator-Finished-Execution pulp/$PULP_INSTANCE --timeout=-1s

# re-test
source .ci/prow/check_route_paths.sh

