---
title: Yapi神器EasyYapi和MybatisPlus工程整合使用及配置文件  
tags: Yapi
date: 2022/6/24
categories:
- Yapi
keywords: [EasyYapi,Yapi]
description: Yapi神器EasyYapi和MybatisPlus工程整合使用及项目配置文件
---

# 前言
EasyApi支持检索项目代码中的注释，注解等信息，自动生成接口文档。
本文主要介绍 EasyApi 的使用和 Mybatis-Plus 及其分页插件 Page 与 EasyApi 整合后，接口文档出现问题的解决方案。    
值得一提的是，EasyYapi的作者对 issue 的维护十分的积极且热心，同学们可以去 github 为他点 star。
注意：EasyApi虽然方便，可以极大减少后端同学的工作量，但是，请各位同学务必对自己接口认真负责的检查。

> 作者 Github 仓库地址: https://github.com/tangcent/easy-yapi

## MybatisPlus整合
关注这部分内容的同学，请直接点击[跳转](#2自定义导出规则适配mybatisplus-page)


# 安装EasyYapi并导出接口文档
原料：
- idea
- Java工程
> 根据本文档配置后依旧无法使用的同学，请移步[官方文档](https://easyyapi.com/setting/ide-setting.html)

## 打开IDEA设置并下载插件EasyYapi
Preferences -》 Plugins -》 EasyYapi
![idea EasyApi插件下载](./plugins-easyYapi.png)

## 登陆Yapi，获取Yapi中项目token
具体项目 -》 设置 -》 token配置 -》 工具标识 -》 token
![获取Yapi项目token](./get-yapi-token.png)

> [Yapi如何部署](https://hellosean1025.github.io/yapi/devops/index.html)

## idea插件配置
server: 配置你的Yapi 服务访问路径  
tokens: 配置 Java 项目名与 Yapi token 之间的映射关系。用 ‘=’ 分割

![idea插件配置](./plugin-easy-yapi-config.png)

## 打开Java项目代码中的Controller，右键空白处，导出接口文档。
- 选择 Export Yapi 即可导出当前类的所有接口文档
- 选择 Export Api 可以导出单个方法的接口文档

![controller导出Yapi](./export_2_yapi.png)


## 校验Yapi导出
去Yapi项目中查看接口是否添加成功
![Yapi导出成功](./yapi_export_success.jpeg)

# 代码侧适配
## 项目结构
项目结构是简单套了一个DDD模型, WEB 接口是对人员的 Crud   
![Java项目结构](./java_project_struct.png)

## 实体类
Po, Qo, Vo都是一样的，不多占用篇幅了。
```java
import lombok.Data;

/**
 * @author: z_true
 * @date: 2022/6/23 14:52
 * @version: 1.0.0
 */
@Data
public class PersonPo {
    /**
     * id
     */
    private Long id;

    /**
     * 姓名
     */
    private String name;
}
```

## 枚举类
人员可以配置性别，这里使用枚举，一会儿可以验证枚举能否正常解析
```java
package com.ztrue.test.springboottest.enums;

import com.baomidou.mybatisplus.annotation.EnumValue;
import com.fasterxml.jackson.annotation.JsonValue;
import lombok.AllArgsConstructor;
import lombok.Getter;

/**
 * @author: z_true
 * @date: 2022/6/23 15:04
 * @version: 1.0.0
 */
@Getter
@AllArgsConstructor
public enum GenderEnums {
    /**
     * 男
     */
    Male(0, "男"),
    /**
     * 女
     */
    Female(1, "女")
    ;

    @EnumValue
    @JsonValue
    private Integer code;
    private String desc;
}
```

## Controller
演示 Controller 代码

``` java
/**
 * 人员
 *
 * @author: z_true
 * @date: 2022/6/23 14:51
 * @version: 1.0.0
 */
@RestController
@RequestMapping
@RequiredArgsConstructor
public class PersonController {
    private final PersonService personService;

    /**
     * 分页
     *
     * 根据分页条件及查询语句，返回封装分页结果集
     *
     * @param page 分页信息
     * @param qo 查询条件
     * @return 分页数据
     */
    @GetMapping
    public Page<PersonVo> page (Page<PersonPo> page, PersonReadQo qo) {
        // 怎么处理的不重要，关键是传入 Qo，结果返回 Vo
        LambdaQueryWrapper<PersonPo> query = new LambdaQueryWrapper<>();
        query.eq(!ObjectUtils.isEmpty(qo.getId()), PersonPo::getId, qo.getId())
                .like(!ObjectUtils.isEmpty(qo.getName()), PersonPo::getName, qo.getName());
        Page<PersonPo> poPage = personService.page(page, query);
        return PageUtil.translatePage(poPage, PersonVo::poToVo);
    }

    /**
     * 列表
     *
     * @param qo qo
     * @return 符合条件的列表
     */
    @GetMapping("/list")
    public List<PersonVo> list (PersonReadQo qo) {
        // 怎么处理的不重要，关键是传入 Qo，结果返回 Vo
        LambdaQueryWrapper<PersonPo> query = new LambdaQueryWrapper<>();
        query.eq(!ObjectUtils.isEmpty(qo.getId()), PersonPo::getId, qo.getId())
                .like(!ObjectUtils.isEmpty(qo.getName()), PersonPo::getName, qo.getName());
        return personService.list(query)
                .stream()
                .map(PersonVo::poToVo)
                .collect(Collectors.toList());
    }

    /**
     * 查询详情
     *
     * 根据人员 id 查询人员详细信息
     *
     * @param id 人员id
     * @return 人员详细信息
     */
    @GetMapping("/{id}")
    public PersonVo getOneDetail (@PathVariable Long id) {
        // 怎么处理的不重要，关键是传入 Qo，结果返回 Vo
        PersonPo po = personService.getById(id);
        return PersonVo.poToVo(po);
    }

    /**
     * 新增
     *
     * @param po 人员信息
     * @return 人员详细信息
     */
    @PostMapping
    public PersonVo save (PersonPo po) {
        personService.save(po);
        return getOneDetail(po.getId());
    }
}
```

## 代码导出规则
请参考  

|Java代码|Yapi内容|
|:-:|:-:|
|类注释|接口分类|
|Method注释第一行|接口名|
|Method注释后几行|接口备注|
|Qo中成员注释|接口Request参数|
|Vo中成员注释|接口Reponse返回值|

> [更多高级用法](https://easyyapi.com/documents/java_doc_demo.html)

## 自定义导出规则适配MybatisPlus-Page
在 Java 项目根目录下，创建 `.easy.api.yml` 文件。  
这份配置文件整合了实际生产使用过程中遇到的 Mybatis-Plus 整合后发生的一系列不易阅读的问题(各位同学可以导出没有配置过 '.easy.api.yml' 的版本试试)。

Github issue:
- [针对参数使用Mybatis-plus下的Page实体导出参数过多的问题](https://github.com/tangcent/easy-yapi/issues/778)

如果有个性化配置需求，请阅读[EasyYapi-可用配置规则](https://easyyapi.com/setting/config-rule.html)

```yaml
# 解决项目中使用 MybatisPlus 中 com.baomidou.mybatisplus.extension.plugins.pagination.Page 的包作返回值，导致导出接口信息过多且杂乱无章的问题
api:
  param:
    parse:
      before: groovy:session.set("isParam",true)
      after: groovy:session.remove("isParam")

json:
  cache:
    # 必须开启
    disable: true
  rule:
    field:
      ignore[com.baomidou.mybatisplus.extension.plugins.pagination.Page#records]: groovy:session.get("isParam")

field:
  ignore:
    # 排除 baomidou.Page<> 接口/对象 中无用的字段
    - orders
    - optimizeCountSql
    - searchCount
    - countId
    - maxLimit
    - optimizeJoinOfCountSql
    # 排除 jackson 和 gson 中的忽略字段
    - "@com.fasterxml.jackson.annotation.JsonIgnore#value"
    - "!@com.google.gson.annotations.Expose#serialize"

  name[com.baomidou.mybatisplus.extension.plugins.pagination.Page#records]: data
#  name:
#    - groovy:(it.defineClass().name() == "com.baomidou.mybatisplus.extension.plugins.pagination.Page"&&it.name()=="records")?"data":null
```

## 验证接口
分页接口
![分页](./web_interface_page.png)
查询列表接口
![列表](./web_interface_list.png)
根据人员 ID 查详情接口    
id是通过解析 java 代码中的 @PathVariable
![详情](./web_interface_get_one_detail.png)
新增接口
![新增](./web_interface_list.png)



