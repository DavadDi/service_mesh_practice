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

# https://blog.turbinelabs.io/setting-up-ssl-with-envoy-f7c5aa06a5ce
# gen ssl cert
openssl req -x509 -newkey rsa:4096 -keyout example-com.key -out example-com.crt -days 365
openssl rsa -in example-com.key -out example-com.key.unsecure

sudo /usr/local/bin/envoy-static -c echo_envoy.yaml -l debug
$ curl -v https://127.0.0.1:443/ -k -H 'Host: example.com'
