# Service Mesher v1.0

k8s 集群安装可以参考 [Kubeadm@Centos 7.4 安装 Kubernetes 1.9.1](https://blog.do1618.com/2018/01/19/kubeadm_centos7.4_install/)

## Envoy 代理单 Pod 方案

![image-20180626110547291](http://www.do1618.com/wp-content/uploads/2018/06/envoy_sidecar.png)



通过 Sidecar 方式为当前服务添加 Envoy 代理主要流程：

**目标：**

1. 保证当前的服务调用方式对于以前的调用透明化处理，无感知
   * 保留原有的服务，采用新增加服务的方式
2. 以 sidecar 的方式配置到当前服务的前端，作为代理使用
3. 服务发起访问的时候只通过一次的 Envoy 代理 
   * 发起调用方可以灵活选择是调用原来的服务还是通过 Envoy 代理访问
   * 发起方的调用链不通过 自身的 Envoy 服务，只是通过被调用方的 Envoy 代理

1. Envoy 新增加 Configmap 文件  envoy-echo-config -> echo_envoy.json 

   ```bash
   $ kubectl create namespace envoy-test
   $ kubectl create configmap envoy-echo-config --from-file echo_envoy.json  -n envoy-test
   ```

   echo_envoy.json 文件样例解析：

   ```json
   {
     "listeners": [
       {
         "address": "tcp://0.0.0.0:80",  # 代理工作的端口，在配置 envoy 相关服务的时候对应
         "filters": [
           {
             "type": "read",
             "name": "http_connection_manager",
             "config": {
               "codec_type": "auto",
               "stat_prefix": "ingress_http",
               "route_config": {
                 "virtual_hosts": [
                   {
                     "name": "service",
                     "domains": ["*"],
                     "routes": [
                       {
                         "timeout_ms": 0,
                         "prefix": "/",     # url访问前缀，默认是根目录
                         "cluster": "local_service"
                       }
                     ]
                   }
                 ]
               },
               "filters": [
                 {
                   "type": "decoder",
                   "name": "router",
                   "config": {}
                 }
               ]
             }
           }
         ]
       }
     ],
     "admin": {
       "access_log_path": "/tmp/envoy-access-log",
       "address": "tcp://0.0.0.0:8001"  # envoy 的管理端口
     },
     "cluster_manager": {
       "clusters": [
         {
           "name": "local_service",
           "connect_timeout_ms": 250,
           "type": "static",             # type 为 static
           "lb_type": "round_robin",
           "hosts": [
             {
               "url": "tcp://127.0.0.1:8080" # envoy 后端连接服务的端口，sidecar 方式共享网络
             }
           ]
         }
       ]
     }
   }
   ```

   

2. Pod 的 yaml 文件以 sidecar 方式增加  envoy 镜像，并使用我们上面创建的 envoy 的 config 文件

   ```bash
   $ kubectl create -f echo_server_deployment.yaml
   ```

   

   echo_server_deployment.yaml 内容如下

   ```yaml
   apiVersion: extensions/v1beta1
   kind: Deployment
   metadata:
     annotations:
     labels:
       app: envoy-echo
     name: envoy-echo
     namespace: envoy-test
   spec:
     minReadySeconds: 5
     replicas: 2
     selector:
       matchLabels:
         app: envoy-echo
     strategy:
       rollingUpdate:
         maxSurge: 1
         maxUnavailable: 1
       type: RollingUpdate
     template:
       metadata:
         labels:
           app: envoy-echo
       spec:
         containers:
         - name: envoy
           image: lyft/envoy:latest
           command: ["/usr/local/bin/envoy"]
           args:
           - "--config-path /etc/envoy/echo_envoy.json"  # echo_envoy.json 为上面创建文件名vim称
           ports:
           - containerPort: 80
             protocol: TCP
           volumeMounts:
           - name: envoy-echo-config  
             mountPath: /etc/envoy
         - image: skyscanner/go-httpbin:travis-9
           imagePullPolicy: IfNotPresent
           name: httpbin
           ports:
           - containerPort: 8080
             name: http
             protocol: TCP
           resources: {}
         dnsPolicy: ClusterFirst
         restartPolicy: Always
         schedulerName: default-scheduler
         securityContext: {}
         terminationGracePeriodSeconds: 30
         volumes:
         - name: envoy-echo-config
           configMap:
             name: envoy-echo-config # envoy 配置 configmap 的名称
   ```

   https://github.com/kubernetes/contrib/blob/master/ingress/echoheaders/echo-app.yaml#L26:14

3. 增加 svc 
    ```bash
     $ kubectl create -f echo_envoy_svc.yaml
    ```

   echo_envoy_svc.yaml 文件

```yaml
apiVersion: v1   
kind: Service    
metadata:        
  annotations:   
  labels:        
    app: envoy-echo
  name: envoy-echo
  namespace: envoy-test
spec:            
  externalTrafficPolicy: Cluster
  ports:         
  - name: envoy-echo
    port: 80     
    protocol: TCP
    targetPort: 80
  selector:      
    app: envoy-echo
  sessionAffinity: None
  type: NodePort 
```


4. 测试

    ```bash
    $ kubectl get pod -n envoy-test -o wide
    NAME                          READY     STATUS    RESTARTS   AGE       IP           NODE
    envoy-echo-6f86cf5668-fw6kv   2/2       Running   0          2m        10.10.1.17   k8s-master-dev.teambition.corp
    envoy-echo-6f86cf5668-nrgvb   2/2       Running   0          2m        10.10.1.18   k8s-master-dev.teambition.corp

    $ curl -v 10.10.1.17:8080
    $ curl -v 10.10.1.17/
    ```

   

##Envoy 代理多 Pod 方案

![image-20180626110200635](http://www.do1618.com/wp-content/uploads/2018/06/envoy_sds.png)

**目标：**

1. Pod 前的 Envoy 代理后端可以连接到多个 Pod，实现自己的流量和连接控制
2. 需要增加一个 SDS 服务，用于服务发现，支持 Envoy 动态服务发现拉取



## 参考

1. [在 Kubernetes 中使用 Envoy mesh 教程](https://jimmysong.io/posts/envoy-mesh-in-kubernetes-tutorial)
2. [Envoy Proxy 与微服务实践](http://senlinzhan.github.io/2017/12/25/envoy/)