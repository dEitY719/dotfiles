# Setup.sh 동작 일관성 검토 - 보안 및 NPM 설정 처리

**검토 대상**:

- 최근 커밋: `156541c` (npm-config 프록시 표시), `7150b8b` (npm 설정 자동화)
- 검토 파일: `shell-common/env/security.local.example`, `shell-common/tools/integrations/npm.local.example`, `shell-common/env/proxy.local.example` (3개 파일)
- 처리 코드: `shell-common/setup.sh`의 `setup_local_files()` 함수

---

## 1️⃣ 현재 상태 분석

### 1.1 동작 과정 비교

#### security.local 처리 방식

```bash
# setup.sh 라인 98-128
if [ -f "$security_local" ]; then
    case "$environment" in
        internal)
            # Comment out Option 1 (한 줄)
            sed -i 's/^CA_CERT="\/usr\/local\/share/#CA_CERT="\/usr\/local\/share/' "$security_local"
            # Uncomment Option 2 (한 줄)
            sed -i 's/^#CA_CERT="\/etc\/ssl\/certs/CA_CERT="\/etc\/ssl\/certs/' "$security_local"
        ;;
        external)
            # Uncomment Option 1 (한 줄)
            sed -i 's/^#CA_CERT="\/usr\/local\/share/CA_CERT="\/usr\/local\/share/' "$security_local"
            # Comment out Option 2 (한 줄)
            sed -i 's/^CA_CERT="\/etc\/ssl\/certs/#CA_CERT="\/etc\/ssl\/certs/' "$security_local"
        ;;
    esac
fi
```

**특징**:

- ✓ 매우 간단한 구조 (1개 변수: `CA_CERT`)
- ✓ 직관적인 sed 명령 (단순 string replacement)
- ✓ 명확한 의도 파악 용이

#### npm.local 처리 방식

```bash
# setup.sh 라인 130-190
if [ -f "$npm_local" ]; then
    case "$environment" in
        internal)
            # Comment out Option 1 (6개 변수)
            sed -i '/^    # === Option1:/,/^    # === Option2:/ {
                /DESIRED_REGISTRY=.*npmjs/s/^    /    # /
                /DESIRED_CAFILE=.*samsungsemi/s/^    /    # /
                /DESIRED_STRICT_SSL="true"/s/^    /    # /
                /DESIRED_PROXY=""/s/^    /    # /
                /DESIRED_HTTPS_PROXY=""/s/^    /    # /
                /DESIRED_NOPROXY=""/s/^    /    # /
            }' "$npm_local"
            # Uncomment Option 2 (6개 변수)
            sed -i '/^    # === Option2:/,/^    # === 공통 설정/ {
                /DESIRED_REGISTRY=.*artifactory/s/^    # /    /
                /DESIRED_CAFILE=.*ca-certificates.crt/s/^    # /    /
                /DESIRED_STRICT_SSL="false"/s/^    # /    /
                /DESIRED_PROXY=.*12.26/s/^    # /    /
                /DESIRED_HTTPS_PROXY=.*12.26/s/^    # /    /
                /DESIRED_NOPROXY=.*10.229/s/^    # /    /
            }' "$npm_local"
        ;;
        external)
            # 동일한 6개 변수 toggle (반복)
        ;;
    esac
fi
```

**특징**:

- ✗ 복잡한 구조 (6개 변수: DESIRED_* 들)
- ✗ 복잡한 sed 문법 (range + nested replacement)
- ✗ 유지보수 어려움 (각 변수를 정확히 명시해야 함)

#### proxy.local 처리 방식

```bash
# setup.sh 라인 85-93
case "$environment" in
    external)
        # External company PC (VPN): skip proxy.local.example
        # Reason: proxy.local.sh is only valid for internal (2번 option)
        # VPN environment uses direct connection without proxy
        if [ "$basename_file" = "proxy.local.example" ]; then
            print_info "Skipped (not needed for VPN): ${basename_file}"
        else
            cp "$example_file" "$local_file"
        fi
    ;;
esac
```

**특징**:

