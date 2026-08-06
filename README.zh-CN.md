[한국어 원문](./readme.MD) | [中文翻译](./README.zh-CN.md)

# 目标

- 搭建 CD（持续交付）环境。
- 这是一个通过 Argo CD 向 EKS（Auto Mode）环境部署 WEB/WAS 应用的 `GitOps CD 仓库`。
  - GitOps 是一种 DevOps 实践：以 Git 仓库作为单一事实来源（Single Source of Truth），用代码管理基础设施和应用配置，并实现`自动化部署`。
  - 常见产品：Argo CD、Flux 等。
  - 持续监控指定内容，在发生变更时触发部署（与 CI 松耦合）。
    - `kustomization.yaml`：由 Argo CD 持续监控，并由 CI 根据构建结果修改。
- 简要工作流：

  ```text
  GitHub Actions Push -> ... -> 修改 kustomization.yaml -> Argo CD 检测变更 -> ... -> 依次替换 Pod（部署） -> 更新服务（实时无停机生效）
  ```

# 完整工作流

```text
开发者 Push
↓
devops_tf_k8s_ci / GitHub Actions
├─ 验证 Terraform、Docker
├─ 构建 WEB/WAS 镜像
├─ Push 到 ECR
└─ 将 devops_tf_k8s_cd 中的镜像标签改为 Git Commit SHA
          ↓
    devops_tf_k8s_cd main
          ↓
    Argo CD 自动检测
          ↓
    同步至 EKS Auto Mode
          ↓
Public ALB → WEB Service → WEB Pod → WAS Service → WAS Pod → RDS
```

- Argo CD 监控 `k8s/overlays/dev`，其中包含 `kustomization.yaml`。
- CI 将上传至 ECR 的镜像标签写入 `kustomization.yaml`（Git Commit SHA 随每次 Push 改变）。
- 文件状态或比较目标发生变化时，CD 流程启动。

# 文件结构（不含监控和负载测试）

```text
tf-k8s-cd/
├─ .github/                        : 验证 CD 仓库自身的文件和语法
│  ├─ dependabot.yml               : 自动检查 GitHub Actions 使用的外部 Action 版本
│  └─ workflows/
│     └─ validate.yml              : 检查 Kubernetes 和 Argo CD 配置是否正常
├─ argocd/                         : 定义 Argo CD 要监控的仓库和路径
│  ├─ application.yaml.tpl         : 定义部署权限限制（边界）
│  └─ project.yaml.tpl             : 定义实际部署任务
├─ ci-extension/                   : CI 完成后修改 CD 仓库镜像标签的连接代码
│  └─ ci.yml                       : CI 使用的参考代码
├─ k8s/                            : Kubernetes 资源声明
│  ├─ base/                        : 所有环境共用的 Kubernetes 资源
│  │  ├─ ingress-class-params.yaml : EKS Auto Mode 创建 AWS Load Balancer 时使用的详细选项
│  │  ├─ ingress-class.yaml        : 创建 IngressClass 并指定 Load Balancer 控制器
│  │  ├─ ingress.yaml              : 将外部请求转发至 WEB 或 WAS Service 的入口
│  │  ├─ kustomization.yaml        : 将 base 文件组合成一个部署单元
│  │  ├─ namespace.yaml            : 创建应用使用的 Namespace
│  │  ├─ was-deployment.yaml       : 定义 WAS 应用镜像、副本数、端口和资源等
│  │  ├─ was-hpa.yaml              : 自动调整 WAS Pod 数量
│  │  ├─ was-pdb.yaml              : 防止同时终止过多 WAS Pod
│  │  ├─ was-service.yaml          : 为 WAS Pod 提供固定的内部访问地址
│  │  ├─ web-deployment.yaml       : 定义 WEB 应用镜像、副本数、端口和资源等
│  │  ├─ web-hpa.yaml              : 自动调整 WEB Pod 数量
│  │  ├─ web-pdb.yaml              : 防止同时终止过多 WEB Pod
│  │  └─ web-service.yaml          : 为 WEB Pod 提供固定的内部访问地址
│  └─ overlays/dev/
│     └─ kustomization.yaml        : 在 base 上覆盖开发环境配置，生成最终 Manifest
│                                  : 包含 ECR 地址、标签、Namespace、副本数、资源配置和公共标签
│                                  : CI Push 新镜像后最常修改的文件；Argo CD 据此部署新版本
└─ scripts/                        : 自动安装、配置、检查和删除 Argo CD
   ├─ bootstrap-cd.bat/.sh         : 一次性执行完整 CD 环境配置
   ├─ check-cd.bat/.sh             : 综合检查 CD 部署状态
   ├─ configure-manifests.bat/.sh  : 将实际 AWS 环境值写入 Kubernetes Manifest
   ├─ create-rds-secret.bat/.sh    : 从 Secrets Manager 读取 RDS 信息并创建 Secret
   ├─ destroy-cd.bat/.sh           : 清理由 CD 创建的资源
   ├─ install-argocd.bat/.sh       : 在 EKS 中安装 Argo CD
   ├─ open-argocd.bat/.sh          : 从本地访问 Argo CD Web 页面
   ├─ render_argocd.py             : 修改 Kustomize 的 WEB/WAS 镜像地址和标签
   ├─ secret_to_env.py             : 将 Secrets Manager JSON 转为环境变量格式
   ├─ setup-ci-cd-link.bat/.sh     : 连接 tf-k8s-ci 与 tf-k8s-cd 仓库
   └─ update_images.py             : 将 Argo CD .tpl 模板转换为 YAML
```

