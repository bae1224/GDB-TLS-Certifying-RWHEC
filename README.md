# Grouped Deletion Bounds for Certifying TLS Optimality in Robot-World Hand-Eye Calibration

레인보우 로보틱스 RB5-850·GoPro HERO 13 광각 카메라로 수집한 **논문 44쌍 데이터와 재현 코드**.

원본 이미지·로봇 기록의 pose 추출, RWHEC 해 추정, 논문 고정 후보의 TLS 인증 코드 포함.

## RWHEC

Robot–World and Hand–Eye Calibration: 관측 자세 `A_i`, `B_i`에서
`A_i X = Y B_i`를 만족하는 두 고정 변환 추정.

이 저장소의 eye-in-hand 구성:

- `X`: 로봇 말단 기준 카메라 자세
- `Y`: 로봇 베이스 기준 보드 자세

[Wise 등의 연구](https://arxiv.org/abs/2507.23045v2)는 다중 센서·타깃과 단안 scale까지
다루며, SDP relaxation으로 least squares(LS) 해의 전역 최적성을 인증.

이 저장소는 단일 카메라·보드와 알려진 scale에 해당하는 보정 코드 제공.

## KRoC 논문

LS 후보가 truncated least squares(TLS)에서도 최적인지 검사.

- 모든 관측 비용이 cutoff 미만인 full-support 후보의 LS dual 해 재사용
- singleton·pairwise 제거 bounds를 cascade로 결합
- 관측 제거 조합의 직접 열거 없이 수치 인증의 충분조건 검사

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

- 실행 위치: 저장소 루트
- 환경: Linux x86_64, Python 3.10 이상, Julia 1.10.10

```bash
python3 -m venv real44data/.venv
real44data/.venv/bin/python -m pip install \
  -r hardware/requirements-gopro.txt \
  -r real44data/requirements.txt

bash scripts/install_julia_rb5.sh
real44data/.venv/bin/python real44data/prepare.py --verify-only

real44data/.venv/bin/python -m hardware.rb5_gopro \
  --config hardware/rb5.gopro.json import \
  --manifest real44data/data/manifest.json \
  --output real44data/.work/from_images

bash scripts/julia_rb5.sh scripts/calibrate_rb5.jl \
  real44data/.work/from_images/combined \
  real44data/.work/solution eye_in_hand
```

이미지와 로봇 기록은 `sample_id`로 대응.

ChArUco/fisheye 보드 pose와
관절각·URDF FK로 `A = T_base_hand`, `B = inverse(T_camera_board)`를 구성한 뒤 LS 해 추정.

출력 폴더: `real44data/.work/solution/`. 재실행 시 새 출력 폴더 지정.

- 추정 변환: `T_hand_camera.csv`, `T_base_board.csv`
- 결과 보고서·잔차: `report.toml`, `residuals.csv`

저장 데이터 재현에는 로봇·카메라 연결이나 ROS 불필요.

실시간 로봇 측정용 ROS 2/rbpodo 연동 코드 포함. 장비 연결 시 ROS 2와
`rbpodo_ros2` 드라이버 등 별도 설치 필요.

## 논문 TLS 인증 재현

```bash
RWHE_PYTHON=real44data/.venv/bin/python bash real44data/reproduce.sh
```

인증 대상: `real44data/input`의 **논문용 고정 X/Y**.

새로 추정한 해의 자동 인증은 미포함.

- 검증: 75개 cutoff, 324회 시간 측정, 독립적인 NumPy 검증
- 결과 저장: `real44data/.work/reproduction/`

**기존 44쌍 결과**

- 기존 44쌍의 AX=YB 일관성 RMS: **7.777714 mm / 0.959949°**.
- 시험한 cutoff **3.30–4.05의 16개 설정**에서 singleton은 미인증, pairwise·cascade는 인증.

인증 범위는 지정된 목적함수의 부동소수점 수치 검증으로, 물리적 절대 정확도 보장은 제외.
미인증만으로 비최적성을 의미하지 않음.

- 상세 조건: [재현 안내](real44data/README.md)
- 코드 출처: [UPSTREAM.json](UPSTREAM.json), [provenance.json](real44data/provenance.json)