- ⚠️ 선택적 생성 (external에서만 스킵)
- ✓ 단순한 구조 (4개 변수: http_proxy, https_proxy, no_proxy 등)
- ✓ 환경별 Option toggle 없음 (단일 설정만 포함)
- ✗ 하지만 조건부 로직이 이상함 (proxy.local은 internal 환경용인데 external에서 스킵)

### 1.2 문제점 요약

| 항목 | security.local | npm.local | proxy.local | 평가 |
| --- | --- | --- | --- | --- |
| **변수 개수** | 1개 | 6개 | 4개 | ✗ 불일치 |
| **sed 명령 복잡도** | 단순 (1줄) | 복잡 (6줄 + range) | 없음 (조건부 스킵) | ✗ 불일치 |
| **환경별 Option** | 2개 | 2개 | 0개 (단일) | ✗ 불일치 |
| **생성 조건** | 항상 생성 | 항상 생성 | internal만 생성 | ✗ 불일치 |
| **코드 가독성** | 높음 | 낮음 | 낮음 (조건부) | ✗ 문제 |

---

## 2️⃣ SOLID 원칙 준수 현황

### 2.1 Single Responsibility Principle (SRP) 위반 ⚠️

`setup_local_files()` 함수가 너무 많은 책임을 가짐:

```bash
setup_local_files() {
    local environment="$1"

    # 책임 1: .local.example → .local.sh 파일 복사
    for example_file in "${local_examples[@]}"; do
        cp "$example_file" "$local_file"
    done

    # 책임 2: security.local.sh 환경별 설정
    if [ -f "$security_local" ]; then
        sed -i ...  # Option toggle
    fi

    # 책임 3: npm.local.sh 환경별 설정
    if [ -f "$npm_local" ]; then
        sed -i ...  # 6개 변수 toggle
    fi
}
```

**문제**:

- 함수가 3개 이상의 서로 다른 책임을 처리
- 각 설정 파일의 처리 로직이 한 함수에 embedded되어 있음
- 새로운 .local 파일 추가 시 함수를 계속 수정해야 함

**개선 방안**:

```bash
# 각 설정별로 독립적인 함수 분리
setup_security_config() { ... }
setup_npm_config() { ... }
setup_python_config() { ... }  # 향후 추가 가능

setup_local_files() {
    # 기본 파일 복사만 담당
    # 각 설정 함수 호출
}
```

### 2.2 Open/Closed Principle (OCP) 위반 ⚠️

새로운 .local.example 파일을 추가하려면 setup.sh를 직접 수정해야 함:

```bash
# 현재: proxy.local.example 추가 시
if [ "$basename_file" = "proxy.local.example" ]; then
    # 특수 처리...
fi
```

**문제**:

- 새로운 설정 파일마다 setup.sh 코드 수정 필요
- 확장에 닫혀있는 구조

**개선 방안**:

```bash
# 설정 파일별 메타데이터 정의
declare -A CONFIG_HANDLERS=(
    ["security.local"]="handle_security_config"
    ["npm.local"]="handle_npm_config"
)

# 동적으로 처리
for config_name in "${!CONFIG_HANDLERS[@]}"; do
    handler_func="${CONFIG_HANDLERS[$config_name]}"
    $handler_func "$environment"
done
```

### 2.3 Don't Repeat Yourself (DRY) 위반 ⚠️

#### Issue 1: Comment/Uncomment 로직 중복

```bash
# security.local에서
sed -i 's/^CA_CERT="../#CA_CERT="../'          # Comment
sed -i 's/^#CA_CERT=/CA_CERT=/'                # Uncomment

# npm.local에서
sed -i '/^    /s/^    /    # /'                # Comment
sed -i '/^    # /s/^    # /    /'              # Uncomment
```

#### Issue 2: 환경별 설정 로직 중복

```bash
case "$environment" in
    internal)
        # security.local: Option 2 활성화
        # npm.local: Option 2 활성화
    ;;
    external)
        # security.local: Option 1 활성화
        # npm.local: Option 1 활성화
    ;;
esac
```

**공통 패턴**: 모든 설정이 동일하게 Option1(external) ↔ Option2(internal) toggle

---

## 3️⃣ SSOT (Single Source of Truth) 원칙 위반 ⚠️

### 3.1 설정값 중복 정의

**문제**: 설정값이 여러 곳에서 중복 정의되거나 분산됨

