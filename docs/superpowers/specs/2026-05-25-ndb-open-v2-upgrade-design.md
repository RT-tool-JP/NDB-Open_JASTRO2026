# NDB Open Data v2.0 アップグレード設計書

- 起票日: 2026-05-25
- 対象リポジトリ: `NDB-Open_2026JASTRO`
- 現バージョン: v1.00（2026/02/13）
- ターゲット: v2.0（2026/05/25）

## 1. 目的と背景

現行 `index.html`（v1.00）は都道府県別 NDB 算定回数を「人口10万人あたり固定」で表示するシングルビューのコロプレスマップである。
`20260316_試験版/` 以下に v0.9β として、A/B 切替・A/B 比表示、施設指標、分母選択（9種）、二次医療圏単位データなど、機能を大幅拡張した試作版が存在する。

本アップグレードの目的は、試験版の拡張機能のうち以下を v2.0 として正式取り込みすること:

- **A/B 切替および A/B 比の表示**
- **施設指標の分子化**（病院数・医師数・放射線科医・看護師・診療放射線技師・各種放射線治療設備）
- **分母の選択化**（実数 / 人口10万 / 65歳以上10万 / SCR / リニアック / 病院 / 放射線科医 / 看護師 / 技師）
- **データ取得・処理スクリプト一式の正式採用**

一方、**二次医療圏（SMA）単位の表示機能は今回スコープ外**とする。今後も追加しない方針のため、UI・JSON・README から二次医療圏に関する記述・要素を削除する。ただし R スクリプト側は将来の方針変更に備え、ダウンロードとパースは残置する（最終 JSON 組み立てだけスキップ）。

## 2. スコープ

### 取り込む機能（試験版から）

| 機能 | 概要 |
|---|---|
| A/B 設定 + A/B 比表示 | 2 つの分子設定を独立に持ち、ヘッダで A/B/比 を切替 |
| 分母 9 種 | 実数, 人口10万, 65+10万, SCR, /リニアック, /病院, /放射線科医, /看護師, /技師 |
| 施設指標タブ | NDB算定 と 施設指標 のタブ。後者は病院数/医師数/放射線科医/看護師/技師/各種放射線治療設備 |
| パレット選択 | 7色の sequential / 4色の diverging + カスタムカラー |
| デュアルレンジスライダ凡例 | 範囲指定スライダ + 入力欄 + AUTO/手動バッジ |
| ズーム/パン | d3-zoom による拡大・縮小・リセット |
| 統計拡張 | IQR/ジニ係数/変動係数を A/B/比モードで切替 |
| 免責事項オーバーレイ | 起動時にスクロール→同意チェック→利用開始 |

### スコープ外（除去）

- 二次医療圏単位の地理単位トグル（UI から削除）
- SMA 関連の `data-geo='sma'` フィルタ、`curGeoUnit === 'sma'` 分岐、`DATA.sma.regions` 等の参照
- `sma.geojson` の fetch
- README/DATA_SOURCES.md における二次医療圏言及

## 3. アーキテクチャ

### 3.1 配信構成（GitHub Pages 互換）

```
NDB-Open_2026JASTRO/
├── index.html                       単一ファイル webapp（v2.0）
├── data/
│   ├── dashboard_data.json            scripts/10 が出力
│   └── prefectures.geojson            scripts/05 がコピー
├── scripts/                         R パイプライン（試験版から移植）
│   ├── 01_download_ndb_data.R
│   ├── 02_download_facility_data.R
│   ├── 03_download_physician_data.R
│   ├── 04_download_population_data.R
│   ├── 05_download_geo_data.R
│   └── 10_prepare_web_data.R
├── rawdata_dl/                      R が落とした生データ（gitignore）
│   ├── ndb_pref/  ndb_sma/  facility/  physician/  population/  geo/
├── _legacy/                         v1.00 退避
│   ├── index.html  rawdata/  scripts/  data/  output/
├── 20260316_試験版/                 参照用に残置
├── README.md  DATA_SOURCES.md  LICENSE  .gitignore
```

### 3.2 データフロー

