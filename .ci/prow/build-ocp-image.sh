#!/usr/bin/env bash

set -e #fail in case of non zero return

OPERATOR_NAMESPACE=${OPERATOR_NAMESPACE:-"pulp-operator-system"}

oc -n $OPERATOR_NAMESPACE new-build --strategy docker --binary --image quay.io/operator-framework/ansible-operator:v1.22.1 --name pulp-operator
oc -n $OPERATOR_NAMESPACE start-build pulp-operator --from-dir  . --follow

if [[ ! $(oc -n $OPERATOR_NAMESPACE get imagestream) ]] ; then
  echo "Build failed!"
  exit 1
fi
