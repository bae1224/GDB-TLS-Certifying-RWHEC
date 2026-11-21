# Real44: 논문 실측 데이터와 재현 코드

RB5-850 / GoPro HERO13 / 고정 ChArUco 보드의 기존 44쌍 실측 자료와
full-support RWHE 후보에 대한 singleton, pairwise, cascade TLS 인증 실험입니다.
공개 범위는 이 실측 실험입니다. 다른 촬영 세션과 합성 실험은 포함하지 않습니다.

## 데이터와 결과

| 경로 | 내용 |
|---|---|
| `data/images/` | 실험에 사용한 원본 해상도 JPG 44장, 약 211 MiB |
| `data/robot_records/` | 이미지와 짝을 이루는 로봇 측정 기록 44개 |
| `data/samples/` | sample_id, 이미지 경로, 로봇/보드 pose, 검출 코너, 영상 품질 |
| `data/manifest.json` | 포함된 44쌍만 가리키는 상대 경로 매핑 |
| `data/source_import_report.json` | 원래 64쌍에서 44쌍을 채택한 기록 |
| `data/combined/` | 원래 보정 입력 A/B와 행별 sample_id |
| `input/` | 논문 인증에 사용한 고정 A/B/X/Y와 행별 sample_id |
| `reference/calibration/` | 원래 LS 보정 결과, 잔차 CSV와 그림 |
| `reference/` | 기존 논문의 75개 cutoff 결과, 324회 시간 측정, 진단과 그림 |
| `lib/` | 기존 인증 코드에서 가져온 비용 행렬, LS dual, 제거 bounds |
| `protocol.json` | cutoff grid, 가중치, 수치 기준, 9회 측정 규칙 |
| `SHA256.json` | 배포 파일의 무결성 확인 목록 |

원래 64쌍 중 영상 재투영 RMS > 1 px인 19쌍과 보드 영상 면적 < 1%인
1쌍을 제외한 44쌍입니다. 이 선택은 영상 품질 기준이며 RWHE outlier 판정이
아닙니다. 제외한 관측의 이미지/pose는 이 패키지에 포함하지 않습니다.

이미지 번호로 pose를 추측하지 말고 `sample_id`와 `data/manifest.json`을
사용하십시오. 원본 JSON 내부의 절대 경로는 당시 출처 기록이며, 재현 코드는
그 경로에 접근하지 않습니다. 이미지, 로봇 기록, pose, 고정 후보는 원본과
동일한 바이트로 보존했습니다.

`A = T_base_hand`, `B = inverse(T_camera_board)`, `X = T_hand_camera`,
`Y = T_base_board`이고 `AX = YB`입니다. CSV 열은
`qw,qx,qy,qz,tx,ty,tz`, 병진 단위는 m입니다. Hand는 URDF tip 프레임입니다.
`samples`의 `T_camera_target`은 카메라 기준 보드 pose이며 B의 역행렬입니다.

## 설치와 재현

아래 명령은 저장소 루트에서 실행합니다. Python 3.10 이상과 Julia 1.10이
필요합니다. Julia 환경은 기존 `environment/Manifest.toml`로 고정됩니다.
Julia 설치 스크립트는 Linux x86_64용입니다.

```bash
python3 -m venv real44data/.venv
real44data/.venv/bin/python -m pip install -r real44data/requirements.txt
bash scripts/install_julia_rb5.sh
real44data/.venv/bin/python real44data/prepare.py --verify-only
RWHE_PYTHON=real44data/.venv/bin/python bash real44data/reproduce.sh
```

새 결과는 `real44data/.work/reproduction/`에 생성됩니다. 기존 결과를
덮어쓰지 않으며, 다시 실행할 때는 새 출력 경로를 지정합니다.

```bash
RWHE_PYTHON=real44data/.venv/bin/python bash real44data/reproduce.sh real44data/.work/run2
```

