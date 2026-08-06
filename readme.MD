# 목표
- CD 구성
- EKS (Auto Mode) 환경의 WEB/WAS 애플리케이션을 ArgoCD로 배포하는 `GitOps CD 저장소`
  - 깃옵스(GitOps)는 깃(Git) 저장소를 단일 진실 공급원(Single Source of Truth)으로 삼아 인프라와 애플리케이션 구성을 코드 형태로 관리하고 `배포를 자동화하는 데브옵스(DevOps) 실천 방법`
  - 제품 : ⁠Argo CD, Flux, ...
  - 특정 내용이 변경되면(계속 감시) 이를 트리거로 하여 배포 함 (CI와 느슨한 연결)
    - kustomization.yaml : ⁠Argo CD 계속 모니터링, CI에서 결과로 수정(CI에서)
- 간단 workflow
  ```
    GitHub Actions Push -> ... -> kustomization.yaml 수정 -> ⁠Argo CD 감지 -> ... -> Pod 순차 교체(배포) -> 서비스 업데이트 (무중단 실시간 반영)
  ```

# 전체 workflow
  ```text
  개발자 Push
  ↓
  devops_tf_k8s_ci / GitHub Actions
  ├─ Terraform·Docker 검증
  ├─ WEB/WAS 이미지 Build
  ├─ ECR Push
  └─ devops_tf_k8s_cd의 이미지 태그를 Git Commit SHA로 변경 <- 태그변경
            ↓
      devops_tf_k8s_cd main
            ↓
      Argo CD 자동 감지
            ↓
      EKS Auto Mode 동기화
            ↓
  Public ALB → WEB Service → WEB Pod → WAS Service → WAS Pod → RDS
  ```
  - Argo CD는 `k8s/overlays/dev` 여기 감시 -> kustomization.yaml 존재
  - CI는 ECR에 업로드된 이미지의 태그(Git Commit SHA는 push 할때마다 변경)를 kustomization.yaml 기록
  - 변경(상태 변경, 비교대상 바꼇다)되면 CD 진행됨

  # 파일 구조 (모니터링, 부하테스트 제외)
  ```text
tf-k8s-cd/

- 점검용
├─ .github/                        : CD 저장소 자체의 파일과 문법 검증
│  ├─ dependabot.yml               : GitHub Actions에서 사용하는 외부 Action 버전을 자동으로 점검
│  └─ workflows/               
│     └─ validate.yml              : CD 저장소에 올라온 Kubernetes 및 Argo CD 설정이 정상적인지 검사하는 GitHub Actions 워크플로

- 실제 배포 담당. 배포 관련 설정 -> ECR 주소 세팅 -> 템플릿 파일로 구성되어 있음 .tpl
├─ argocd/                         : Argo CD가 어떤 저장소와 경로를 감시할지 정의
│  ├─ application.yaml.tpl         : 배포 권한 제한(경계) 정의
│  └─ project.yaml.tpl             : 실제 배포 작업 정의

- 참고용
├─ ci-extension/                   : CI 완료 후 CD 저장소의 이미지 태그를 변경하는 연결 코드
│  └─ ci.yml                       : ci에 사용되는 코드 (참고용)

- 쿠버네티스 구성용 menifest를 리소스별로 모두 쪼갠 파일
├─ k8s/                            : 실제 Kubernetes 리소스 선언
│  ├─ base/                        : 모든 환경에서 공통으로 사용하는 Kubernetes 리소스를 정의
│  │  ├─ ingress-class-params.yaml : EKS Auto Mode가 생성할 AWS Load Balancer의 세부 옵션을 정의 (외부/내부용,동작,생성방식)
│  │  ├─ ingress-class.yaml        : Kubernetes의 IngressClass를 생성. 어떤 컨트롤러를 사용하여 Load Balancer를 만들지 결정
│  │  ├─ ingress.yaml              : 외부 사용자의 요청을 WEB 또는 WAS Service로 전달하는 진입점
│  │  ├─ kustomization.yaml        : base 폴더에 있는 Kubernetes 파일을 하나의 배포 단위로 묶음 -> 조합
│  │  ├─ namespace.yaml            : 애플리케이션이 배포될 Kubernetes Namespace를 생성
│  │  ├─ was-deployment.yaml       : WEB 애플리케이션의 실행 상태를 정의. 이미지, Pod 복제개수, 포트,CPU/메모리 요청/제한량..
│  │  ├─ was-hpa.yaml              : WEB Pod 수를 자동으로 조절
│  │  ├─ was-pdb.yaml              : WEB Pod가 동시에 너무 많이 종료되지 않도록 보호
│  │  ├─ was-service.yaml          : WEB Pod에 고정된 내부 접근 주소를 제공
│  │  ├─ web-deployment.yaml       : WAS 애플리케이션의 실행 상태를 정의. 이미지, Pod 복제개수, 포트,CPU/메모리 요청/제한량..
│  │  ├─ web-hpa.yaml              : WAS Pod 수를 자동으로 조절
│  │  ├─ web-pdb.yaml              : WAS Pod가 동시에 너무 많이 종료되지 않도록 보호
│  │  └─ web-service.yaml          : WAS Pod에 고정된 내부 접근 주소를 제공
│  └─ overlays/
│     └─ dev/
- ECR 주소, 태그 갱신값들이 반영
│        └─ kustomization.yaml     : 개발 환경에서만 필요한 값을 base 위에 덮어씀 => 최종 매니페스트 설정됨


│                                  : WEB/WAS ECR 이미지 주소, 태그, Namespace, 개발 환경 복제 개수/리소스 설정, 공통 라벨
│                                  : `CI가 새 이미지를 ECR에 Push하면 가장 자주 변경되는 파일이 바로 이 파일`
│                                  : `Argo CD는 이 변경을 감지하여 새 버전을 배포`

- 세팅관련 bat|sh
└─ scripts/                        : Argo CD 설치, 설정, 점검, 삭제 자동화
   ├─ bootstrap-cd.bat             : CD 환경 전체 구성을 한 번에 실행하는 대표 스크립트
   ├─ bootstrap-cd.sh
   ├─ check-cd.bat                 : CD 배포 상태를 종합 점검
   ├─ check-cd.sh
   ├─ configure-manifests.bat      : Kubernetes Manifest에 실제 AWS 환경 값을 설정
   ├─ configure-manifests.sh
   ├─ create-rds-secret.bat        : AWS Secrets Manager에 저장된 RDS 접속 정보를 읽어 Kubernetes Secret으로 생성
   ├─ create-rds-secret.sh
   ├─ destroy-cd.bat               : CD를 통해 생성한 리소스를 정리
   ├─ destroy-cd.sh
   ├─ install-argocd.bat           : EKS 클러스터에 Argo CD를 설치
   ├─ install-argocd.sh       
   ├─ open-argocd.bat              : 로컬 컴퓨터에서 Argo CD 웹 화면에 접속할 수 있도록
   ├─ open-argocd.sh
   ├─ render_argocd.py             : Kustomize 설정의 WEB/WAS 이미지 주소와 태그를 자동으로 수정
   ├─ secret_to_env.py             : AWS Secrets Manager가 반환한 JSON 값을 환경변수 형태로 변환
   ├─ setup-ci-cd-link.bat         : tf-k8s-ci와 tf-k8s-cd 저장소를 연결하기 위한 설정을 수행
   ├─ setup-ci-cd-link.sh
   └─ update_images.py             : .tpl 형식으로 작성된 Argo CD 템플릿을 실제 YAML 파일로 변환
```