#### security.local.example (템플릿)

```bash
# CA_CERT 설정 (1개 변수, 2개 Option)
CA_CERT="/usr/local/share/ca-certificates/samsungsemi-prx.com.crt"
#CA_CERT="/etc/ssl/certs/ca-certificates.crt"
```

#### npm.local.example (템플릿)

```bash
# Option 1 설정
DESIRED_REGISTRY="https://registry.npmjs.org/"
DESIRED_CAFILE="/usr/local/share/ca-certificates/samsungsemi-prx.com.crt"
DESIRED_PROXY=""

# Option 2 설정 (주석)
# DESIRED_REGISTRY="http://repo.samsungds.net:8081/..."
# DESIRED_CAFILE="/etc/ssl/certs/ca-certificates.crt"
# DESIRED_PROXY="http://12.26.204.100:8080"
```

#### proxy.local.example (템플릿)

```bash
# 프록시 설정 (4개 변수, Option 없음)
export http_proxy="http://12.26.204.100:8080/"
export https_proxy="http://12.26.204.100:8080/"
export no_proxy="10.229.95.200,10.229.95.220,..."
```

#### setup.sh (자동화)

```bash
# npm.local 설정
sed -i '/DESIRED_REGISTRY=.*npmjs/s/^    /    # /'
sed -i '/DESIRED_REGISTRY=.*artifactory/s/^    # /    /'

# proxy.local 조건부 스킵 (setup.sh 라인 88-91)
if [ "$basename_file" = "proxy.local.example" ]; then
    print_info "Skipped (not needed for VPN): ${basename_file}"
fi
```

**문제**:
- npm.local.example과 setup.sh에서 동일한 값이 반복 정의됨
- 유지보수 시 두 곳을 모두 수정해야 함
- 불일치 가능성이 있음

### 3.2 옵션 정보의 분산

| 정보 | security.local | npm.local | proxy.local | 문제 |
|------|---|---|---|---|
| Option 개수 | 2개 | 2개 | 0개 (단일) | ✗ 불일치 |
| 설정값 정의 위치 | template | template | template | ✓ 명확 |
| setup.sh 처리 | sed toggle | sed toggle | 조건부 스킵 | ✗ 불일치 |
| 프록시 변경 시 | ✓ 1곳 수정 | ✓ 2곳 수정 | ✓ 1곳 수정 | ⚠️ 불일치 |
| 환경별 로직 | 동일 | 동일 | 다름 | ✗ 일관성 부재 |

### 3.3 실제 유지보수 시나리오

**시나리오 1**: 회사 프록시 주소 변경 (12.26.204.100:8080 → 10.0.0.1:3128)

**필요한 수정**:

1. npm.local.example 수정 (Option 2):
```bash
# DESIRED_PROXY="http://10.0.0.1:3128"
# DESIRED_HTTPS_PROXY="http://10.0.0.1:3128"
```

2. setup.sh 수정 (sed 패턴 변경):
```bash
sed -i '/DESIRED_PROXY=.*12.26/s/^    # /    /'          # ← 패턴 변경 필요
sed -i '/DESIRED_HTTPS_PROXY=.*12.26/s/^    # /    /'    # ← 패턴 변경 필요
```

3. proxy.local.example 수정:
```bash
export http_proxy="http://10.0.0.1:3128/"
export https_proxy="http://10.0.0.1:3128/"
```

**문제점**:
- npm.local: **2곳** 수정 필요 (template + setup.sh 패턴)
- proxy.local: **1곳** 수정 필요
- 프로토콜이 다름 (sed toggle vs 단순 업데이트)

**시나리오 2**: proxy.local 추가 프록시 주소 필요

proxy.local은 Option이 없으므로:
- 새 프록시 주소를 위해서는 Option을 **새로 추가**해야 함
- 이는 template 구조와 setup.sh 로직을 동시에 수정 필요
- npm.local과 달리 구조가 다르므로 매우 번거로움

**근본 원인**: 각 파일의 처리 방식이 불일치하고, 설정값의 정의와 적용 로직이 분산됨

---

## 4️⃣ 현재 구조의 한계

### 4.1 sed 기반 자동화의 문제점

#### Issue 1: 정규식 유지보수 어려움

