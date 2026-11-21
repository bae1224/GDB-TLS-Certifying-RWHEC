# Grouped Deletion Bounds for Certifying TLS Optimality in Robot-World Hand-Eye Calibration

RB5-850·GoPro HERO13으로 수집한 **기존 논문 44쌍 데이터와 재현 코드**입니다.
원본 이미지와 로봇 기록에서 pose를 추출하고 RWHEC 해를 구하는 코드,
논문의 고정 후보에 대한 TLS 인증 코드가 포함되어 있습니다.

## RWHEC

Robot–World and Hand–Eye Calibration은 관측 자세 `A_i`, `B_i`로부터
`A_i X = Y B_i`를 만족하는 두 고정 변환을 추정하는 문제입니다.
이 저장소의 eye-in-hand 구성에서 `X`는 카메라의 로봇 말단 기준 자세,
`Y`는 보드의 로봇 베이스 기준 자세입니다.
[Wise 등의 연구](https://arxiv.org/abs/2507.23045v2)는 다중 센서·타깃과 단안 scale까지
다루며, SDP relaxation으로 least squares(LS) 해의 전역 최적성을 인증합니다.
여기에는 단일 카메라·보드와 알려진 scale에 해당하는 보정 코드가 포함됩니다.

## KRoC 논문

**Grouped Deletion Bounds for Certifying TLS Optimality in Robot-World Hand-Eye Calibration**은
LS 후보가 truncated least squares(TLS)에서도 최적인지 검사합니다.
모든 관측 비용이 cutoff 미만인 full-support 후보를 대상으로 LS dual 해를 재사용하고,
singleton·pairwise 제거 bounds를 cascade로 결합하여 관측 제거 조합을 직접 열거하지 않고
수치 인증의 충분조건을 검사합니다.

## 폴더 구성

| 경로 | 내용 |
|---|---|
| [real44data/data](real44data/data) | 원본 JPG 44장, 대응 로봇 기록, pose와 manifest |
| [hardware/rb5_gopro](hardware/rb5_gopro) | GoPro 이미지 처리·보드 pose 추정·로봇 측정 연동 |
| [hardware/rb5](hardware/rb5) | RB5 URDF FK, 로봇 상태 읽기, 좌표 변환·CSV 생성 |
| [hardware/models/rainbow](hardware/models/rainbow) | RB5-850E URDF와 출처·라이선스; FK용이며 mesh는 제외 |
| [hardware/intrinsics/2026-10-27](hardware/intrinsics/2026-10-27) | GoPro fisheye 내부 파라미터와 검증 자료 |
| [scripts](scripts) · [src](src) | Julia 설치·실행, RWHEC LS 해 추정과 SDP 제약 |
| [environment](environment) | 고정된 Julia 의존성 환경 |
| [real44data](real44data) | 논문 고정 A/B/X/Y, TLS 인증 코드, 기존 결과·재현 안내 |

## 원본 이미지에서 RWHEC 해 구하기

저장소 루트에서 실행합니다. Linux x86_64, Python 3.10 이상과 Julia 1.10.10을 사용합니다.

```bash
python3 -m venv real44data/.venv
real44data/.venv/bin/python -m pip install -r hardware/requirements-gopro.txt -r real44data/requirements.txt
bash scripts/install_julia_rb5.sh
real44data/.venv/bin/python real44data/prepare.py --verify-only

real44data/.venv/bin/python -m hardware.rb5_gopro --config hardware/rb5.gopro.json import \
  --manifest real44data/data/manifest.json --output real44data/.work/from_images
bash scripts/julia_rb5.sh scripts/calibrate_rb5.jl \
  real44data/.work/from_images/combined real44data/.work/solution eye_in_hand
```

이미지와 로봇 기록은 `sample_id`로 대응시킵니다. ChArUco/fisheye 보드 pose와
관절각·URDF FK로 `A = T_base_hand`, `B = inverse(T_camera_board)`를 만든 뒤 LS 해를 구합니다.
`real44data/.work/solution/`에 `T_hand_camera.csv`, `T_base_board.csv`,
`report.toml`, `residuals.csv`가 생성됩니다. 재실행할 때는 새 출력 폴더를 지정합니다.

저장된 자료의 재현에는 로봇·카메라 연결이나 ROS가 필요하지 않습니다.
실시간 로봇 측정용 ROS 2/rbpodo 연동 코드도 포함되지만, ROS 2와
`rbpodo_ros2` 드라이버 등 실제 장비 연결 환경은 별도로 설치해야 합니다.

## 논문 TLS 인증 재현

```bash
RWHE_PYTHON=real44data/.venv/bin/python bash real44data/reproduce.sh
```

이 절차는 `real44data/input`의 **논문용 고정 X/Y**를 사용합니다.
위에서 새로 추정한 해를 자동으로 인증하는 절차는 아닙니다.
75개 cutoff, 324회 시간 측정과 독립적인 NumPy 검증을 수행하고,
`real44data/.work/reproduction/`에 결과를 저장합니다.

- 기존 44쌍의 AX=YB 일관성 RMS: **7.777714 mm / 0.959949°**.
- 시험한 cutoff **3.30–4.05의 16개 설정**에서 singleton은 미인증, pairwise·cascade는 인증.

인증은 지정된 목적함수에 대한 부동소수점 수치 검증이며 물리적 절대 정확도 보장이 아닙니다.
미인증은 비최적성의 증명이 아닙니다. 다른 촬영 세션과 합성 실험은 이번 공개 범위에 포함하지 않습니다.
상세 조건은 [재현 안내](real44data/README.md), 코드 출처는
[UPSTREAM.json](UPSTREAM.json)과 [provenance.json](real44data/provenance.json)을 참조하십시오.
