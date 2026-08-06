# gpu

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/system_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic gpu --force`

## 호출

- Help 진입점: `gpu-help [section|--list|--all]`
- 통합 라우팅: `my-help gpu [section]`
- Alias: `gpu-help`

## 요약 (gpu-help)

- Usage: gpu-help [section|--list|--all]
- sections
    - diagnostics: gpustatus | gpuinfo
    - docker: gpu-offload | gpu-mem
    - fixes: docker compose restart ollama | docker restart ollama | dcr ollama
    - wsl: gpu-info-basic | gpu-memory | gpu-watch
    - test: tinyllama | llama3:instruct
    - troubleshoot: OLLAMA_NUM_GPU | OLLAMA_FLASH_ATTENTION
    - examples: good vs bad layer offload
    - tips: gpustatus | gpuinfo | gpu-offload | gpu-memory | gpu-watch
    - details: gpu-help <section>  (example: gpu-help diagnostics)

## 섹션

### diagnostics

- **gpustatus** — bash gpu_status.sh — 5-part detailed GPU diagnostic
- **gpuinfo** — Compact GPU summary — Brief GPU hardware + layer offload

### docker

- **gpu-offload** — docker logs ollama | grep offloaded — Layer offload status (25/25 = good)
- **gpu-mem** — docker logs ollama | grep gpu memory — GPU memory recognition check

### fixes

- **docker compose restart ollama** — Restart Ollama — Forces GPU layer re-init
- **docker restart ollama** — Restart container — Direct restart without compose
- **dcr ollama** — Auto-detect restart — Compose-aware restart

### wsl

- **gpu-info-basic** — nvidia-smi — GPU hardware info, workload, temp
- **gpu-memory** — nvidia-smi memory (CSV) — Detailed memory info
- **gpu-watch** — Real-time GPU monitor — Live monitoring (Ctrl+C to exit)

### test

- Fast test (1-2s): docker exec ollama ollama run tinyllama "hi"
- Full test (10s+): docker exec ollama ollama run llama3:instruct "hi"

### troubleshoot

- Add to docker-compose.yml (Ollama service):
  environment:
    OLLAMA_NUM_GPU: '25'           # or your GPU's layer count
    OLLAMA_FLASH_ATTENTION: '1'    # enables flash attention
- Then restart: docker compose up -d ollama

### examples

- ✅ Good GPU layer offload:
  offloaded 25/25 layers to GPU

- ❌ Bad GPU layer offload:
  offloaded 0/25 layers to GPU

### tips

- Full diagnosis: gpustatus
- Quick overview: gpuinfo
- Monitor layers: gpu-offload
- Check memory: gpu-memory or gpu-watch

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/gpu.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/system_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