```
e-Stat / 厚労省サイト
  ├─ scripts/01 → rawdata_dl/ndb_pref/, ndb_sma/, ndb_pref/*_sexage/
  ├─ scripts/02 → rawdata_dl/facility/
  ├─ scripts/03 → rawdata_dl/physician/
  ├─ scripts/04 → rawdata_dl/population/
  └─ scripts/05 → rawdata_dl/geo/  → data/prefectures.geojson にコピー
                                          ↓
scripts/10_prepare_web_data.R（全部入りで読み込み・集計・SCR算出）
                                          ↓
                          data/dashboard_data.json（SMA キー除外）
                                          ↓
index.html ← fetch('data/dashboard_data.json'), fetch('data/prefectures.geojson')
```

## 4. 詳細設計

### 4.1 ディレクトリ移行

| 現状 | 移行先 | 手段 |
|---|---|---|
| `index.html`（v1.00） | `_legacy/index.html` | git mv |
| `rawdata/` | `_legacy/rawdata/` | git mv |
| `scripts/` | `_legacy/scripts/` | git mv |
| `data/ndb_radiation.json` | `_legacy/data/ndb_radiation.json` | git mv |
| `data/prefectures.geojson` | （上書き予定） | scripts/10 で再生成 |
| `output/` | `_legacy/output/` | git mv |
| `20260316_試験版/data/` 配下 | `rawdata_dl/` | 通常 mv（git 履歴外） |
| `20260316_試験版/*.R` | `scripts/` にコピー後改修 | cp |
| `20260316_試験版/webapp/index.html` | `index.html` にコピー後改修 | cp |
| `20260316_試験版/` 本体 | 残置（参照用） | そのまま |

### 4.2 scripts/01〜05 の改修

- 共通: 先頭の `data_dir <- file.path(getwd(), "data", ...)` 等を **`rawdata_dl` 配下** に書き換える1行修正のみ
- 02_download_facility_data.R: `data_dir <- file.path(getwd(), "rawdata_dl", "facility")`
- 03_download_physician_data.R: `data_dir <- file.path(getwd(), "rawdata_dl", "physician")`
- 04_download_population_data.R: `data_dir <- file.path(getwd(), "rawdata_dl", "population")`
- 05_download_geo_data.R: `data_dir <- file.path(getwd(), "rawdata_dl", "geo")`
- 01_download_ndb_data.R: `data_dir <- file.path(getwd(), "rawdata_dl")`（その下に `ndb_pref/`, `ndb_sma/`, `ndb_pref/*_sexage/` が掘られる）

NDB の SMA セクション、性年齢別セクションは**処理を残す**（将来用 + SCR は分母として継続使用）。

### 4.3 scripts/10_prepare_web_data.R の改修

| 変更箇所 | 内容 |
|---|---|
| `data_dir` | `file.path(base_dir, "rawdata_dl")` |
| `webapp_dir` | 廃止し、`output_dir <- file.path(base_dir, "data")` に置き換え |
| SMA セクション（2, 9c, 9d-2, 9j, 9l[sma], pop_sma 等） | パース処理は実行（変数は生成される） |
| 最終 `web_data <- list(...)` の SMA キー | コメントアウト: `counts$sma`, `population$total$sma`, `population$elderly$sma`, `facility$hospitals$sma`, `facility$radiation$sma`, `rad_doctors$sma`, トップ `sma` |
| JSON 出力先 | `data/dashboard_data.json` |
| GeoJSON コピー | `data/prefectures.geojson` のみ（`sma.geojson` のコピーはスキップ） |

将来 SMA を復活させる場合は、コメントアウトを外せばよい。

### 4.4 index.html の改修

ベース: `20260316_試験版/webapp/index.html`（1993 行）

| 改修内容 | 場所 |
|---|---|
| ヘッダ表記 | `v0.9β | 最終更新: 2026/03/17` → `v2.0 | 最終更新: 2026/05/25`（タイトル `都道府県別 算定回数マップ` も再確認） |
| 「地理単位」パネルの HTML 削除 | サイドバー先頭 |
| `curGeoUnit` 変数 | `'pref'` で固定、setGeoUnit 関数およびコール元は削除 |
| SMA 分岐コードの削除 | `curGeoUnit === 'sma'`、`DATA.sma`、`DATA.facility.*.sma`、`DATA.population.*.sma`、`DATA.rad_doctors.sma`、`GEO_SMA`、`MGEO_SMA` 等の参照 |
| 施設指標定義 `FACILITY_GROUPS` の `geo` プロパティ | `'sma'` 要素を削除（または `geo` プロパティ自体を削除） |
| 分母の有効/無効判定 | `per_nurse`/`per_rad_tech` の `curGeoUnit === 'pref'` 三項演算子を解消 |
| fetch 文 | `fetch('data/sma.geojson')` 行を削除 |
| ズーム範囲 | SMA レベルが消えるので最大ズーム値を見直し（標準のまま `[1, 50]` 範囲で問題なし） |
| 免責事項オーバーレイ | 文面・挙動ともに維持 |
| クラス名 `region-path.sma-path` | SMA ノード削除に伴い未使用、CSS は残置でも実害なし（残置） |