재현 절차는 44쌍의 hash/매핑 확인, 75개 cutoff의 LS SDP 및 bounds 계산,
12개 cutoff × 3방법 × 9회 시간 측정, 독립적인 NumPy 비용/bound 재구성,
기존 논문 판정과 비교, 그림 생성을 수행합니다. Julia와 BLAS는 각각 1스레드입니다.
후보 X/Y는 고정하며 cutoff를 바꿀 때 재추정하지 않습니다.

기존 보정 솔버로 LS 추정을 다시 수행하려면 별도 출력 폴더를 사용합니다.
이 단계는 인증 실험의 고정 후보를 변경하지 않습니다.

```bash
bash scripts/julia_rb5.sh scripts/calibrate_rb5.jl real44data/data/combined real44data/.work/refit eye_in_hand
```

원본 이미지로부터 보드 pose를 추출하는 코드는 `hardware/rb5_gopro`에,
관절각에서 로봇 pose를 계산하는 FK와 공용 처리 코드는 `hardware/rb5`에 있습니다.
RB5 URDF는 `hardware/models/rainbow/rb5_850e.urdf`에 포함되어 있습니다.
OpenCV 등 영상 처리 의존성은 `hardware/requirements-gopro.txt`를 참조하십시오.
아래 두 명령으로 원본 JPG와 로봇 기록에서 A/B를 다시 만들고, 그 입력으로 X/Y를 추정합니다.

```bash
python3 -m hardware.rb5_gopro --config hardware/rb5.gopro.json import --manifest real44data/data/manifest.json --output real44data/.work/reimport
bash scripts/julia_rb5.sh scripts/calibrate_rb5.jl real44data/.work/reimport/combined real44data/.work/refit_from_images eye_in_hand
```

이 과정은 저장된 데이터로 실행되므로 ROS·RealSense·실제 장비 연결이 필요하지 않습니다.
새로 추정한 X/Y는 별도 결과이며, `reproduce.sh`는 계속 논문용 고정 후보를 사용합니다.

## 확인할 결과와 해석

- 고정 후보의 AX=YB 잔차: 병진 RMS 약 **7.777714 mm**, 회전 RMS 약 **0.959949°**.
- 정규화 전 LS 비용: **16.3960522982**. 가중치는 회전 125, 병진 5000입니다.
- 시험한 cutoff **3.30–4.05의 16개 설정**에서 singleton은 미인증,
  pairwise와 cascade는 인증입니다. Singleton은 시험값 4.10부터 인증됩니다.
- Cutoff 1과 1.5는 full-support 조건을 만족하지 않아 적용 대상 밖입니다.
- Cutoff 4에서 기존 9회 중앙값은 singleton **11.9 ms / 미인증**,
  pairwise **29.3 ms / 인증**, cascade **28.1 ms / 인증**입니다.

시간은 CSV 입력, 비용 행렬 구성, LS SDP 풀이와 인증을 포함합니다.
후보 생성, 프로세스 시작과 JIT는 제외합니다. 새 실행시간은 실행 환경에 따라
달라지며 `reference`의 기존 시간과 구분해 보고해야 합니다.

75개 cutoff는 동일 자료의 민감도 분석입니다. 독립 실험 75건이 아닙니다.
Cutoff는 독립 잡음 분포에서 추정한 값이 아닙니다. 인증은 지정된 목적함수의
부동소수점 수치 인증이며 물리적 절대 보정 정확도 또는 interval proof가
아닙니다. 미인증은 비최적성의 증명이 아닙니다.

`reference/calibration`의 `numerically_certified`는 LS 솔버의 판정입니다.
TLS 판정은 `reference/cutoff_results.csv` 또는 새 재현 결과를 사용하십시오.
논문 후보와 원래 LS 솔버 출력은 수치적으로 매우 가깝지만, 정확한 논문 재현에는
`input/X_candidate.csv`와 `input/Y_candidate.csv`를 사용합니다.
