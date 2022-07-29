#!/usr/bin/env bash

set -ex #fail in case of non zero return

CI_TEST=${CI_TEST:-pulp}
API_ROOT=${API_ROOT:-"/pulp/"}
OPERATOR_NAMESPACE=${OPERATOR_NAMESPACE:-"pulp-operator-system"}
PULP_INSTANCE="ocp-example"
INGRESS_DEFAULT_DOMAIN=$(oc -n $OPERATOR_NAMESPACE get ingresses.config/cluster -o jsonpath={.spec.domain})
ROUTE_HOST=${1:-"${PULP_INSTANCE}.${INGRESS_DEFAULT_DOMAIN}"}

OUTPUT_TEMPLATE='{{.spec.host}} {{.spec.path}} {{.spec.port.targetPort}} {{.spec.tls.termination}} {{.spec.to.name}}'
# check root path
root_path=( $(oc -n $OPERATOR_NAMESPACE get route $PULP_INSTANCE -ogo-template="$OUTPUT_TEMPLATE") )
if [ ${root_path[0]} != "$ROUTE_HOST" ] ; then exit 1 ; fi
if [ ${root_path[1]} != "/" ] ; then exit 2 ; fi
if [ ${root_path[2]} != "api-24817" ] ; then exit 3 ; fi
if [ ${root_path[3]} != "edge" ] ; then exit 4 ; fi
if [ ${root_path[4]} != "${PULP_INSTANCE}-api-svc" ] ; then exit 5 ; fi
echo "[OK] / path ..."

# check /api/v3/ path
api_v3_path=( $(oc -n $OPERATOR_NAMESPACE get route ${PULP_INSTANCE}-api-v3 -ogo-template="$OUTPUT_TEMPLATE") )
if [ ${api_v3_path[0]} != "$ROUTE_HOST" ] ; then exit 6 ; fi
if [ ${api_v3_path[1]} != "/pulp/api/v3/" ] ; then exit 7 ; fi
if [ ${api_v3_path[2]} != "api-24817" ] ; then exit 8 ; fi
if [ ${api_v3_path[3]} != "edge" ] ; then exit 9 ; fi
if [ ${api_v3_path[4]} != "${PULP_INSTANCE}-api-svc" ] ; then exit 10 ; fi
echo "[OK] /api/v3/ path ..."

# check /auth/login
auth_login=( $(oc -n $OPERATOR_NAMESPACE get route ${PULP_INSTANCE}-auth -ogo-template="$OUTPUT_TEMPLATE") )
if [ ${auth_login[0]} != "$ROUTE_HOST" ] ; then exit 11 ; fi
if [ ${auth_login[1]} != "/auth/login/" ] ; then exit 12 ; fi
if [ ${auth_login[2]} != "api-24817" ] ; then exit 13 ; fi
if [ ${auth_login[3]} != "edge" ] ; then exit 14 ; fi
if [ ${auth_login[4]} != "${PULP_INSTANCE}-api-svc" ] ; then exit 15 ; fi
echo "[OK] /auth/login/ path ..."

# check /pulp/content/
core_content=( $(oc -n $OPERATOR_NAMESPACE get route ${PULP_INSTANCE}-content -ogo-template="$OUTPUT_TEMPLATE") )
if [ ${core_content[0]} != "$ROUTE_HOST" ] ; then exit 16 ; fi
if [ ${core_content[1]} != "/pulp/content/" ] ; then exit 17 ; fi
if [ ${core_content[2]} != "content-24816" ] ; then exit 18 ; fi
if [ ${core_content[3]} != "edge" ] ; then exit 19 ; fi
if [ ${core_content[4]} != "${PULP_INSTANCE}-content-svc" ] ; then exit 20 ; fi
echo "[OK] /pulp/content/ path ..."