# Argo CD 폴더 
- Argo CD가 어떤 방식으로 쿠버네티스 리소스를 배포할지 정의
- .tpl 파일 형식은 실제값이 들어가서 세팅되어야 함 -> 템플릿 파일
- 세부
  - CD
    - argocd/application.yaml.tpl
      - 애플리케이션 리소스 정의, 쿠버네티스 배포 위치 지정, 실제 감시할 위치 지정
      - 실제 배포 작업 정의
    - argocd/project.yaml.tpl
      - 애플리케이션 논리적 구분, 배포 권한 제한 선언, ecr정보등 참조
  - 모니터링
    - argocd/monitoring-application.yaml.tpl
      - 프로메테우스, 그라파나등 모니터링관련 설정, CD와 관계 x

# 세팅
- 구분값 교체
  - de-ai-25 => de-ai-xx
  - DE-AI-25 => DE-AI-xx

- ~\k8s\overlays\dev\kustomization.yaml 1회성 수기 수정
  - newName 파트 수정 : 본인 ECR내 web/was 이미지 주소로 변경
  ```
    # 본인 리전 교체
    aws ecr describe-repositories --region ap-northeast-2  --query "repositories[].{Name:repositoryName,URI:repositoryUri}"  --output table
    ---
    ---------------------------------------------------------------------------------------------------------------------------------- 
    |                                                      DescribeRepositories                                                      |
    +--------------------------------------+-----------------------------------------------------------------------------------------+
    |                 Name                 |                                           URI                                           |
    +--------------------------------------+-----------------------------------------------------------------------------------------+
    |  de-ai-12-devops-tf-eks-auto-dev/web |  827913617635.dkr.ecr.us-east-1.amazonaws.com/de-ai-12-devops-tf-eks-auto-dev/web       |
    |  de-ai-12-devops-tf-eks-auto-dev/was |  827913617635.dkr.ecr.us-east-1.amazonaws.com/de-ai-12-devops-tf-eks-auto-dev/was       |
    +--------------------------------------+-----------------------------------------------------------------------------------------+

    # kustomization.yaml 수정
    images:
    - name: WAS_IMAGE
      newName: 827913617635.dkr.ecr.us-east-1.amazonaws.com/de-ai-12-devops-tf-eks-auto-dev/was <- 수정
      newTag: 5f68fff31524
    - name: WEB_IMAGE
      newName: 827913617635.dkr.ecr.us-east-1.amazonaws.com/de-ai-12-devops-tf-eks-auto-dev/web <- 수정
      newTag: 5f68fff31524
  ```