# Argo CD 目录

- 定义 Argo CD 如何部署 Kubernetes 资源。
- `.tpl` 是模板文件，填入实际值后才能使用。
- CD：
  - `argocd/application.yaml.tpl`：定义 Application 资源、部署位置、监控路径和实际部署任务。
  - `argocd/project.yaml.tpl`：定义应用逻辑分组、部署权限限制，并引用 ECR 信息等。
- 监控：
  - `argocd/monitoring-application.yaml.tpl`：Prometheus、Grafana 等监控配置，与业务 CD 无直接关系。

# 环境设置

## 替换标识值

- `de-ai-12` → `de-ai-xx`
- `DE-AI-25` → `DE-AI-xx`

## 首次修改 `k8s/overlays/dev/kustomization.yaml`

查询本人 ECR 中的 WEB/WAS 镜像地址：

```bash
aws ecr describe-repositories --region us-east-1 --query "repositories[].{Name:repositoryName,URI:repositoryUri}" --output table
```

将查询结果写入 `newName`：

```yaml
images:
- name: WAS_IMAGE
  newName: 827913617635.dkr.ecr.us-east-1.amazonaws.com/de-ai-12-devops-tf-eks-auto-dev/was # 修改
  newTag: 5f68fff31524
- name: WEB_IMAGE
  newName: 827913617635.dkr.ecr.us-east-1.amazonaws.com/de-ai-12-devops-tf-eks-auto-dev/web # 修改
  newTag: 5f68fff31524
```

# 检查

## 检查 ECR 标签

确认存在 `dev-latest` 和哈希值。运行前把仓库名替换为自己的值。

```bash
aws ecr describe-images --repository-name "de-ai-12-devops-tf-eks-auto-dev/web" --image-ids imageTag=dev-latest --region us-east-1 --query "imageDetails[0].imageTags" --output json
aws ecr describe-images --repository-name "de-ai-12-devops-tf-eks-auto-dev/was" --image-ids imageTag=dev-latest --region us-east-1 --query "imageDetails[0].imageTags" --output json
```

预期同时看到 `dev-latest` 和类似 `d8b623986184` 的提交哈希标签。

## 检查 Kustomize 和 Git 变更

```bash
kubectl kustomize k8s/overlays/dev
git diff -- k8s/overlays/dev/kustomization.yaml
```

第一条命令无错误并正常输出即表示检查通过。

## 检查 GitHub Actions

在 `validate.yml` 中添加“检查”注释，然后执行：暂存 → 提交 → Push → 确认 GitHub Actions 运行且显示绿灯。

# 将本地 kubectl 连接至 EKS

```bash
# 查询集群名称（修改区域）
aws eks list-clusters --region us-east-1 --output table

# 建立连接（替换集群名称）
aws eks update-kubeconfig --region us-east-1 --name de-ai-12-devops-tf-eks-auto-dev

# 确认 kubectl 可以访问集群
kubectl get namespaces
```

应能看到 `de-ai-12`、`default`、`kube-system` 等 Namespace 处于 `Active` 状态。

# 安装 Argo CD

```powershell
# 安装
.\scripts\bootstrap-cd.bat ucoccto/devops_tf_k8s_cd

# 检查 Argo CD Pod
kubectl get pods -n argocd

# 检查 Argo CD 与 GitHub 仓库的连接状态
kubectl get applications -n argocd
```

Argo CD 以 Pod 形式运行在 Kubernetes 集群中并负责 CD。Application 正常示例：

```text
NAME       SYNC STATUS   HEALTH STATUS
de-ai-12   OutOfSync     Healthy
```

如果显示 `Unknown`，可能需要增加认证步骤；私有仓库还需要配置访问凭据。

# 检查当前状态

```bash
# 检查 Pod
kubectl get pods -n de-ai-12

# 检查 Ingress 和 ALB 地址
kubectl get ingress -n de-ai-12

# 检查当前部署的镜像
kubectl get deployment web was -n de-ai-12 -o jsonpath="{range .items[*]}{.metadata.name}{': '}{.spec.template.spec.containers[0].image}{'\n'}{end}"
```

正常情况下 WEB/WAS Pod 均为 `Running`，Ingress 显示 ALB 地址，镜像标签当前为 `dev-latest`。

# 连接 CI 与 CD 仓库

- 取消 CI 仓库 `ci.yaml` 中 `update-cd:` Job 以下内容的注释。
- 设置 `CD_REPOSITORY`：

  ```bash
  gh variable set CD_REPOSITORY --repo ucoccto/devops_tf_k8s_ci --body "ucoccto/devops_tf_k8s_cd"
  ```

- 设置 `CD_REPOSITORY_TOKEN`：

  ```bash
  gh auth token | gh secret set CD_REPOSITORY_TOKEN --repo ucoccto/devops_tf_k8s_ci
  ```

# Argo CD 登录信息

```text
Argo CD 地址     : https://localhost:8080
Argo CD 用户名   : admin
Argo CD 密码     : 61Ety9W8Ev00hanX
```

# 访问网站

```text
kubectl describe ingress public-alb -n de-ai-12
kubectl describe ingress public-alb -n de-ai-12
---

访问：http://k8s-deai12-publical-83d23986ad-330339377.us-east-1.elb.amazonaws.com/

在 CI 仓库中 Push 开发代码 -> 稍等片刻后访问网站 -> 可以看到变更已经生效
# Kubernetes 配置修改由 CD 负责
# 基础设施修改由 CI 负责
# 代码修改由 CI 负责
```