```bash
# 정확한 패턴 일치 필요
sed -i '/DESIRED_PROXY=.*12.26/s/^    # /    /'
       # ← 만약 "12.26.204.100:8080" 형식이 변경되면?
       # ← 정규식을 다시 작성해야 함
```

#### Issue 2: 파일 형식 변경에 취약

```bash
# 들여쓰기 변경 시
sed -i '/^    # === Option1:/,/^    # === Option2:/ {'
#      # ← "    " (4칸) 가정
# 만약 탭으로 변경되면 패턴 불일치
```

#### Issue 3: 확인 어려움

```bash
# 설정 후 확인 불가능
npm config get registry  # 실제로 설정되었는지 확인
npm config get proxy     # 설정 과정에서 누락되지 않았는지 확인?
```

### 4.2 파일 구조의 일관성 부재

#### security.local.example

```bash
# Template 스타일: 정적 인라인 옵션
# Option 1: ... (주석 + 설명)
CA_CERT="/usr/local/share/..."

# Option 2: ... (주석 + 설명)
#CA_CERT="/etc/ssl/..."
```

#### npm.local.example

```bash
# Configuration 스타일: 동적 변수 + 옵션
# Option 1: ... (여러 줄의 DESIRED_* 변수)
DESIRED_REGISTRY="..."
DESIRED_CAFILE="..."

# Option 2: ... (여러 줄의 DESIRED_* 변수 commented)
# DESIRED_REGISTRY="..."
# DESIRED_CAFILE="..."

# 실제 적용 로직
if command -v npm >/dev/null 2>&1; then
    npm config set registry "$DESIRED_REGISTRY"
    npm config set cafile "$DESIRED_CAFILE"
fi
```

#### proxy.local.example

```bash
# Simple Export 스타일: 단순 환경변수 정의
# (Option 없음, internal 환경용만)
export http_proxy="http://12.26.204.100:8080/"
export https_proxy="http://12.26.204.100:8080/"
export no_proxy="10.229.95.200,..."
```

**문제**: 세 파일의 구조가 완전히 다름
- security.local: 단일 변수 (sed toggle)
- npm.local: 다중 변수 + 적용 로직 (sed toggle)
- proxy.local: 단순 환경변수 (조건부 스킵, Option 없음)

---

## 5️⃣ 리팩토링 제안

### 5.1 핵심 원칙

1. **SSOT 확보**: 설정값은 한 곳에서만 정의
2. **책임 분리**: 각 설정 파일별 독립적인 처리 로직
3. **일관된 구조**: 모든 .local.example 파일이 동일한 패턴 따름
4. **명확한 의도**: sed 조작 없이도 설정값의 의미가 명확함

### 5.2 리팩토링 방안 A: 설정 파일 계층화 (권장)

#### 구조 변경

```
shell-common/
├── config/
│   └── environments.conf          # SSOT: 환경별 설정값 정의
│
├── env/
│   ├── security.local.example      # 템플릿 (변수만 정의)
│   └── security.local.sh           # 자동 생성됨 (setup.sh가 env.conf에서 읽어 생성)
│
└── tools/integrations/
    ├── npm.local.example           # 템플릿 (변수만 정의)
    └── npm.local.sh                # 자동 생성됨
```

#### environments.conf (새로 생성 - SSOT)

```bash
# Single Source of Truth: 환경별 설정값 정의 (3개 파일 통합)
# format: ENVIRONMENT:SETTING_NAME=VALUE

# === Security (CA Certificate) ===
external:CA_CERT="/usr/local/share/ca-certificates/samsungsemi-prx.com.crt"
internal:CA_CERT="/etc/ssl/certs/ca-certificates.crt"

# === NPM Configuration (Option 1: External) ===
external:NPM_REGISTRY="https://registry.npmjs.org/"
external:NPM_CAFILE="/usr/local/share/ca-certificates/samsungsemi-prx.com.crt"
external:NPM_STRICT_SSL="true"
external:NPM_PROXY=""
external:NPM_HTTPS_PROXY=""
external:NPM_NOPROXY=""

# === NPM Configuration (Option 2: Internal) ===
internal:NPM_REGISTRY="http://repo.samsungds.net:8081/artifactory/api/npm/npm/"
internal:NPM_CAFILE="/etc/ssl/certs/ca-certificates.crt"
internal:NPM_STRICT_SSL="false"
internal:NPM_PROXY="http://12.26.204.100:8080"
internal:NPM_HTTPS_PROXY="http://12.26.204.100:8080"
internal:NPM_NOPROXY="10.229.95.200,10.229.95.220,..."

# === Proxy Configuration (Internal Only) ===
internal:PROXY_HTTP="http://12.26.204.100:8080/"
internal:PROXY_HTTPS="http://12.26.204.100:8080/"
internal:PROXY_NO="10.229.95.200,10.229.95.220,..."
```

