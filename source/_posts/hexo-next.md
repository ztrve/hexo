---
title: Hexo 安装 Next 主题-Hexo建站(四)  
tags: Hexo
date: 2021/2/4  
categories:
- Hexo
keywords: [Hexo,Next,Theme]
description: Hexo 安装 Next 主题
---
在部署完 Hexo 之后, Hexo 自带的主题确实还挺好看的但是为了后期植入评论等插件, 有更方便的支持, 我选择了 [Next Theme](http://theme-next.iissnan.com/getting-started.html)
<!-- more -->

# 安装条件
生产环境(Linux服务器):
- hexo

未安装 hexo 的同学可以参考前两节的内容. 将 hexo 部署起来

# 安装步骤
> 注意: 以下工作空间根目录为 Linux 服务器 hexo 安装路径根目录

#### 下载 Next 主题
这里我选择的是最后一次发布的主线版本.
![](download_last_master_branch.png)

```shell
cd <your_hexo_path>
mkdir themes/next
curl -L https://api.github.com/repos/theme-next/hexo-theme-next/tarball | tar -zxv -C themes/next --strip-components=1
```
>更多版本选择请前往 Next 的 [部署文档](https://github.com/theme-next/hexo-theme-next/blob/master/docs/INSTALLATION.md) 

#### 配置 Next
修改 hexo 根目录下配置文件 _config.yml.  
在配置文件中找到关键字 theme, 并将主题设置为 next (注意这里的next 为 theme/next 的文件夹名)
```shell
# 将原始主题注释掉, 万一想换回来呢
# theme: landscape 
theme: next
```

重启验证:
```shell
docker-compose restart hexo
```

![](restart_hexo01.png)


# 安装图片插件
如果像使用 markdown 一样方便的引用图片, 那么就要安装如下插件. 引用[官方文档](https://hexo.io/zh-cn/docs/asset-folders#Embedding-an-image-using-markdown)上的话
>hexo-renderer-marked 3.1.0 introduced a new option that allows you to embed an image in markdown without using asset_img tag plugin.
> ```shell
> _config.yml
> post_asset_folder: true
> marked:
>   prependRoot: true
>   postAsset: true
> ```
> 
> 
> ```
> Once enabled, an asset image will be automatically resolved to its corresponding post’s path. For example, “image.jpg” is located at “/2020/01/02/foo/image.jpg”, meaning it is an asset image of “/2020/01/02/foo/“ post, ![](image.jpg) will be rendered as <img src="/2020/01/02/foo/image.jpg">.
> ```


