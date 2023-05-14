---
title: "Using Zone Awareness in Envoy"
date: 2023-05-13T20:10:33+05:30
summary: " "
draft: false
tags: ["envoy"]
---

### Introduction

In this post we will go over how we can enable Envoy's [zone aware routing](https://www.envoyproxy.io/docs/envoy/latest/faq/configuration/zone_aware_routing) so that microservices within the same AZ can communicate with one another to reduce latency and having a second AZ as a failover.

### Architecture overview

![envoy az](/envoy_az.png#center)

- We are communicating from `Service-A` to `Service-B` spread across two AZs.

### Prerequisites

These are the [prerequisites](https://www.envoyproxy.io/docs/envoy/latest/faq/configuration/zone_aware_routing#envoy-configuration-on-the-source-service) to enable zone aware routing:

- `local_cluster_name` must be set to the source cluster.
- Both definitions of the source and the destination clusters must have [EDS](https://www.envoyproxy.io/docs/envoy/latest/api-v3/config/cluster/v3/cluster.proto#envoy-v3-api-enum-config-cluster-v3-cluster-discoverytype) type.
  - In this example, we will not be using the `EDS` type, we will stick to `STRICT` and `STATIC_DNS` type
- Envoy must be launched with `--service-zone` option which defines the zone for the current host.

#### Cluster Name

As mentioned previously we will need to define the `local_cluster_name` in the envoy config:

{{< highlight yaml >}}
cluster_manager:
  local_cluster_name: service-a
{{< /highlight >}}

The above `local_cluster_name` is defined in `Service-A`. Similarly the `local_cluster_name` will change for `Service-B`.

#### Locality Config

This is the main component that should to be enabled in the cluster section along with region, zone and priority.

{{< highlight yaml >}}
locality:
  region: us-east-1
  zone: us-east-1b
priority: 1
{{< /highlight >}}

Based on the priority envoy will route requests to desired microservice spread across AZs. In this example we have set two priorities - `1` for the same AZ & `2` for different AZ.

#### Cluster block

{{< highlight yaml >}}
- name: service-b
  connect_timeout: 10s
  type: STRICT_DNS
  lb_policy: ROUND_ROBIN
  load_assignment:
    cluster_name: service-b
    endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: service-b-az1
                port_value: 80
        locality:
          region: us-east-1
          zone: us-east-1a
        priority: 1
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: service-b-az2
                port_value: 80
        locality:
          region: us-east-1
          zone: us-east-1b
        priority: 2
{{< /highlight >}}

As you can see here, `Service-B` has two endpoints, one in AZ-1 and the other in AZ-2 when `Service-A` communicates with `Service-B` all requests will go to microservice present in AZ-1 because the priority for it is set to `1`. 

If the priority is set to `1` for `Service-B` in AZ-2 then envoy will send requests to both the endpoints in a round robin fashion.


#### Putting it all together

Now let's put all the individual blocks together:

{{< highlight yaml >}}
cluster_manager:
  local_cluster_name: service-a
 
admin:
  access_log_path: /tmp/admin_access.log
  address:
    socket_address: { address: 0.0.0.0, port_value: 5555 }
 
static_resources:
  listeners:
  - name: service-a
    address:
      socket_address: { address: 0.0.0.0, port_value: 80 }
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: ingress_http
          access_log:
          - name: envoy.file_access_log
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.access_loggers.file.v3.FileAccessLog
              path: "/var/log/service-a.log"
          codec_type: AUTO
          route_config:
            name: wildcard
            virtual_hosts:
            - name: wildcard
              domains: ["*"]
              routes:
              - match: { prefix: "/" }
                route: { cluster: service-a, timeout: 90s }
          http_filters:
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router 
  - name: service-b
    address:
      socket_address: { address: 0.0.0.0, port_value: 8082 }
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: ingress_http
          access_log:
          - name: envoy.file_access_log
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.access_loggers.file.v3.FileAccessLog
              path: "/var/log/service-b.log"
          codec_type: AUTO
          route_config:
            name: wildcard
            virtual_hosts:
            - name: wildcard
              domains: ["*"]
              routes:
              - match: { prefix: "/" }
                route: { cluster: service-b, timeout: 90s }
          http_filters:
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
  clusters:
  - name: service-a
    connect_timeout: 10s
    type: STATIC
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: service-a
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: 0.0.0.0
                port_value: 8081
        locality:
          region: us-east-1
          zone: us-east-1a
  - name: service-b
    connect_timeout: 10s
    type: STRICT_DNS
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: service-b
      endpoints:
        - lb_endpoints:
          - endpoint:
              address:
                socket_address:
                  address: service-b-az1
                  port_value: 80
          locality:
            region: us-east-1
            zone: us-east-1a
          priority: 1

        - lb_endpoints:
          - endpoint:
              address:
                socket_address:
                  address: service-b-az2
                  port_value: 80
          locality:
            region: us-east-1
            zone: us-east-1b
          priority: 2
{{< /highlight >}}

### Demo

![zone awareness](/zone-awareness.gif#center)

- First we send a curl call to `Service-B` via `Service-A`, due to the zone awareness config envoy sends requests to `Service-B` present in AZ-1.
- After I stop the `Service-B` container in AZ-1, the requests automatically failover to `Service-B` in AZ-2.

### Full example

Here is the link to the [setup](https://github.com/jsanant/blog-post-examples/tree/main/envoy-zone-awareness) which was shown in the demo.

### Conclusion

By using zone awareness routing, you can reduce latency between microservices and also keep all the data transfer within the same AZ.
