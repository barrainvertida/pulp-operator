#!/usr/bin/env bash

# exit codes:
# 1 - root route domain wrong
# 2 - root route path wrong
# 3 - root route port wrong
# 4 - root route termination wrong
# 5 - root route service wrong

set -ex #fail in case of non zero return

CI_TEST=${CI_TEST:-pulp}
API_ROOT=${API_ROOT:-"/pulp/"}
OPERATOR_NAMESPACE=${OPERATOR_NAMESPACE:-"pulp-operator-system"}
PULP_INSTANCE="ocp-example"


echo "Waiting pulp instance ..."
while true ; do if [ $(oc -n $OPERATOR_NAMESPACE get pulp $PULP_INSTANCE -oname) ] ; then break ; else sleep 5 ; fi ; done

INGRESS_DEFAULT_DOMAIN=$(oc -n $OPERATOR_NAMESPACE get ingresses.config/cluster -o jsonpath={.spec.domain})

# wait until operator finishes its execution to start the tests
oc -n $OPERATOR_NAMESPACE wait --for condition=Pulp-Operator-Finished-Execution pulp/$PULP_INSTANCE --timeout=-1s

# check root path
root_path=( $(oc -n $OPERATOR_NAMESPACE get route $PULP_INSTANCE -ogo-template='{{.spec.host}} {{.spec.path}} {{.spec.port.targetPort}}') )
if [ ${root_path[0]} != "${PULP_INSTANCE}.${INGRESS_DEFAULT_DOMAIN}" ] ; then exit 1 ; fi
if [ ${root_path[1]} != "/" ] ; then exit 2 ; fi
if [ ${root_path[2]} != "api-24817" ] ; then exit 3 ; fi
if [ ${root_path[3]} != "edge" ] ; then exit 4 ; fi
if [ ${root_path[4]} != "${PULP_INSTANCE}-api-svc" ] ; then exit 5 ; fi
