#!/usr/bin/env bash

set -e #fail in case of non zero return

CI_TEST=${CI_TEST:-pulp}
API_ROOT=${API_ROOT:-"/pulp/"}
OPERATOR_NAMESPACE=${OPERATOR_NAMESPACE:-"pulp-operator-system"}

oc -n $OPERATOR_NAMESPACE --kubeconfig=/etc/kubeconfig/config wait --for condition=Pulp-Operator-Finished-Execution pulp/ocp-example --timeout=-1s
