#!/usr/bin/env bash

# exit codes:
# 1..5 - a wrong configuration on root route
# 6..10 - a wrong configuration on /api/v3/ route
# 11..15 - a wrong configuration on /auth/login/ route

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

OUTPUT_TEMPLATE='{{.spec.host}} {{.spec.path}} {{.spec.port.targetPort}} {{.spec.tls.termination}} {{.spec.to.name}}'
# check root path
root_path=( $(oc -n $OPERATOR_NAMESPACE get route $PULP_INSTANCE -ogo-template="$OUTPUT_TEMPLATE") )
if [ ${root_path[0]} != "${PULP_INSTANCE}.${INGRESS_DEFAULT_DOMAIN}" ] ; then exit 1 ; fi
if [ ${root_path[1]} != "/" ] ; then exit 2 ; fi
if [ ${root_path[2]} != "api-24817" ] ; then exit 3 ; fi
if [ ${root_path[3]} != "edge" ] ; then exit 4 ; fi
if [ ${root_path[4]} != "${PULP_INSTANCE}-api-svc" ] ; then exit 5 ; fi
echo "/ path OK..."

# check /api/v3/ path
api_v3_path=( $(oc -n $OPERATOR_NAMESPACE get route ${PULP_INSTANCE}-api-v3 -ogo-template="$OUTPUT_TEMPLATE") )
if [ ${api_v3_path[0]} != "${PULP_INSTANCE}.${INGRESS_DEFAULT_DOMAIN}" ] ; then exit 6 ; fi
if [ ${api_v3_path[1]} != "/pulp/api/v3/" ] ; then exit 7 ; fi
if [ ${api_v3_path[2]} != "api-24817" ] ; then exit 8 ; fi
if [ ${api_v3_path[3]} != "edge" ] ; then exit 9 ; fi
if [ ${api_v3_path[4]} != "${PULP_INSTANCE}-api-svc" ] ; then exit 10 ; fi
echo "/api/v3/ path OK..."

# check /auth/login
auth_login=( $(oc -n $OPERATOR_NAMESPACE get route ${PULP_INSTANCE}-auth -ogo-template="$OUTPUT_TEMPLATE") )
if [ ${auth_login[0]} != "${PULP_INSTANCE}.${INGRESS_DEFAULT_DOMAIN}" ] ; then exit 11 ; fi
if [ ${auth_login[1]} != "/auth/login/" ] ; then exit 12 ; fi
if [ ${auth_login[2]} != "api-24817" ] ; then exit 13 ; fi
if [ ${auth_login[3]} != "edge" ] ; then exit 14 ; fi
if [ ${auth_login[4]} != "${PULP_INSTANCE}-api-svc" ] ; then exit 15 ; fi
echo "/auth/login/ path OK..."

# check /pulp/content/
core_content=( $(oc -n $OPERATOR_NAMESPACE get route ${PULP_INSTANCE}-content -ogo-template="$OUTPUT_TEMPLATE") )
if [ ${core_content[0]} != "${PULP_INSTANCE}.${INGRESS_DEFAULT_DOMAIN}" ] ; then exit 16 ; fi
if [ ${core_content[1]} != "/pulp/content/" ] ; then exit 17 ; fi
if [ ${core_content[2]} != "content-24816" ] ; then exit 18 ; fi
if [ ${core_content[3]} != "edge" ] ; then exit 19 ; fi
if [ ${core_content[4]} != "${PULP_INSTANCE}-content-svc" ] ; then exit 20 ; fi
echo "/pulp/content/ path OK..."



echo "All paths OK!"
