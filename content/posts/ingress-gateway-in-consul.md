---
title: "Creating an ingress gateway in Consul"
summary: "Create ingress gateway using Consul, consul-template and NGINX"
date: 2022-08-19T18:21:36+05:30
draft: false
tags: ["Consul", "devops"]
---

### Introduction

In this post we will go over how we can create an ingress gateway by using Consul's KV, NGINX and consul-template so that traffic from outside the cluster can communicate with specifc internal services.

Here `NGINX` is a place holder, you can also use [Envoy](https://www.envoyproxy.io/), [HAProxy](http://www.haproxy.org/) or any other reverse proxy.

### Architecture overview

![ingress gateway](/ingress_gateway.png#center)

- We have consul-template running as a process under [supervisor](http://supervisord.org/) in the virtual machine, you can also deploy it as a service or a system [job](https://www.nomadproject.io/docs/job-specification/job#type) using [nomad](https://www.nomadproject.io/)
- It periodically checks Consul's KV and service discovery if a new API config is added/removed or a new service is registered/deregistered

In the above architecture Consul KV and consul-template behave as an ad-hoc control plane and NGINX is the data plane[^1].

[^1]: [Control Plane and Data Plane](https://medium.com/envoyproxy/service-mesh-data-plane-vs-control-plane-2774e720f7fc)

### Let's breakdown how each of the components are configured

#### consul-template

First we need to create a consul-template file which will render the NGINX config containing all the necessary API endpoints and NGINX related configuration.

The first block is the upstream block where we loop over the services defined under `ingress-gateway/services` which need to be exposed:

{{< highlight go-text-template >}}
{{ range  $i, $service := key "ingress-gateway/services"  | split  "," -}}
{{ $service_key := printf "%s" $service }}  
upstream {{$service_key}} {
{{ range service $service_key  }}
server {{.Address}}:{{.Port}};
{{else}}
server 127.0.0.1:65535;
{{end}}
}
{{end}}
{{< /highlight >}}

Next we have the main server block which renders the endpoints of the services:

{{< highlight go-text-template >}}
server {
listen {{ $route_data.port }} {{if $route_data.protocol | eq "http2"}}http2{{end}} {{ if $route_data.ssl | eq true }}ssl{{end}};

    server_name {{ printf "%s" .Key  }};

{{range $route := $route_data.routes}}
{{- $service_key := printf "%s" $route.service -}}
location {{$route.path}} {
proxy_pass {{ $route.proxyPassProtocol }}://{{$service_key}}{{$route.proxyPassPathSuffix}};
proxy_http_version 1.1;
proxy_set_header Connection "";
proxy_set_header Host $http_host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
}
{{end}}
{{end}}
}
{{< /highlight >}}

#### Consul KV

The high level KV structure is as follows:

- `ingress-gateway/hosts`: The DNS/hosts entries to where traffic should be routed to
- `ingress-gateway/port`: Port on which NGINX needs to run
- `ingress-gateway/service`: Services that need to be exposed to the outside world, the naming convention is similar to the service registered on the service discovery
- `ingress-gateways/shared`: Any shared nginx config, such as SSL chiper config

The main routing configuration is stored under the hosts folder:

- `ingress-gateway/hosts/hello.example.com`

{{< highlight yaml >}}
port: 80
protocol: http1
ssl: false # If SSL is enabled the certificate block will be rendered
routes:

- path: / # The location block path
  proxyPassProtocol: http # It can be gRPC protocol
  proxyPassPathSuffix: / # Any paths that need to be added to the API
  service: hello-world # The service name registered in Consul SD
  {{< /highlight >}}

This can be further extended to create different paths under the same host or you can also create different host entries under the `hosts` folder.

For example: `ingress-gateway/hosts/foo.example.com`, which can contain it's own API endpoints

#### NGINX

And here is the rendered NGINX config:

{{< highlight nginx >}}
upstream hello-world {
server 127.0.0.1:5000;
}

server {
listen 80;

    server_name hello.example.com;

    location / {
    proxy_pass http://hello-world/;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_set_header Host $http_host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

}
}

server {
listen 80 default*server;
server_name *;
}
{{< /highlight >}}

### Let's see it in action

![ingress gateway](/ingress-gateway.gif#center)

Fun fact the Consul URL that is being used is reverse proxied through the same NGINX running on the VM!

### Full example

You can deploy the whole setup on your laptop and take it for a spin by following these [steps](https://github.com/jsanant/blog-post-examples/tree/main/ingress-gateway)!

### Conclusion

I hope you got an understanding of how to create an ingress-gateway in a Consul using NGINX, Consul KV and consul-template.

If you have any questions or any feedback, please let me know! :)