- 점검
  ```
    # 태그 확인 - `dev-latest, 해시값 확인`
    # --repository-name 뒷값 본인것으로 수정후 테스트함
    aws ecr describe-images  --repository-name "de-ai-25-devops-tf-eks-auto-dev/web"  --image-ids imageTag=dev-latest  --region ap-northeast-2  --query "imageDetails[0].imageTags"  --output json
    ---
    [                                                                                                          
      "dev-latest",
      "d8b623986184"
    ] 
    
    aws ecr describe-images  --repository-name "de-ai-25-devops-tf-eks-auto-dev/was"  --image-ids imageTag=dev-latest  --region ap-northeast-2  --query "imageDetails[0].imageTags"  --output json
    ---
    [                                                                                                          
      "d8b623986184",
      "dev-latest"
    ]
  ```

```
  # kustomization.yaml 점검
  kubectl kustomize k8s/overlays/dev
  ---
  오류 없이 잘 출력 OK
```

  ```
    # kustomization.yaml git 비교 (추후 다시 확인)
    git diff -- k8s/overlays/dev/kustomization.yaml
  ```

  ```
    # github actions 잘 작동되는지 점검
    validate.yml = 주석 `체크` 문구 추가
    ---
    스테이징 -> 커밋 -> 푸시 -> git actions 작동 -> 그린라이트 (확인)
  ```

- 로컬 PC의 kubectl과 EKS 클러스터 연결
  ```
    # EKS 클러스터명 조회 (리전 수정)
    aws eks list-clusters  --region us-east-1 --output table

  ```