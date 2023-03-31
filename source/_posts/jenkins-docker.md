---
title: Jenkins结合Docker实现持续集成-Jenkins(一)   
tags: Logback
date: 2021/3/25
categories:
- Jenkins
keywords: [Jenkins,Docker]
description: Docker部署Jenkins实现持续集成  
---
Jenkins作为火了十来年的持续集成(Continuous Integration)工具, 拥有很多优势: 易安装、易配置、完善的测试报告、分布式构建。最值得一提的是它强大完善的第三方插件库，插件库中基本涵盖了你能想到的大部分功能比如RSS/Email/IM集成等等. 本节主要为大家介绍在 CenterOS 下使用 docker 将 Jenkins 成功部署. 并实现 docker in docker 为我们的 Jenkins Image 体积减负, 与宿主机共享一套 docker 环境

> 我的 Jenkins: http://jenkins.diswares.cn/

<!-- more -->
# 部署环境
- CenterOS 7.9
# Jenkins 的本机部署
这里简单介绍一下 Jenkins 的本机部署方式. 一般都是下载一个 Jenkins 的 rpm 包, 将其解压后, 修改配置文件中的 JDK 路径, 然后 service start 就可以正常使用了. 这种方式部署简单, 但是容易将我们的服务器环境变得十分复杂. 所以下面介绍本节重点, Docker 搭建 Jenkins.
# Docker 搭建 Jenkins
## Docker Image 选择
首先打开熟悉的 Docker Hub 去挑选一下合适的镜像
![](docker-hub.png)
这里千万别第一个 Jenkins 官方镜像给误导了. 点进去看之后我们就可以看到弃用通知. 
> This image has been deprecated for over 2 years in favor of the jenkins/jenkins:lts image provided and maintained by the Jenkins Community as part of the project's release process. The images found here have not received updates for over 2 years and will not receive any updates in the future.
> 这个镜像已经被弃用两年多了. 取而代之的是 jenkins/jenkins:lts 由 Jenkins 社区作为项目发布的一部分来提供维护. 这个镜像已经超过两年没有收到更新, 并且以后也不会进行更新!

所以, 这里我们要用 [jenkins/jenkins](https://hub.docker.com/r/jenkins/jenkins) 镜像.   
这个镜像为我们提供了包管理工具 apt-get, 并将工作区存储放到了 /var/jenkins_home 目录下.  

## 改造 Dockerfile(非必须)
### MyDockerfile
在了解了 jenkins/jenkins 的实现后, 我们在后期可能会需要在 docker container 中使用其他环境或者工具. 这里提供一个 demo 方便各位构建自己的 docker image.  
创建文件 MyJenkinsDockerfile
```shell
FROM jenkins/jenkins:lts-jdk11
# if we want to install via apt
USER root
ARG dockerGid=999
RUN echo "docker:x:${dockerGid}:jenkins" >> /etc/group


# RUN  cat /proc/version
# apt mirror
# RUN  sed -i s@/archive.ubuntu.com/@/mirrors.aliyun.com/@g /etc/apt/sources.list
# RUN  sed -i s@/deb.debian.org/@/mirrors.aliyun.com/@g /etc/apt/sources.list
# RUN  sed -i s@/security.debian.org/@/mirrors.aliyun.com/@g /etc/apt/sources.list
# RUN  apt-get clean & apt-get update

# wget
# RUN  apt-get install wget

# yum
# RUN wget http://yum.baseurl.org/download/3.2/yum-3.2.28.tar.gz
# RUN tar zxvf yum-3.2.28.tar.gz

USER jenkins
```

### 构建 Docker Image

同目录下运行下列命令
```shell
docker build --no-cache -t jenkins:ztrue -f ./MyJenkinsDockerfile .
```

## 启动容器
### docker-compose
虽然生产环境肯定不会用 docker-compose 作容器管理, 但是作为一块轻量级的容器编排工具, 还是非常适合我们练手的, 毕竟 docker run 的命令每次启动时都不一定记得住, docker-compose.yml 可以辅助我们操作
```yaml
version: '2'
services:
  jenkins:
    container_name: jenkins
    restart: always
    image: jenkins:ztrue
    # 没有进行 docker file 改造的同学请用官方镜像
    # image: jenkins/jenkins
    ports:
      - 8080:8080
      - 50000:50000
    volumes:
      - /root/.m2:/root/.m2
      - /opt/jenkins/jenkins_home:/var/jenkins_home
      - /var/run/docker.sock:/var/run/docker.sock
      - /usr/bin/docker:/usr/bin/docker
      - /etc/sysconfig/docker:/etc/sysconfig/docker
      - /etc/timezone:/etc/timezone
      - /etc/localtime:/etc/localtime
```

### docker run
```shell
docker run -p 8080:8080 -p 50000:50000 \
-v /root/.m2:/root/.m2 \
-v /opt/jenkins/jenkins_home:/var/jenkins_home \
-v /var/run/docker.sock:/var/run/docker.sock \
-v /usr/bin/docker:/usr/bin/docker \
-v /etc/sysconfig/docker:/etc/sysconfig/docker \
-v /etc/timezone:/etc/timezone \
-v /etc/localtime:/etc/localtime \
jenkins/jenkins:lts-jdk11
```

## docker in docker
一般我们会在项目根目录下编写 Jenkinsfile 来控制编译, 而你的项目可能是由 python、java、go等语言编写的. 那么我们通常会使用 Jenkinsfile 语法中的 agent 来调用一个 docker 镜像给我们的构建(Build)提供环境, 来保证宿主机环境与 Jenkins 环境的隔离.   
`注意: `请提前安装 docker 相关的插件

这个时候, docker Jenkins container 中并没有 docker 环境. 那我们就有两种解决方案: 
- 在 container 中安装一个 docker
- 将宿主机的 docker 环境挂载进 docker container (docker in docker)

对比一下两种解决方案的优势.
- 第一种会隔离性更好, 更有利于我们服务器迁移操作. 但是会显著增加 jenkins docker image 的体积
- 第二种反之

这里为大家介绍第二套解决方案的实际操作  

### 挂载
将 docker 挂载进 docker 容器, 其实只要解决下面两个问题 
### 挂载路径
具体的路径挂载请查看[启动容器](#启动容器)中的挂载配置. 这里为同学们讲解这几个路径的实际作用  
- /var/run/docker.sock: docker 在 linux 上部署后, 拥有 client 和 server. 作为 server 的 Docker Daemon 缺省会监听 /var/run/docker.sock. 我们将这个文件挂载进去, 那么 docker container 中使用的 docker ps、docker run 等命令都会发送给宿主机的 Docker Daemon
- /usr/bin/docker: docker 命令文件
- /etc/sysconfig/docker: docker 的配置文件

### 权限
Jenkins 容器中的用户是 jenkins, 没有权限操作 docker 用户管理的文件, 将其打通就好了

