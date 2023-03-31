---
title: nginx 代理 hexo 及域名配置-Hexo建站(三)  
tags: Hexo
date: 2021/1/24
categories:
- Hexo
keywords: [Hexo,Nginx,docker-compose,docker,域名]
description: docker-compose 部署 hexo 并使用nginx代理及域名配置
---
先前我们将 Hexo 通过 docker-compose 成功将 hexo 部署进了我们的服务器, 拥有域名的同学一定不希望他人在访问 Hexo 时还使用`http://<host>:4000`这种形式. 这一节, 主要演示使用阿里云控制台购买的域名并配置 nginx 代理实现域名访问 Hexo Blog 的实战  
<!-- more -->

# 安装条件
生产环境(Linux服务器):
- [docker](https://www.docker.com/)
- [docker-compose](https://docs.docker.com/compose/install/)

其他:
- [阿里云账号](https://homenew.console.aliyun.com/)
- [域名](https://wanwang.aliyun.com/domain)

以上条件缺一不可. 请自行安装后再进行后续步骤


## 阿里云域名设置
`注意: `这里对域名绑定至服务器不作过多展开, 只介绍如何在阿里云控制台设置解析规则
由于公网 DNS 服务器不是实时刷新的. 有一个刷新周期, 所以我们先进行这一步配置. 这样就可以规避域名没有被 DNS 服务器及时更新, 以至我们的访问失败的问题  
1. 打开我们的阿里云并进入域名管理
   ![](domain-step01.png)
2. 点击我们购置的域名
   ![](domain-step02.png)
3. 进入域名解析
   ![](domain-step03.png)
4. 添加记录
   ![](domain-step04.png)
5. 填写域名前缀信息
   ![](domain-step05.png)
6. 等待 TTL 时间. 阿里云会帮我们将配置自动更新至公网 DNS 服务器

# 配置 nginx
这里我们依旧使用 docker-compose 安装 nginx, [nginx 镜像版本](https://hub.docker.com/_/nginx)可以自由选择, 最好使用官方提供的 docker image.  
> 由于当前演示的 hexo 版本也是有 docker-compose 进行管理的. 如果与笔者配置不一致. 请移步: {% post_link  hexo-docker %}

`声明: `$your_nginx_host 为你宿主机中 nginx 持久化的工作路径. exp: /usr/local/docker/nginx
## 配置 docker-compose.yml
```yaml
version: '2'
services:
  nginx:
    restart: always
    image: nginx:1.16.1
    container_name: nginx
    hostname: nginx
    ports:
      - 80:80
      - 443:443
    links:
      - hexo:hexo # 注意这里需将 hexo 服务的 hostname 注入进去 
    volumes: # 将配置文件及 web 静态文件挂载出来
      # 替换以下 <your_nginx_host>
      - <your_nginx_host>/conf.d:/etc/nginx/conf.d
      - <your_nginx_host>/html:/var/www/html
      - <your_nginx_host>/static:/var/www
      - <your_nginx_host>/nginx.conf:/etc/nginx/nginx.conf
    depends_on:
      - hexo # 需要等 hexo 服务成功启动后再启动 nginx
```

## 配置 nginx/conf.d
```shell
user root;
worker_processes  1;
events {
    worker_connections  1024;
}
http {
    include       mime.types;
    default_type  application/octet-stream;
    keepalive_timeout  65;
    
    # 配置 blog config
    server {
        # http 默认走 80 端口
        listen       80;
        
        # 这里修改 nginx 需要监听的域名, 建议改为非 'www' 开头的其他域名
        # 后期我们就直接通过该域名访问 hexo 服务
        # exp: server_name  blog.diswares.cn;
        server_name  <your_server_name>;
        add_header 'Access-Control-Allow-Origin' '*';

        location / {
                # 上一步, 我们将 hexo 服务的 hostname 注入到容器中了. docker container 在接收到 hostname = 'hexo' 的报文时, 会用它的 DNS 服务器, 自动为我们解析成 hexo 服务的 ip地址. 
                # 所有访问 http://<your_server_name>的流量都会通过 nginx 代理被转发到 http://hexo:4000/ 端口. hexo 服务监听了 4000 就能收到这处流量了.  
                proxy_pass http://hexo:4000/;
        }

        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   html;
        }
    }

}
```


# 成果校验
![](check-success.png)