#### setup.sh 개선

```bash
# environments.conf에서 값을 읽어 .local.sh 파일 자동 생성
setup_environment_config() {
    local environment="$1"
    local config_file="$SHELL_COMMON_DIR/config/environments.conf"

    # security.local.sh 생성
    {
        cat shell-common/env/security.local.example
        echo "# Auto-configured for: $environment"
        grep "^${environment}:CA_CERT=" "$config_file" | cut -d: -f2-
    } > shell-common/env/security.local.sh

    # npm.local.sh 생성
    {
        cat shell-common/tools/integrations/npm.local.example
        echo "# Auto-configured for: $environment"
        grep "^${environment}:NPM_" "$config_file" | cut -d: -f2- | \
        sed 's/NPM_/DESIRED_/g'
    } > shell-common/tools/integrations/npm.local.sh

    # proxy.local.sh 생성 (internal 환경만)
    if [ "$environment" = "internal" ]; then
        {
            cat shell-common/env/proxy.local.example
            echo "# Auto-configured for: $environment"
            grep "^${environment}:PROXY_" "$config_file" | \
            sed 's/PROXY_HTTP/http_proxy/; s/PROXY_HTTPS/https_proxy/; s/PROXY_NO/no_proxy/' | \
            cut -d: -f2-
        } > shell-common/env/proxy.local.sh
    fi
}
```

**장점**:
- ✓ SSOT 확보 (environments.conf가 유일한 진실)
- ✓ sed 조작 제거 (파일 생성으로 대체)
- ✓ 3개 파일 통합 관리
- ✓ 새로운 설정 추가 용이 (environments.conf만 수정)
- ✓ 설정값 변경 시 한 곳만 수정

### 5.3 리팩토링 방안 B: 설정 파일 표준화

#### 모든 .local.example을 동일한 구조로 통일

**security.local.example** (현재 ✓ 좋음)
```bash
# 템플릿 파일: 변수 정의만
CA_CERT="/usr/local/share/ca-certificates/samsungsemi-prx.com.crt"
```

**npm.local.example** (개선 필요)
```bash
# Before: 템플릿에서 설정 로직까지 포함
DESIRED_REGISTRY="..."
if command -v npm; then
    npm config set ...
fi

# After: 순수 변수 정의만
DESIRED_REGISTRY="https://registry.npmjs.org/"
DESIRED_CAFILE="/usr/local/share/ca-certificates/samsungsemi-prx.com.crt"
DESIRED_PROXY=""
```

**새로운 npm-apply.sh** (설정 적용 로직)
```bash
#!/bin/bash
# npm 설정을 npm.local.sh에서 읽어 실제로 적용

if [ -f "npm.local.sh" ]; then
    source npm.local.sh

    [ -n "$DESIRED_REGISTRY" ] && npm config set registry "$DESIRED_REGISTRY"
    [ -n "$DESIRED_CAFILE" ] && npm config set cafile "$DESIRED_CAFILE"
    ...
fi
```

**장점**:
- ✓ 모든 .local.example 파일이 순수 템플릿 역할
- ✓ 설정 로직이 별도의 apply 스크립트로 분리
- ✓ 각 설정별로 일관된 구조

### 5.4 즉시 적용 가능한 개선 (Quick Win)

#### 개선 1: 설정값 추출 및 주석화

