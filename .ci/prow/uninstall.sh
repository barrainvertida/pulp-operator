#!/usr/bin/env bash

set -e #fail in case of non zero return

CI_TEST=${CI_TEST:-pulp}
API_ROOT=${API_ROOT:-"/pulp/"}

sed -i 's/kubectl/oc --kubeconfig=\/etc\/kubeconfig\/config/g' Makefile
#make undeploy uninstall
