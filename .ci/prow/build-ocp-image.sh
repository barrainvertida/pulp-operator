#!/usr/bin/env bash

set -ex #fail in case of non zero return

OPERATOR_NAMESPACE=${OPERATOR_NAMESPACE:-"pulp-operator-system"}
BC_NAME="pulp-operator"
GOLANG_BC_NAME="golang-test"

echo "Creating build config $BC_NAME"
oc -n $OPERATOR_NAMESPACE new-build --strategy docker --binary --image quay.io/operator-framework/ansible-operator:v1.22.1 --name $BC_NAME

echo "Waiting bc $BC_NAME sync repo ..."
while true ; do if [ $(oc -n $OPERATOR_NAMESPACE get bc $BC_NAME -oname) ] ; then break ; else sleep 5 ; fi ; done

echo "Starting to build container image ..."
oc -n $OPERATOR_NAMESPACE start-build $BC_NAME --from-dir . --follow

# wait a little bit to the build update its status (sometimes the --follow returns but the build .status.phase was not yet updated)
while [ $(oc -n $OPERATOR_NAMESPACE  get build ${BC_NAME}-$(oc -n $OPERATOR_NAMESPACE get bc $BC_NAME -ojsonpath='{.status.lastVersion}')  -ojsonpath='{.status.phase}') == 'Running' ] ; do
  sleep 2
done

echo "Checking if build completed ..."
if [ $(oc -n $OPERATOR_NAMESPACE  get build ${BC_NAME}-$(oc -n $OPERATOR_NAMESPACE get bc $BC_NAME -ojsonpath='{.status.lastVersion}')  -ojsonpath='{.status.phase}') != 'Complete' ] ; then
  echo "Build failed!"
  exit 1
fi


cd .ci/prow/go/
echo "Building golang test images ..."
oc -n $OPERATOR_NAMESPACE new-build --binary --strategy docker --name $GOLANG_BC_NAME
echo "Waiting bc $BC_NAME sync repo ..."
while true ; do if [ $(oc -n $OPERATOR_NAMESPACE get bc $GOLANG_BC_NAME -oname) ] ; then break ; else sleep 5 ; fi ; done
echo "Starting to build container image ..."
oc -n $OPERATOR_NAMESPACE start-build $GOLANG_BC_NAME --from-dir . --follow