```bash
# setup.sh 내에 명시적 변수 정의
declare -A SECURITY_CONFIG=(
    [external]="/usr/local/share/ca-certificates/samsungsemi-prx.com.crt"
    [internal]="/etc/ssl/certs/ca-certificates.crt"
)

declare -A NPM_REGISTRY=(
    [external]="https://registry.npmjs.org/"
    [internal]="http://repo.samsungds.net:8081/..."
)

# sed 패턴 대신 변수 사용
CA_CERT="${SECURITY_CONFIG[$environment]}"
```

#### 개선 2: 함수 분리

```bash
# 현재: setup_local_files() 함수가 모든 것을 처리

# 개선:
apply_security_config() { ... }
apply_npm_config() { ... }

setup_local_files() {
    for example_file in "${local_examples[@]}"; do
        cp "$example_file" "$local_file"
    done

    # 각 설정별 함수 호출
    apply_security_config "$environment"
    apply_npm_config "$environment"
}
```

#### 개선 3: 검증 로직 추가

```bash
# 설정 후 실제로 적용되었는지 검증
verify_security_config() {
    local expected_ca="$1"
    # NODE_EXTRA_CA_CERTS가 설정되었는지 확인
    if [ "$NODE_EXTRA_CA_CERTS" = "$expected_ca" ]; then
        print_success "Security config verified"
    else
        print_info "Warning: Security config may not be applied correctly"
    fi
}

verify_npm_config() {
    local expected_registry="$1"
    # npm config get으로 실제 설정값 확인
    local actual="$(npm config get registry 2>/dev/null)"
    if [ "$actual" = "$expected_registry" ]; then
        print_success "NPM config verified"
    else
        print_info "Warning: npm config set이 자동 적용되지 않을 수 있습니다"
    fi
}
```

---

## 6️⃣ 리팩토링 후 setup.sh 구조 개선

### 6.1 cleanup_local_files() 함수 제거 (SOLID 원칙)

#### 현재 동작 (불필요한 복잡성)

```bash
main() {
    case "$choice" in
        1)
            cleanup_local_files              # ← 필요함
            setup_local_files 호출 안함
            ;;
        2)
            cleanup_local_files              # ← cleanup 후 setup (2단계)
            setup_local_files "internal"
            ;;
        3)
            cleanup_local_files              # ← cleanup 후 setup (2단계)
            setup_local_files "external"
            ;;
    esac
}
```

#### 리팩토링 후 동작 (간결함)

```bash
main() {
    case "$choice" in
        1)
            remove_local_files               # ← 단순 삭제만
            ;;
        2)
            setup_environment_config "internal"   # ← 1단계 (자동 생성)
            ;;
        3)
            setup_environment_config "external"   # ← 1단계 (자동 생성)
            ;;
    esac
}
```

**개선 이유**:
- ✓ cleanup_local_files() 제거 (SRP 원칙)
  - 현재: cleanup과 setup이 결합된 복합 책임
  - 개선: setup만 담당 (생성이 자동으로 덮어쓰기)
- ✓ 단계 감소: 2단계 (cleanup → setup) → 1단계 (setup only)
- ✓ 코드 간결성: 불필요한 함수 제거

### 6.2 선택적 copy 로직 제거 (SSOT + 일관성)

#### 현재 동작 (불일치)

```bash
setup_local_files() {
    for example_file in ...; do
        case "$environment" in
            internal)
                # 모든 파일 copy
                cp "$example_file" "$local_file"
                ;;
            external)
                # 선택적 조건부 copy
                if [ "$basename_file" = "proxy.local.example" ]; then
                    print_info "Skipped (not needed for VPN): ${basename_file}"
                else
                    cp "$example_file" "$local_file"
                fi
                ;;
        esac
    done
}
```

**문제점**:
- ✗ internal과 external의 copy 로직이 다름
- ✗ proxy.local은 특별 처리 (조건부 스킵)
- ✗ 일관성 부재 (DRY 원칙 위반)

#### 리팩토링 후 동작 (일관됨)

