---
title: Apache APISIX
sidebar_position: 1
---

[Apache APISIX](https://apisix.apache.org) is an open source cloud native API platform that supports the full lifecycle of API management including publishing, traffic management, deployment strategies, and circuit breakers.

## Installing APISIX

Apache APISIX will be installed if the `apisix.enabled` is set to `true` in the `values.yaml` file. The default namespace for Apache APISIX is `apisix`.

## Configure APISIX for multiple Eureka replicas

By default, OBaaS deploys three Eureka replicas. APISIX connects directly to each
Eureka StatefulSet pod so that it can refresh the service registry and fail over
to another Eureka replica.

If you change `eureka.replicas`, also update
`apisix.apisix.discovery.registry.eureka.host`. Include one host entry for every
Eureka replica, numbered from `0` through `eureka.replicas - 1`.

For example, the following values configure five Eureka replicas:

```yaml
eureka:
  replicas: 5

apisix:
  apisix:
    discovery:
      registry:
        eureka:
          host:
            - "http://{{ .Release.Name }}-eureka-0.{{ .Release.Name }}-eureka.{{ .Release.Namespace }}.svc.cluster.local:8761"
            - "http://{{ .Release.Name }}-eureka-1.{{ .Release.Name }}-eureka.{{ .Release.Namespace }}.svc.cluster.local:8761"
            - "http://{{ .Release.Name }}-eureka-2.{{ .Release.Name }}-eureka.{{ .Release.Namespace }}.svc.cluster.local:8761"
            - "http://{{ .Release.Name }}-eureka-3.{{ .Release.Name }}-eureka.{{ .Release.Namespace }}.svc.cluster.local:8761"
            - "http://{{ .Release.Name }}-eureka-4.{{ .Release.Name }}-eureka.{{ .Release.Namespace }}.svc.cluster.local:8761"
          prefix: "/eureka/"
```

Apply the updated values with Helm:

```shell
helm upgrade --install <app-release> helm/infra-charts/obaas \
  --namespace <application-namespace> \
  --create-namespace \
  -f <values-file>
```

Verify that the APISIX ConfigMap includes an endpoint for each Eureka replica:

```shell
kubectl -n <application-namespace> get configmap <app-release>-apisix \
  -o yaml | yq '.data."config.yaml"' \
  | yq '.discovery.registry.eureka.host'
```

The command should return five endpoints for the example configuration, from
`<app-release>-eureka-0` through `<app-release>-eureka-4`.

## Accessing Apache APISIX

Oracle Backend for Microservices and AI deploys the Apache APISIX Gateway and Dashboard in the `apisix` namespace by default. The gateway is exposed via an external load balancer and an ingress controller.

To access the Apache APISIX APIs, use kubectl port-forward to create a secure channel to `service/apisix-admin`. Run the following command to establish the secure tunnel (replace the example namespace `obaas-dev` with the namespace where APISIX is deployed):

```shell
kubectl port-forward -n obaas-dev svc/apisix-admin 9180
```

## Retrieving admin key

To access the APISIX APIs, you need the admin key. Retrieve it with the following command (replace the example namespace `obaas-dev` with the namespace where APISIX is deployed):

**Option 1 - Using yq:**

```bash
kubectl -n obaas-dev get configmap apisix -o yaml | yq '.data."config.yaml"' | yq '.deployment.admin.admin_key[] | select(.name == "admin") | .key'
```

**Option 2 - Manual retrieval:**

If the command above doesn't work:

1. Run: `kubectl get configmap apisix -n obaas-dev -o yaml`
1. Look for the `config.yaml` section
1. Find `deployment.admin.admin_key` and copy the key value

Test the admin key by running a simple curl command; it should return the list of configured routes.

```shell
curl http://127.0.0.1:9180/apisix/admin/routes -H "X-API-key: $admin_key" -X GET
```

## Accessing APISIX Dashboard

:::note
 Note that all functionality is not available in the dashboard. You might need to use the REST APIs
:::

APISIX has an embedded dashboard that can be accessed after a tunnel is established to the `apisix-admin` service. The dashboard is available on [http://localhost:8190/ui](http://localhost:8190/ui). **NOTE:** you need the Admin key to be able to access the dashboard.

![APISIX Dashboard](images/apisix-dashboard.png)

## Configuring APISIX using REST APIs

You can configure and update the APISIX gateway using the provided APIs.  Pleas refer to the [API Documentation](https://apisix.apache.org/docs/apisix/getting-started/README/) for detailed information.

## Tracing requests through APISIX

When SigNoz and APISIX are enabled, OBaaS configures APISIX with the built-in
`opentelemetry` plugin and exports spans to the in-cluster SigNoz OpenTelemetry
collector. APISIX uses the service name `APISIX`, writes its trace context to
JSON access logs, and propagates W3C `traceparent` headers to upstream services.

This makes the plugin available, but it does **not** enable tracing on every
route. Add the plugin to each route that you want to trace, or attach it through
an APISIX GlobalRule when every route should be traced. The OBaaS chart does not
create a tracing route or GlobalRule for you.

For a short validation window, configure an existing or new route with an
always-on sampler:

```yaml
plugins:
  opentelemetry:
    sampler:
      name: always_on
```

For production, use parent-based sampling and sample a fraction of new traces.
This preserves the sampling decision of an incoming trace while reducing the
volume of traces that originate at the gateway:

```yaml
plugins:
  opentelemetry:
    sampler:
      name: parent_base
      options:
        root:
          name: trace_id_ratio
          options:
            fraction: 0.1
```

Apply the route or GlobalRule through your normal APISIX configuration workflow.
If you use the Admin API, retrieve the current object first and preserve its
matching rules, upstream, authentication, and other plugins when adding the
`opentelemetry` block.

The APISIX span is the gateway portion of the trace. To continue the same trace
in an upstream Java service, the service must be OpenTelemetry-instrumented and
configured to export to SigNoz. Instrumentation is described in
[Configure Applications for SigNoz](../observability/configure.md). Kafka and
database spans likewise depend on instrumentation in the backend service; an
APISIX span alone is not proof of a complete end-to-end trace.

### Find APISIX spans and correlated logs in SigNoz

Port-forward the SigNoz UI service, then open [http://localhost:8080](http://localhost:8080):

```shell
kubectl -n <application-namespace> port-forward \
  svc/<app-release>-signoz 8080:8080
```

The OpenTelemetry collector's port `8888` exposes Prometheus metrics. It is not
the SigNoz UI and cannot be used to browse traces.

In **Traces** > **Trace Explorer**, select a recent time range and filter on
service name `APISIX`. To locate one request, filter on its trace ID, for example
the `trace_id` from the APISIX access log. Open a matching trace to inspect the
gateway span and any child spans from instrumented services.

APISIX access logs include `trace_id`, `span_id`, and `traceparent`. In **Logs
Explorer**, filter on the `trace_id` field to find the matching gateway log
entry. This requires the deployed file-log receiver and parser to preserve the
JSON `trace_id` field; if the trace is present but the log is not, verify that
collector configuration separately.

## Using custom plugins

You can install custom plugins in APISIS using the Helm charts.

First, add an `extraConfigMaps` section to the `values.yaml` file that you use with the `obaas` Helm chart.  This will allow you
to create extra arbitrary Config Maps in your cluster as part of the OBaaS installation.  In this config map, add one key (data item)
for each plugin, and include the Lua code for the plugin, as shown in the example below.  You may list as many custom plugins as desired.

```yaml
# ConfigMaps created by the parent chart 
# Each top-level key becomes a ConfigMap name, with nested keys as data entries 
extraConfigMaps: 
  apisix-custom-plugin: 
    abd.lua: | 
      local core = require("apisix.core") 
      
      local plugin_name = "abd" 
      
      local _M = { 
          version = 0.1, 
          priority = 2500, 
          name = plugin_name, 
          schema = {} 
      } 
      
      function _M.access(conf, ctx) 
          core.log.warn("ABD plugin executed") 
      end 
      
      return _M 
    xyz.lua: | 
      local core = require("apisix.core") 
      
      local plugin_name = "xyz" 
      
      local _M = { 
          version = 0.1, 
          priority = 2501, 
          name = plugin_name, 
          schema = {} 
      } 
      
      function _M.access(conf, ctx) 
           core.log.info("XYZ plugin executed") 
      end 
      
      return _M 
```

Next, in the `apisix` section, add a `customPlugins` section to configure the plugins, here is an example that loads the two plugins defined above:

```yaml
# custom plugin 
apisix:
  apisix:
    customPlugins: 
      enabled: true 
      luaPath: "/opts/custom_plugins/?.lua" 
      plugins: 
        - name: "abd" 
          attrs: {} 
          configMap: 
            name: "apisix-custom-plugin" 
            mounts: 
              - key: "abd.lua" 
                path: "/opts/custom_plugins/apisix/plugins/abd.lua" 
        - name: "xyz" 
          attrs: {} 
          configMap: 
            name: "apisix-custom-plugin" 
            mounts: 
              - key: "xyz.lua" 
                path: "/opts/custom_plugins/apisix/plugins/xyz.lua"
```

:::note
 Note that the luaPath does not contain the “apisix/plugins” part because APISIX will automatically add that when it searches for the plugin source code files.
:::

After you have deployed OBaaS, you can access the APISIX admin service to create a route and attach your plugins to the route. Here is an example of a route that uses the `abd` plugin from the example above:

```json
{
  "list": [
    {
      "key": "/apisix/routes/00000000000000000076",
      "value": {
        "uri": "/test-plugin*",
        "methods": [
          "GET"
        ],
        "plugins": {
          "abd": {}
        },
        "update_time": 1772900293,
        "upstream": {
          "discovery_type": "eureka",
          "pass_host": "pass",
          "scheme": "http",
          "hash_on": "vars",
          "tls": {
            "verify": false
          },
          "service_name": "CONFIG-SERVER",
          "type": "roundrobin"
        },
        "priority": 0,
        "id": "00000000000000000076",
        "status": 1,
        "name": "abc",
        "enable_websocket": false,
        "create_time": 1772899208
      },
      "modifiedIndex": 96,
      "createdIndex": 77
    }
  ],
  "total": 1
}
```

You can then hit the uri in the route to test it, for example:

```bash
curl http://IP_ADDRESS:8080/test-plugin/1

{"name":"test-plugin","profiles":["1"],"label":null,"version":null,"state":null,"propertySources":[]}
```

You can check the APISIX pod log to confirm the plugin was executed, in this example by verifying you see the HTTP GET and also the `ADB plugin executed` message that the plugin printed:

```
2026/03/07 16:18:31 [warn] 56#56: *38964 [lua] abd.lua:13: phase_func(): ABD plugin executed, client: 127.0.0.1, server: _, request: "GET /test-plugin/1 HTTP/1.1", host: "localhost:8080" 
127.0.0.1 - - [07/Mar/2026:16:18:31 +0000] localhost:8080 "GET /test-plugin/1 HTTP/1.1" 200 112 0.021 "-" "curl/7.81.0" 10.42.0.48:8080 200 0.022 "http://localhost:8080"
```

:::note
 Note that you do not need to list your custom plugins in the `apisix.apisix.plugins` list in the `values.yaml` for the `obaas` Helm chart, APISIX will automatically
 add your custom plugins to its configuration.
:::
