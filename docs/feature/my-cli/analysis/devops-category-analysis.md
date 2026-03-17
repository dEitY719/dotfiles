# DevOps Category Analysis

**카테고리**: DevOps
**Topics**: docker, dproxy, sys, proxy, mount, mysql, gpu
**총 7개**

---

## 1. Docker ⭐⭐⭐⭐ (Tier 2)

**파일**: `docker_help.sh` (64줄)
**사용 빈도**: Weekly (2~3회)

### 콘텐츠 분석
```
예상 섹션:
- Container Management
- Image Management
- Network
- Volumes
- Logs & Debug
```

### 개선 방향

**Quick Mode (필수 명령어)**
```
- docker ps / docker ps -a
- docker run / docker exec
- docker build
- docker logs
- docker stop / docker rm
총 5~6개
```

**Full Mode**
```
모든 섹션 포함
```

### 우선순위
- CL-7.4 (상세 분석 후)

---

## 2. Proxy ⭐⭐⭐ (Tier 2)

**파일**: `proxy_help.sh` (91줄)
**사용 빈도**: Weekly (특정 환경)

### 현황
```
- 프록시 설정 및 관리
- 네트워크 환경에 따라 사용
```

### 개선 방향
```
Quick Mode: 주 설정 명령어
Full Mode: 모든 설정 옵션
```

### 우선순위
- CL-7.5 (후순위)

---

## 3. DProxy ⭐⭐ (Tier 2)

**파일**: `dproxy_help.sh` (54줄)
**사용 빈도**: Weekly

### 분석 대기

---

## 4. Sys ⭐⭐ (Tier 2)

**파일**: `sys_help.sh` (44줄)
**사용 빈도**: Weekly (시스템 관리)

### 분석 대기

---

## 5. Mount ⭐⭐ (Tier 3)

**파일**: (분석 필요)
**사용 빈도**: Monthly

### 분석 대기

---

## 6. MySQL ⭐⭐ (Tier 2)

**파일**: `mysql_help.sh` (22줄)
**사용 빈도**: Weekly (개발 시)

### 현황
```
간단함 (22줄)
- 기본 MySQL 명령어
```

### 개선 방향
```
현재 상태 유지 가능
```

---

## 7. GPU ⭐⭐ (Tier 3)

**파일**: `gpu_help.sh` (38줄)
**사용 빈도**: Rarely

### 분석 대기

---

## 📊 Summary

| Topic | Lines | Tier | Frequency | Status |
|-------|-------|------|-----------|--------|
| docker | 64 | 2 | Weekly | ⏳ Pending |
| proxy | 91 | 2 | Weekly | ⏳ Pending |
| dproxy | 54 | 2 | Weekly | ⏳ Pending |
| sys | 44 | 2 | Weekly | ⏳ Pending |
| mount | ? | 3 | Monthly | ⏳ Pending |
| mysql | 22 | 2 | Weekly | ⏳ Pending |
| gpu | 38 | 3 | Rarely | ⏳ Pending |

---

## 🎯 Priority

**우선순위**: CL-7.4 이후 (DevOps 카테고리는 Development보다 후순위)

가장 많이 사용되는 것부터:
1. Docker (Weekly)
2. Proxy (Weekly)
3. Sys (Weekly)
4. MySQL (Weekly)