```bash
setup_environment_config() {
    local environment="$1"
    local config_file="$SHELL_COMMON_DIR/config/environments.conf"

    # 1. security.local.sh 생성 (동일한 로직)
    generate_config_file "security" "$environment" "$config_file"

    # 2. npm.local.sh 생성 (동일한 로직)
    generate_config_file "npm" "$environment" "$config_file"

    # 3. proxy.local.sh 생성
    #    - internal: 자동 생성
    #    - external: 자동으로 생성 안 함 (environments.conf에 정의 없음)
    if [ "$environment" = "internal" ]; then
        generate_config_file "proxy" "$environment" "$config_file"
    fi
}

generate_config_file() {
    local config_type="$1"
    local environment="$2"
    local config_file="$3"

    # environments.conf에서 값 읽어 파일 생성
    # 모든 환경에서 동일한 로직 사용
    local output_file="..."
    {
        cat "${TEMPLATE_FILE}"
        echo "# Auto-configured for: $environment"
        grep "^${environment}:${config_type^^}_" "$config_file" | \
        cut -d: -f2-
    } > "$output_file"
}
```

**개선점**:
- ✓ 모든 환경에서 동일한 generate_config_file() 사용 (DRY)
- ✓ 선택적 copy 로직 제거 (조건부 스킵 → 자동 판단)
- ✓ proxy.local은 environments.conf에 정의 여부로 자동 판단
  - internal: PROXY_* 정의 → 생성됨
  - external: PROXY_* 정의 없음 → 생성 안 됨

### 6.3 sed toggle 로직 제거 (명확성)

#### 현재 동작 (복잡)

```bash
# security.local.sh 처리
sed -i 's/^CA_CERT="\/usr\/local\/share/#CA_CERT="\/usr\/local\/share/' "$security_local"
sed -i 's/^#CA_CERT="\/etc\/ssl\/certs/CA_CERT="\/etc\/ssl\/certs/' "$security_local"

# npm.local.sh 처리
sed -i '/^    # === Option1:/,/^    # === Option2:/ {
    /DESIRED_REGISTRY=.*npmjs/s/^    /    # /
    /DESIRED_CAFILE=.*samsungsemi/s/^    /    # /
    ...
}' "$npm_local"
```

**문제점**:
- ✗ sed 정규식이 복잡하고 유지보수 어려움
- ✗ 파일 형식 변경에 취약 (들여쓰기 가정)
- ✗ 설정값이 중복 정의됨 (template + sed 패턴)

#### 리팩토링 후 동작 (명확함)

```bash
# environments.conf에서 직접 값 읽음
generate_config_file() {
    local config_type="$1"
    local environment="$2"
    local config_file="$3"

    {
        cat "${TEMPLATE_FILE}"
        echo ""
        echo "# Auto-configured for: $environment"

        # SSOT: environments.conf에서만 읽음
        grep "^${environment}:${config_type^^}_" "$config_file" | \
        cut -d: -f2- | \
        sed "s/${config_type^^}_//g"  # 접두사 제거
    } > "$output_file"
}
```

**개선점**:
- ✓ sed toggle 제거 (단순 파일 생성)
- ✓ SSOT 확보 (설정값 한 곳에서만 정의)
- ✓ 파일 형식 독립적 (들여쓰기 상관없음)
- ✓ 명확성: 생성되는 파일 내용이 예측 가능

### 6.4 setup.sh 전체 구조 개선

#### 현재 구조 (3단계 처리)

```
Main Menu
  ↓
cleanup_local_files()    ← 함수 1
  ↓
setup_local_files()      ← 함수 2 (조건부 copy 포함)
  ↓
sed toggle 처리          ← 함수 3
  ↓
setup_pip_config()       ← 함수 4
```

**문제**:
- 4개 함수 중 일부는 중복 책임
- 조건부 로직이 분산됨

#### 리팩토링 후 구조 (1단계 처리)

```
Main Menu
  ↓
setup_environment_config()    ← 단일 책임 함수
  ├─ generate_config_file("security")
  ├─ generate_config_file("npm")
  └─ generate_config_file("proxy")  [if internal]
  ↓
setup_pip_config()
```

**장점**:
- ✓ 함수 개수 감소 (cleanup_local_files 제거)
- ✓ 책임 명확화 (각 함수는 1가지만)
- ✓ 유지보수성 향상 (일관된 로직)

---

## 7️⃣ 권장 액션 플랜

### 단계 1: 즉시 (문제 해결)

1. **설정값 추출** (개선 1)
   - setup.sh 내에 `declare -A SECURITY_CONFIG=(...)`로 명시
   - sed 정규식의 의도를 주석으로 설명

