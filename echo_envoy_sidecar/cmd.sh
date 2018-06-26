#~/bin/bash
# create namespace
kubectl create namespace envoy-test

# create envoy config configmap
kubectl create configmap envoy-echo-config --from-file echo_envoy.json  -n envoy-test

# create echo deployment
kubectl create -f echo_server_deployment.yaml

# create echo_server svc
kubectl create -f echo_envoy_svc.yaml

# show pods
kubectl get pod -n envoy-test -o wide
