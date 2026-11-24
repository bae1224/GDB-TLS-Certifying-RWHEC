# 표 3: 동일 입력의 TLS 인증 비교

SSR–DRS의 RWHEC 재구현과 제안 단일 관측·관측 쌍·단계적 방법을 같은 관측, 후보, 정규화 전 가중치, 절단 임계값으로 비교하는 독립 실행 묶음.

하한의 근거는 [LOWER_BOUND.md](LOWER_BOUND.md), 실제 계산은 [verified_bound.jl](verified_bound.jl)에 정리했다. 원 저자의 DRS/STRIDE 공식 구현을 실행한 결과로 해석하지 않는다.

## 구성

- `cases/`: 사전에 고정한 합성 8건과 기존 실측 44쌍 1건. 후보 재추정 없음
- `protocol.json`: 입력 해시, 사례 선택, 30초 예산, 3회 반복, 상대 비용 간격 기준
- `common.jl`: 동일 입력 구성과 기존 단일 관측·관측 쌍·단계적 구현
- `ssr_drs.jl`: SSR 목적식, Frobenius 투영, LS 좌표 정규화, DRS 반복
- `verified_bound.jl`: 부분수준집합 상계와 목적식·전체 슬랙 잔차 보정
- `test_bounds.jl`: 양성·음성 통제 실험과 오차 구간 검사
- `runs/`, `matched_case_results.csv`, `matched_summary.json`: 이번 재측정 결과
- `original_*`: 수정 전 프로토콜·요약. 이번 결과와 구분해 보존

## 재현

Julia 1.10.10과 저장된 `environment/Manifest.toml`을 사용한다. 초기 설치 시 패키지 다운로드가 필요할 수 있다.

```bash
julia --project=environment -e 'using Pkg; Pkg.instantiate()'
```

기록된 결과를 보존한 채 새로운 디렉터리에서 재측정한다. Python 3.11 이상이면 추가 Python 패키지가 필요 없다.

```bash
python3 make_rerun.py /tmp/kroc_tls_rerun
cd /tmp/kroc_tls_rerun
OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 JULIA_NUM_THREADS=1 \
  julia --project=environment test_bounds.jl
OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 JULIA_NUM_THREADS=1 \
  julia --project=environment run_benchmark.jl
python3 summarize.py
```

9건 × 3회 × 30초의 SSR 예산과 초기 컴파일 시간이 필요하다. 기존 `runs/`가 있으면 덮어쓰지 않고 중단한다. JIT 준비와 통제 실험은 측정 시간에서 제외하며, 입력 읽기·전처리·인증·최종 검사는 포함한다. 방법 순서는 반복마다 순환한다.

`slacks/`의 큰 바이너리는 재실행 때 생성한다. GitHub용 묶음에는 포함하지 않는다. 입력과 소스의 해시, 호출별 결과, 검증 기록은 포함한다.

재측정 후 `audit_saved.jl`로 사례별 저장 슬랙의 전체 잔차 검증을 실행할 수 있다.
`test_end_to_end.jl`은 최적값 0인 RWHEC 사례와 잘못된 후보를 별도로 검사한다.
두 검사는 표 3 시간에 포함하지 않는다.
`verify_physical.py`는 NumPy로 저장 슬랙의 목적식 관계를 독립적으로 표본 검사한다.
이는 전역 하한의 증명을 대체하지 않으며, 결과는 `physical_validation.json`에 저장한다.

## 재측정 결과: 2026-11-24

| 자료 | τ² | SSR–DRS 인증 | 시간 합(s) | 단계적 인증 | 시간 합(s) |
|---|---:|---:|---:|---:|---:|
| 일반 합성 | 16 | 0/4 | 125.083 | 2/4 | 0.118 |
| 제한 합성 | 16 | 0/4 | 122.788 | 2/4 | 0.123 |
| 실측 44쌍 | 4 | 0/1 | 30.444 | 1/1 | 0.028 |
| 합계 | — | 0/9 | 278.315 | 5/9 | 0.270 |

시간은 미인증을 포함한 사례별 3회 중앙값의 합. 합계는 반올림 전 값으로 계산. SSR–DRS의 27회 호출은 모두 30초 예산에 도달해 반복 경계에서 종료.

- [호출별 원자료](runs/) · [사례별 집계](matched_case_results.csv) · [요약](matched_summary.json)
- [하한 통제 검사](tests.toml) · [저장 슬랙 전체 잔차 검사](saved_audit.toml) · [통합 검사](integration_tests.toml)
- [독립적인 목적식 표본 검사](physical_validation.json): 27개 슬랙, 540개 자세·이진변수 조합

## 해석

작은 병진 영공간 잔차를 버리고 얻은 Schur 값은 하한으로 보고하지 않는다. 후보 비용 이하인 해의 병진 크기를 관측에서 유도하고, 전체 목적식과 PSD 잔차를 그 크기로 보정한다. 검증 조건이 성립하지 않으면 자명한 TLS 하한 0을 사용한다.

표 3은 명시한 재구현·9건·시간 예산에서의 비교다. 공식 구현과 초기화·투영·하한 보정이 다르고 보정이 보수적일 수 있으므로, 기존 TLS 인증법의 일반적 성능을 대표하지 않는다. 단일 관측·관측 쌍·단계적 방법의 기존 수치 판정 절차는 그대로 유지했다. 새로운 잔차 검증은 SSR–DRS에 적용했다.

실측 44쌍·τ²=4의 28.0 ms 대 1176.6 ms, 약 42배라는 기존 표 2의 수치는 자체 구현 열거법과의 별도 비교다. 이 묶음의 표 3 실행시간과 섞지 않는다. 임계값 실험에서는 정규화 전 가중치를 고정한다.
