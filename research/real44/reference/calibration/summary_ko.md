# GoPro HERO13 + RB5 RWHEC 결과 — 2026-10-28

- 구성: 손목 장착 카메라, 고정 ChArUco 보드 (`eye_in_hand`).
- 입력: `data/rb5/gopro_raw/manifest.json`, GP010588.JPG–GP010651.JPG ↔ pose001–pose064.
- Intrinsic: `hardware/intrinsics/2026-10-27/fisheye.json` 및 일치하는 PASS 검증 보고서.
- Intrinsic SHA256: `bd0beaf5a03afb0b4a1d77a25735cc2342b513c87f3f6e5d0313f210af6c2acb`.
- 로봇 입력: 실제 관절각 + 설정된 `rb5_850e` URDF FK, `link0` → `tcp`.
- 처리 데이터: `data/rb5/gopro_session_20261028/`.

## 입력 검사

64쌍의 파일·ID·로봇 기록을 검증하고 JPG에서 ChArUco 자세를 계산했습니다.
44쌍을 채택했습니다. 재투영 RMS > 1 px인 19쌍과 보드 면적 부족 1쌍을 제외했습니다.
설정된 기준을 완화하거나 솔버 잔차를 보고 추가 샘플을 제거하지 않았습니다.
채택된 사진의 보드 재투영 RMS는 0.344–0.981 px, 중앙값 0.628 px입니다.

제외: pose004, pose007, pose010, pose017, pose018, pose019, pose020, pose021,
pose033, pose042, pose043, pose044, pose045, pose046, pose047(면적 부족),
pose049, pose051, pose052, pose054, pose061.
자세별 제외 사유는 처리 데이터의 `import_report.json`에 있습니다.

## 최적화와 잔차

| 항목 | 값 |
|---|---:|
| 사용한 사진/포즈 쌍 | 44 |
| Solver/status | COSMO / OPTIMAL |
| numerically_certified | true |
| normalized_gap | 1.1743789129283318e-8 |
| 위치 RMS | 7.7777 mm |
| 회전 RMS | 0.95995 deg |
| 위치 잔차 중앙값 / 최대 | 6.7923 / 16.5152 mm |
| 회전 잔차 중앙값 / 최대 | 0.67847 / 1.76245 deg |

위치 잔차가 큰 샘플은 pose011(16.515 mm), pose006(14.804 mm),
pose009(13.052 mm), pose014(12.604 mm), pose023(11.079 mm)입니다.

`residuals.csv`의 행 순서는 처리 데이터 `combined/sample_ids.json`과 같습니다.
`residuals_by_sample.csv`에 ID·원본 사진명·위치/회전 잔차·재투영 RMS를 연결했습니다.
`residuals.png`는 자세별 잔차 그래프입니다.

## 좌표 변환

`T_parent_child`는 child 좌표를 parent 좌표로 변환합니다. CSV는 4×4 행렬이며 이동 단위는 m입니다.

- `T_hand_camera.csv`: 카메라 → URDF tip(`tcp`) 좌표. 이동 성분(mm): [-2.2753, -43.9107, 87.2950].
- `T_base_board.csv`: 보드 → 로봇 base(`link0`) 좌표. 이동 성분(mm): [50.5362, -1291.0696, 304.4323].
- 촬영 당시 `T_base_camera = T_base_hand @ T_hand_camera`.

두 회전행렬의 직교성·행렬식과 동차행렬 마지막 행을 확인했습니다.
저장된 A/B/X/Y로 `A @ X`와 `Y @ B` 잔차를 Python에서 다시 계산하여
Julia가 저장한 `residuals.csv`와 일치하는지 확인했습니다.

수치적 최적성 검증은 지정된 입력·목적함수에 대한 부동소수점 검증입니다.
7.78 mm / 0.96 deg는 보정에 사용한 데이터의 일치도이며 실제 절대 정확도나
새 자세에 대한 정확도 보증이 아닙니다. 독립된 자세/기준 측정에 대한 검증은 아직 수행하지 않았습니다.
물리 정확도를 판단하려면 보드 위치와 카메라 장착 위치의 실측 및 별도 검증 데이터가 필요합니다.

## 실행 명령

```bash
/usr/bin/python3 -u -m hardware.rb5_gopro --config hardware/rb5.local.json import \
  --manifest data/rb5/gopro_raw/manifest.json --output data/rb5/gopro_session_20261028
bash scripts/julia_rb5.sh scripts/calibrate_rb5.jl \
  data/rb5/gopro_session_20261028/combined results/rb5/gopro_session_20261028 eye_in_hand
```

위 출력 경로는 이미 존재하므로 재실행할 때 새 출력 폴더를 지정합니다.