その他 A/B 切替、分母選択、SCR、配色、統計、CSV ダウンロード、年スライダ、再生アニメーションは **無改修** で取り込む。

### 4.5 .gitignore 更新

追加項目:

```
rawdata_dl/
_legacy/output/
```

`_legacy/scripts/`、`_legacy/index.html`、`_legacy/rawdata/`、`_legacy/data/`、`20260316_試験版/` は git に含めて履歴・再現性を保つ。

### 4.6 README.md 更新

- 「機能」セクション: A/B 切替、A/B 比、施設指標、分母 9 種、SCR、パレット選択、ズーム を追記
- 「ディレクトリ構成」セクション: 4.1 ベースの新構成に更新
- 「データパイプライン」セクション: scripts/01〜05 と 10 を順に説明
- 「必要な R パッケージ」: `foreign`（DBF読込）を追加
- 「データソース」: 既存項目 + 医療施設調査・医師統計
- 二次医療圏には言及しない

`DATA_SOURCES.md` は **無修正**。

## 5. テスト方針

R 側:
- `source("scripts/01_download_ndb_data.R")` 〜 `10_prepare_web_data.R` を順に実行し、すべてエラーなく完走することを確認
- 生成 JSON のサイズと主要キーが揃っていることを確認: `ndb.codes`, `ndb.counts.pref`, `facility.hospitals.pref`, `physician.pref`, `rad_doctors.pref`, `population.total.pref`, `prefectures`

Web 側:
- `python -m http.server` 起動 → ブラウザで以下を手動確認
  - 免責事項オーバーレイ表示・スクロール後同意→入る
  - デフォルト選択（M放射線治療系）でマップが青系で塗られる
  - A → B 切替で橙系に変化、B 側で別の項目を選べる
  - A/B 比で diverging palette（青〜赤）に変化、統計パネルが比モード表示
  - タブを「施設指標」に切替 → 病院数・医師数等が選べてマップ更新
  - 分母セレクトを順に切替（実数/人口/高齢者/SCR/各種 per_*）し、マップが反応
  - 年度スライダー操作と再生
  - パレット切替、Min/Max 手動指定、AUTO 復帰
  - ツールチップ、CSV ダウンロード
- 二次医療圏関連の UI 要素が一切出てこないことを確認

## 6. リスクと注意

- **大容量 JSON**: 試験版の `dashboard_data.json` は数 MB 級。GitHub Pages では問題ないが、SMA を除けばさらに軽くなる。除外後のサイズを確認。
- **データ再ダウンロード**: 試験版に既存の `data/` をそのまま `rawdata_dl/` にコピーすれば追加 DL 不要。R スクリプトの skip ロジックも動く。
- **SMA 削除の徹底**: `curGeoUnit === 'sma'` の分岐は webapp の多数箇所に散在する。Grep で漏れなく洗い出すこと。
- **SCR 計算は維持**: 性年齢別データのパースと SCR 計算は分母 `scr` のために残す。SMA とは独立。
- **`_legacy/` 内のリンク切れ**: `_legacy/index.html` を開いても動かない（パスが旧）。問題なしと見做す。

## 7. 受け入れ条件

- [ ] ルート `index.html` で v2.0 として全機能（A/B/比、施設指標、分母9種）が動作する
- [ ] サイドバーから「地理単位」パネルが消えている
- [ ] 二次医療圏は UI からもツールチップからも一切現れない
- [ ] `scripts/01〜05` と `10` を実行すると `data/dashboard_data.json` と `data/prefectures.geojson` が生成される
- [ ] 旧 v1.00 アセットは `_legacy/` 配下に退避済み
- [ ] README.md が v2.0 を反映している