2. **검증 로직 추가**
   - setup 완료 후 `npm config get registry` 등으로 확인
   - 사용자에게 피드백 제공

### 단계 2: 단기 (구조 개선)

1. **함수 분리** (개선 2)
   - setup_security_config(), setup_npm_config() 분리
   - SRP 원칙 준수

2. **문서 개선**
   - 각 파일의 용도를 명확히 (Template vs Configuration)
   - sed 패턴의 의도를 설명

### 단계 3: 중기 (근본 해결)

1. **리팩토링 방안 A 적용** (권장)
   - environments.conf 도입
   - SSOT 원칙 확보
   - sed 조작 제거

2. **파일 구조 표준화**
   - 모든 .local.example 통일
   - 설정 적용 로직 분리

3. **setup.sh 간소화** (섹션 6 참고)
   - cleanup_local_files() 제거
   - 선택적 copy 로직 제거
   - sed toggle 로직 제거

---

## 8️⃣ 체크리스트

### 현재 상태 ❌

- [ ] SSOT 원칙 준수 (설정값 중복 없음)
- [ ] SRP 원칙 준수 (함수의 책임이 명확함)
- [ ] OCP 원칙 준수 (새 파일 추가 시 코드 수정 불필요)
- [ ] DRY 원칙 준수 (중복 로직 없음)
- [ ] 파일 구조 일관성 (모든 .local.example이 동일한 패턴)
- [ ] 설정값 검증 (설정 후 확인 가능)

### 개선 후 목표 ✓

리팩토링 방안 A 적용 시:
- [x] SSOT 원칙 준수
- [x] SRP 원칙 준수 (함수 분리)
- [x] OCP 원칙 준수 (설정 추가 용이)
- [x] DRY 원칙 준수
- [x] 파일 구조 일관성
- [x] 설정값 검증 가능

---

## 📌 9️⃣ 결론

### 주요 발견사항

1. **동작 과정의 심각한 불일치** (3개 파일)
   - security.local: 간단한 1개 변수 (sed toggle)
   - npm.local: 복잡한 6개 변수 (sed 6줄 + range toggle)
   - proxy.local: 4개 변수 (조건부 스킵, Option 없음)
   - **동일한 설정 패턴을 3가지 다르게 처리 중**

2. **일관성 부재**
   - security.local과 npm.local: sed toggle 방식
   - proxy.local: 조건부 스킵 방식 (다름)
   - 각 파일의 구조, 변수 개수, Option 여부 모두 다름
   - setup.sh의 처리 로직이 제각각임

3. **SOLID 원칙 위반**
   - setup_local_files()가 3개 이상의 책임 보유 (SRP 위반)
   - 새 파일 추가 시 함수 수정 필요 (OCP 위반)
   - comment/uncomment 로직 중복 (DRY 위반)

4. **SSOT 원칙 위반**
   - 설정값이 template과 setup.sh에 중복 정의
   - npm.local: 2곳, proxy.local: 1곳, security.local: 1곳
   - 프로토콜 불일치로 유지보수 비용 증가

### 해결 방향

**권장**: 3단계 리팩토링 적용

1. **리팩토링 방안 A**: environments.conf 도입
   - SSOT 원칙 확보 (3개 파일 설정값을 1곳에 통합)
   - sed 조작 제거 (명확한 파일 생성)
   - 일관된 처리 방식 (모든 파일을 동일한 프로토콜로)

2. **setup.sh 간소화** (섹션 6 참고)
   - cleanup_local_files() 제거 (SRP 원칙)
   - 선택적 copy 로직 제거 (DRY 원칙)
   - sed toggle 로직 제거 (SSOT 원칙)
   - 처리 단계 감소: 2단계 → 1단계

3. **파일 구조 표준화**
   - 모든 .local.example 통일
   - 설정 적용 로직 분리

**최종 효과**:
- ✓ 코드 복잡도 감소 (함수 개수 감소, 단계 축소)
- ✓ 유지보수성 향상 (SSOT 확보)
- ✓ 확장성 확보 (새 환경/설정 추가 용이)
- ✓ 일관성 확보 (SOLID 원칙 준수)
