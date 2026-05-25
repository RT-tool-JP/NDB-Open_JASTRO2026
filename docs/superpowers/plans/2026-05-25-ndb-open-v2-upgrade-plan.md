# NDB Open Data v2.0 アップグレード実装プラン

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 現行 v1.00 を試験版ベースの v2.0 に置き換え、A/B 切替・A/B 比表示・施設指標・分母9種を有効化し、二次医療圏 UI は除去する。

**Architecture:** ルート `index.html`（試験版コピー + SMA削除）+ `data/{dashboard_data.json, prefectures.geojson}` + `scripts/01〜05, 10*.R`。現行アセットは `_legacy/` 退避、生データは `rawdata_dl/`（gitignore）。

**Tech Stack:** D3.js v7（CDN）、R（readxl, dplyr, tidyr, stringr, jsonlite, zoo, foreign）、Python http.server（ローカル確認用）。

**Spec:** [docs/superpowers/specs/2026-05-25-ndb-open-v2-upgrade-design.md](../specs/2026-05-25-ndb-open-v2-upgrade-design.md)

---

## Phase 1: ディレクトリ再編とレガシ退避

### Task 1: .gitignore に rawdata_dl/ と _legacy/output/ を追加

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: .gitignore 末尾に追記**

```
# v2.0 additions
rawdata_dl/
_legacy/output/
```

- [ ] **Step 2: コミット**

```bash
git add .gitignore
git commit -m "chore: gitignore rawdata_dl and _legacy/output"
```

---

### Task 2: 現行 v1.00 アセットを _legacy/ に git mv で退避

**Files:**
- Move: `index.html` → `_legacy/index.html`
- Move: `rawdata/` → `_legacy/rawdata/`
- Move: `scripts/` → `_legacy/scripts/`
- Move: `data/ndb_radiation.json` → `_legacy/data/ndb_radiation.json`
- Move: `data/prefectures.geojson` → `_legacy/data/prefectures.geojson`
- Move: `output/` → `_legacy/output/`

- [ ] **Step 1: _legacy/ ディレクトリ作成**

```bash
mkdir -p _legacy/data
```

- [ ] **Step 2: git mv で各アセット退避**

```bash
git mv index.html _legacy/index.html
git mv rawdata _legacy/rawdata
git mv scripts _legacy/scripts
git mv data/ndb_radiation.json _legacy/data/ndb_radiation.json
git mv data/prefectures.geojson _legacy/data/prefectures.geojson
git mv output _legacy/output
```

- [ ] **Step 3: data ディレクトリは残骸なので空のまま維持確認**

```bash
ls data/
```
Expected: 何も表示されない（空ディレクトリ）

- [ ] **Step 4: コミット**

```bash
git commit -m "refactor: 現行v1.00アセットを_legacy/に退避"
```

---

### Task 3: 試験版データを rawdata_dl/ に移動（git追跡外）

**Files:**
- Move: `20260316_試験版/data/*` → `rawdata_dl/*`

- [ ] **Step 1: rawdata_dl/ 作成**

```bash
mkdir -p rawdata_dl
```

- [ ] **Step 2: 試験版データを丸ごと移動**

PowerShell:
```powershell
Move-Item "20260316_試験版/data/*" "rawdata_dl/"
```
または Bash:
```bash
mv "20260316_試験版/data/"* rawdata_dl/
```

- [ ] **Step 3: 移動結果確認**

```bash
ls rawdata_dl/
```
Expected: `ndb_pref/  ndb_sma/  facility/  physician/  population/  geo/` などが表示される

- [ ] **Step 4: 移動先の主要ファイル存在確認**

```bash
ls rawdata_dl/ndb_pref/M_radiation_pref/ | head -3
ls rawdata_dl/geo/
```
Expected: `ndb01_M_radiation_pref_2014.xlsx` などのファイル、`prefectures.geojson sma.geojson` 等が表示

- [ ] **Step 5: git status で追跡外確認**

```bash
git status
```
Expected: rawdata_dl/ は ignored で出てこないか、untracked でも .gitignore により後で除外される

---

## Phase 2: R スクリプト移植と JSON 生成

### Task 4: scripts/01〜05 を試験版から移植

**Files:**
- Create: `scripts/01_download_ndb_data.R`
- Create: `scripts/02_download_facility_data.R`
- Create: `scripts/03_download_physician_data.R`
- Create: `scripts/04_download_population_data.R`
- Create: `scripts/05_download_geo_data.R`

- [ ] **Step 1: scripts/ 新規作成**

```bash
mkdir -p scripts
```

- [ ] **Step 2: 試験版から 01〜05 をコピー**

```bash
cp "20260316_試験版/01_download_ndb_data.R"        scripts/
cp "20260316_試験版/02_download_facility_data.R"   scripts/
cp "20260316_試験版/03_download_physician_data.R"  scripts/
cp "20260316_試験版/04_download_population_data.R" scripts/
cp "20260316_試験版/05_download_geo_data.R"        scripts/
```

- [ ] **Step 3: 各スクリプトの data_dir を rawdata_dl 配下に書き換え**

| ファイル | 旧 | 新 |
|---|---|---|
| `scripts/01_download_ndb_data.R` | `data_dir <- file.path(getwd(), "data")` | `data_dir <- file.path(getwd(), "rawdata_dl")` |
| `scripts/02_download_facility_data.R` | `data_dir <- file.path(getwd(), "data", "facility")` | `data_dir <- file.path(getwd(), "rawdata_dl", "facility")` |
| `scripts/03_download_physician_data.R` | `data_dir <- file.path(getwd(), "data", "physician")` | `data_dir <- file.path(getwd(), "rawdata_dl", "physician")` |
| `scripts/04_download_population_data.R` | `data_dir <- file.path(getwd(), "data", "population")` | `data_dir <- file.path(getwd(), "rawdata_dl", "population")` |
| `scripts/05_download_geo_data.R` | `data_dir <- file.path(getwd(), "data", "geo")` | `data_dir <- file.path(getwd(), "rawdata_dl", "geo")` |

Edit tool で各ファイルの `data_dir <-` 行を書き換える。

- [ ] **Step 4: 動作確認（DL skip 確認）**

R を起動して以下を実行（既にデータがあるので skip ログが出れば OK）:

```r
setwd("C:/Git/NDB-Open_2026JASTRO")
source("scripts/01_download_ndb_data.R")
```
Expected: 既存ファイルは `=> skip` でログ出力されエラーなし

- [ ] **Step 5: コミット**

```bash
git add scripts/01_download_ndb_data.R scripts/02_download_facility_data.R scripts/03_download_physician_data.R scripts/04_download_population_data.R scripts/05_download_geo_data.R
git commit -m "feat: scripts/01-05を試験版から移植、data_dirをrawdata_dl/に変更"
```

---

### Task 5: scripts/10_prepare_web_data.R を移植してパス改修

**Files:**
- Create: `scripts/10_prepare_web_data.R`

- [ ] **Step 1: 試験版から 10 をコピー**

```bash
cp "20260316_試験版/10_prepare_web_data.R" scripts/
```

- [ ] **Step 2: data_dir と webapp_dir/output_dir を書き換え**

Edit tool で:

旧:
```r
data_dir <- file.path(base_dir, "data")
webapp_dir <- file.path(base_dir, "webapp")
dir.create(file.path(webapp_dir, "data"), recursive = TRUE, showWarnings = FALSE)
```

新:
```r
data_dir <- file.path(base_dir, "rawdata_dl")
output_dir <- file.path(base_dir, "data")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
```

- [ ] **Step 3: JSON 出力先の書き換え**

旧:
```r
json_path <- file.path(webapp_dir, "data", "dashboard_data.json")
```

新:
```r
json_path <- file.path(output_dir, "dashboard_data.json")
```

- [ ] **Step 4: GeoJSON コピー先の書き換え**

旧（10. GeoJSONコピー セクション）:
```r
geo_files <- list(
  c(file.path(data_dir, "geo/prefectures.geojson"),
    file.path(webapp_dir, "data/prefectures.geojson")),
  c(file.path(data_dir, "geo/sma.geojson"),
    file.path(webapp_dir, "data/sma.geojson"))
)
```

新（pref のみ、SMA はマーカー付きでコメントアウト）:
```r
geo_files <- list(
  c(file.path(data_dir, "geo/prefectures.geojson"),
    file.path(output_dir, "prefectures.geojson"))
  # [v2.0-sma-disabled] 将来 SMA 表示を復活させる場合は次行のコメントを外す
  # , c(file.path(data_dir, "geo/sma.geojson"), file.path(output_dir, "sma.geojson"))
)
```

---

### Task 6: scripts/10 の web_data list から SMA キーを除外

**Files:**
- Modify: `scripts/10_prepare_web_data.R` の `web_data <- list(...)` ブロック（spec 4.3 参照）

- [ ] **Step 1: web_data 組み立て部を編集**

旧:
```r
web_data <- list(
  ndb = list(
    codes = codes_hierarchy,
    years = 2014:2023,
    counts = list(pref = ndb_pref_counts, sma = ndb_sma_counts),
    scr = list(pref = scr_nested)
  ),
  facility = list(
    hospitals = list(pref = hospitals_pref_nested, sma = hospitals_sma_nested),
    radiation = list(items = rt_items_list,
                     pref = radiation_nested,
                     sma = radiation_sma_nested),
    staff = staff_nested
  ),
  physician = list(pref = physician_nested),
  rad_doctors = list(pref = rad_doctor_pref_nested, sma = rad_doctor_sma_nested),
  population = list(
    total = list(pref = pop_total_nested, sma = pop_total_sma_nested),
    elderly = list(pref = pop_elderly_nested, sma = pop_elderly_sma_nested)
  ),
  prefectures = setNames(as.list(pref_names), pref_codes),
  sma = list(
    regions = sma_regions,
    years = if (nrow(ndb_sma_agg) > 0) sort(unique(ndb_sma_agg$fy_year)) else integer()
  )
)
```

新:
```r
web_data <- list(
  ndb = list(
    codes = codes_hierarchy,
    years = 2014:2023,
    counts = list(pref = ndb_pref_counts
      # [v2.0-sma-disabled] , sma = ndb_sma_counts
    ),
    scr = list(pref = scr_nested)
  ),
  facility = list(
    hospitals = list(pref = hospitals_pref_nested
      # [v2.0-sma-disabled] , sma = hospitals_sma_nested
    ),
    radiation = list(items = rt_items_list,
                     pref = radiation_nested
      # [v2.0-sma-disabled] , sma = radiation_sma_nested
    ),
    staff = staff_nested
  ),
  physician = list(pref = physician_nested),
  rad_doctors = list(pref = rad_doctor_pref_nested
    # [v2.0-sma-disabled] , sma = rad_doctor_sma_nested
  ),
  population = list(
    total = list(pref = pop_total_nested
      # [v2.0-sma-disabled] , sma = pop_total_sma_nested
    ),
    elderly = list(pref = pop_elderly_nested
      # [v2.0-sma-disabled] , sma = pop_elderly_sma_nested
    )
  ),
  prefectures = setNames(as.list(pref_names), pref_codes)
  # [v2.0-sma-disabled] , sma = list(regions = sma_regions, years = if (nrow(ndb_sma_agg) > 0) sort(unique(ndb_sma_agg$fy_year)) else integer())
)
```

- [ ] **Step 2: grep で [v2.0-sma-disabled] マーカー数を確認**

```bash
grep -n "v2.0-sma-disabled" scripts/10_prepare_web_data.R
```
Expected: 8 行ヒット（counts, hospitals, radiation, rad_doctors, pop_total, pop_elderly, sma トップ, geo_files）

---

### Task 7: scripts/10 を実行して dashboard_data.json と prefectures.geojson を生成

**Files:**
- Generate: `data/dashboard_data.json`
- Generate: `data/prefectures.geojson`

- [ ] **Step 1: R で 10 を実行**

R で以下:

```r
setwd("C:/Git/NDB-Open_2026JASTRO")
source("scripts/10_prepare_web_data.R")
```

Expected: `=== 完了 ===` まで到達、エラーなし。途中ログに各セクション処理件数が表示される。

- [ ] **Step 2: 出力ファイル確認**

```bash
ls -la data/
```
Expected: `dashboard_data.json`（数 MB）と `prefectures.geojson` が存在

- [ ] **Step 3: JSON 主要キー確認**

PowerShell:
```powershell
Get-Content data/dashboard_data.json -Head 1 | Out-String | Select-String -Pattern '"ndb"','"facility"','"physician"','"rad_doctors"','"population"','"prefectures"'
```
Bash:
```bash
head -c 2000 data/dashboard_data.json | grep -oE '"(ndb|facility|physician|rad_doctors|population|prefectures|sma)"' | sort -u
```

Expected: `ndb`, `facility`, `physician`, `rad_doctors`, `population`, `prefectures` の 6 キー。**`sma` は出てこないこと**。

- [ ] **Step 4: コミット**

```bash
git add scripts/10_prepare_web_data.R data/dashboard_data.json data/prefectures.geojson
git commit -m "feat: scripts/10で都道府県のみJSON生成（SMAは[v2.0-sma-disabled]マーカー付きで保留）"
```

---

## Phase 3: index.html を試験版ベースで構築

### Task 8: 試験版 webapp/index.html をルートにコピーしてヘッダ更新

**Files:**
- Create: `index.html`

- [ ] **Step 1: コピー**

```bash
cp "20260316_試験版/webapp/index.html" index.html
```

- [ ] **Step 2: ヘッダ表記を v2.0 に書き換え**

Edit tool で:

旧:
```html
<div class="sub">都道府県別・二次医療圏別 算定回数マップ <span style="margin-left:6px;font-size:10px;opacity:.6">v0.9β | 最終更新: 2026/03/17</span></div>
```

新:
```html
<div class="sub">都道府県別 算定回数マップ <span style="margin-left:6px;font-size:10px;opacity:.6">v2.0 | 最終更新: 2026/05/25</span></div>
```

- [ ] **Step 3: title 要素も書き換え**

旧:
```html
<title>NDB Open Data - 拡張ダッシュボード</title>
```

新:
```html
<title>NDB Open Data - 都道府県別 算定回数マップ</title>
```

---

### Task 9: 「地理単位」パネル HTML を削除

**Files:**
- Modify: `index.html`（サイドバー先頭の panel）

- [ ] **Step 1: 削除対象を特定**

```bash
grep -n '地理単位\|setGeoUnit\|data-geo=' index.html
```

- [ ] **Step 2: パネル全体を削除**

以下のブロックを丸ごと削除:

```html
      <div class="panel">
        <h3>地理単位</h3>
        <div class="toggle-group">
          <button class="toggle-btn active" data-geo="pref" onclick="setGeoUnit('pref')">都道府県</button>
          <button class="toggle-btn" data-geo="sma" onclick="setGeoUnit('sma')">二次医療圏</button>
        </div>
      </div>
```

---

### Task 10: fetch を pref のみに簡約、GEO_SMA/MGEO_SMA 変数削除

**Files:**
- Modify: `index.html`（init() 関数と関連グローバル変数）

- [ ] **Step 1: init() の Promise.all を 2 本に縮める**

旧:
```js
const [gr, sr, dr] = await Promise.all([
  fetch('data/prefectures.geojson'),
  fetch('data/sma.geojson'),
  fetch('data/dashboard_data.json')
]);
GEO_PREF = await gr.json();
GEO_SMA = await sr.json();
DATA = await dr.json();
```

新:
```js
const [gr, dr] = await Promise.all([
  fetch('data/prefectures.geojson'),
  fetch('data/dashboard_data.json')
]);
GEO_PREF = await gr.json();
DATA = await dr.json();
```

- [ ] **Step 2: グローバル変数宣言から GEO_SMA / MGEO_SMA を削除**

旧:
```js
let DATA = null, GEO_PREF = null, GEO_SMA = null;
let MGEO_PREF = null, MGEO_SMA = null;
```

新:
```js
let DATA = null, GEO_PREF = null;
let MGEO_PREF = null;
```

- [ ] **Step 3: curGeoUnit グローバル変数を削除**

旧:
```js
/* Shared state (applies to both A and B) */
let curGeoUnit = 'pref';
```

新（行ごと削除）。

---

### Task 11: SMA 分岐を 6 カテゴリ別に削除

**Files:**
- Modify: `index.html`（JS 全域）

このタスクは大物。spec 4.4.2 のカテゴリ表に従って機械的に削除する。

- [ ] **Step 1: 削除前の参照数カウント**

```bash
grep -cE "sma|SMA|GeoUnit|curGeoUnit" index.html
```
Expected: 約 64 件

- [ ] **Step 2: 関数 `setGeoUnit` 自体を削除**

`function setGeoUnit(` から関数の閉じ `}` までを削除。

- [ ] **Step 3: アクセサ関数を pref 固定に簡約**

| 関数 | 改修内容 |
|---|---|
| `getRegionCodes()` | `Object.keys(DATA.prefectures)` 固定 |
| `getRegionName(code)` | `DATA.prefectures[code] \|\| code` 固定 |
| `getFacilitySource(indicator)` | 各 if 文の三項演算子 `curGeoUnit === 'pref' ? X : Y` を `X` に簡約 |
| `getDenomSource()` | 同上 |
| `getEffectiveDenom()` | `per_linac`/`per_nurse`/`per_rad_tech`/`per_rad_doctor` の curGeoUnit 三項演算子を簡約。`per_linac` は `DATA.facility.radiation.pref?.rt_linac_units` の有無のみで判定 |

例（`getDenomSource()`）:

旧:
```js
function getDenomSource() {
  const eff = getEffectiveDenom();
  if (eff === 'pop100k') return curGeoUnit === 'pref' ? DATA.population.total?.pref : DATA.population.total?.sma;
  if (eff === 'eld100k') return curGeoUnit === 'pref' ? DATA.population.elderly?.pref : DATA.population.elderly?.sma;
  if (eff === 'per_linac') return curGeoUnit === 'pref' ? DATA.facility.radiation.pref?.rt_linac_units : DATA.facility.radiation.sma?.rt_linac_units;
  if (eff === 'per_hospital') return curGeoUnit === 'pref' ? DATA.facility.hospitals.pref : DATA.facility.hospitals.sma;
  if (eff === 'per_rad_doctor') return curGeoUnit === 'pref' ? DATA.rad_doctors?.pref : DATA.rad_doctors?.sma;
  if (eff === 'per_nurse') return DATA.facility.staff?.nurses;
  if (eff === 'per_rad_tech') return DATA.facility.staff?.rad_technologists;
  return null;
}
```

新:
```js
function getDenomSource() {
  const eff = getEffectiveDenom();
  if (eff === 'pop100k') return DATA.population.total?.pref;
  if (eff === 'eld100k') return DATA.population.elderly?.pref;
  if (eff === 'per_linac') return DATA.facility.radiation.pref?.rt_linac_units;
  if (eff === 'per_hospital') return DATA.facility.hospitals.pref;
  if (eff === 'per_rad_doctor') return DATA.rad_doctors?.pref;
  if (eff === 'per_nurse') return DATA.facility.staff?.nurses;
  if (eff === 'per_rad_tech') return DATA.facility.staff?.rad_technologists;
  return null;
}
```

`getFacilitySource()` も同様に簡約。

- [ ] **Step 4: `FACILITY_GROUPS` の各 item から `geo` プロパティを削除**

旧:
```js
{ id: 'hospitals', name: '病院数', unit: '施設', geo: ['pref','sma'] },
```

新:
```js
{ id: 'hospitals', name: '病院数', unit: '施設' },
```

すべての item で `geo:` プロパティ自体を削除。

- [ ] **Step 5: 施設指標リスト描画の disabled 判定を削除**

`buildFacList()` または `renderFac` 系で `item.geo.includes(curGeoUnit)` を使った disabled 制御を削除。

- [ ] **Step 6: CSV ファイル名生成の curGeoUnit を pref リテラルに**

旧:
```js
a.download = `ratio_${curGeoUnit}_${yr}.csv`;
```

新:
```js
a.download = `ratio_pref_${yr}.csv`;
```

他の `${curGeoUnit}_${yr}.csv` 系も同様に置換。

- [ ] **Step 7: SMA 関連エラーメッセージ・分岐を削除**

`curGeoUnit === 'sma'` ブロック、`DATA.sma.regions` 直接参照、`!DATA.sma` 系チェックを全削除。

- [ ] **Step 8: initMap / drawMap の SMA レイヤ描画を削除**

`if (curGeoUnit === 'sma') ...` で SMA GeoJSON を描画している箇所を全削除し、pref のみの描画に統一。

- [ ] **Step 9: hasDataForConfig 等の判定関数から SMA 分岐を削除**

`curGeoUnit` を参照しているあらゆる箇所を pref 前提に書き換える。

- [ ] **Step 10: CSS の `.region-path.sma-path` ルールを削除**

旧:
```css
.region-path.sma-path{stroke-width:.3}
.region-path.sma-path.hovered{stroke-width:1.2}
```

新（行ごと削除）。

---

### Task 12: SMA 削除完了の grep 検証

**Files:**
- Verify: `index.html`

- [ ] **Step 1: 削除完了の機械的チェック**

```bash
grep -nE "sma|SMA|GeoUnit|curGeoUnit" index.html
```
Expected: **0 件**

- [ ] **Step 2: 特定識別子の二重確認**

```bash
grep -nE "sma\.geojson|DATA\.sma|GEO_SMA|MGEO_SMA|setGeoUnit|curGeoUnit" index.html
```
Expected: **0 件**

- [ ] **Step 3: ヒット時の対応**

ヒットがあれば spec 4.4.2 のカテゴリ表に当てはめて削除を繰り返す。コメント文字列内の SMA も削除対象。

- [ ] **Step 4: コミット**

```bash
git add index.html
git commit -m "feat: index.htmlをv2.0化（試験版ベース、SMA関連を全削除）"
```

---

## Phase 4: 動作確認

### Task 13: ローカルサーバでブラウザ動作確認

**Files:**
- Test: `index.html` をブラウザで開く

- [ ] **Step 1: HTTP サーバ起動（バックグラウンド）**

```bash
cd C:/Git/NDB-Open_2026JASTRO
python -m http.server 8000
```

- [ ] **Step 2: ブラウザで開く**

`http://localhost:8000/` にアクセス。

- [ ] **Step 3: 免責事項オーバーレイ確認**

- 表示される
- スクロールしてチェックボックス活性化
- 「利用開始」で消える

- [ ] **Step 4: 初期表示確認**

- マップが青系で塗られる（A モード、人口10万人あたり、M放射線治療の初期選択）
- サイドバー先頭が「表示値（分母）」になっており「地理単位」が**ない**
- ヘッダ右側に A / B / A/B比 ボタン
- 統計パネル右上に全国合計・平均・四分位等

- [ ] **Step 5: A/B 切替確認**

- ヘッダ A → B クリック → 配色が橙系に変化
- 「設定対象: A | B」が表示される
- B 側で別の項目を選択し、A に戻すと A 側の設定が復元される

- [ ] **Step 6: A/B 比表示**

- ヘッダ「A/B比」クリック → diverging palette（青〜白〜赤）に変化
- 統計パネルが「A / B 比」モード表示

- [ ] **Step 7: タブ切替**

- 「NDB算定」→「施設指標」に切替
- 病院数・医師数・放射線科医等が選択可能
- すべて pref データなので disabled な項目がない

- [ ] **Step 8: 分母セレクト 9 種を順次確認**

実数 / 人口10万 / 65歳以上10万 / SCR / リニアック / 病院 / 放射線科医 / 看護師 / 技師
それぞれでマップが反応すること、unit ラベルが切り替わること。

- [ ] **Step 9: 年スライダ・再生**

- スライダ操作
- ▶ 再生ボタンでアニメーション
- ストップ可能

- [ ] **Step 10: パレット・凡例コントロール**

- 凡例ホバーで設定パネル出現
- Min/Max 手動入力 → 適用 → 手動バッジ
- 自動ボタン → AUTO バッジ復帰
- パレット 7 種 + diverging 4 種切替

- [ ] **Step 11: ツールチップ・CSV**

- マップ上の都道府県にホバー → ツールチップ表示（県名・分子・分母・比）
- 「CSV ダウンロード」→ ファイル名が `ratio_pref_2023.csv` または `ndb_pref_2023.csv` 等の pref 含む形式

- [ ] **Step 12: DevTools コンソール確認**

- F12 でコンソールを開く
- リロード → エラー 0 件、警告 0 件（特に `sma` や `undefined is not iterable` 等が出ないこと）

- [ ] **Step 13: HTTP サーバ停止**

```bash
# Ctrl+C または kill (バックグラウンド時)
```

---

### Task 14: README.md 更新

**Files:**
- Modify: `README.md`

- [ ] **Step 1: タイトル下リード文を更新**

```markdown
# NDB Open Data - 都道府県別ダッシュボード v2.0

NDB（レセプト情報・特定健診等情報データベース）オープンデータと医療施設調査・医師統計を組み合わせ、都道府県別の医療提供体制をインタラクティブに可視化するWebアプリケーションです。
```

- [ ] **Step 2: 機能セクション書き換え**

```markdown
## 機能

- **コロプレスマップ**: D3.js による都道府県別塗り分け地図（沖縄インセット付き、ズーム/パン対応）
- **A/B 切替・A/B 比表示**: 2 つの設定（A・B）を独立に保持、A/B 比は diverging palette
- **分子の選択**:
  - NDB 算定（M放射線治療、K手術、D検査）— 階層チェックボックスで複数選択
  - 施設指標（病院数、医師数、放射線科医、看護師、診療放射線技師、リニアック・体外照射・ガンマナイフ・腔内/組織内）
- **分母の選択（9 種）**: 実数 / 人口10万 / 65歳以上人口10万 / SCR（年齢・性別調整） / リニアック1台 / 病院1施設 / 放射線科医1人 / 看護師1人 / 放射線技師1人
- **年度スライダー**: 2014〜2023 年度、自動再生
- **統計パネル**: 合計・平均・四分位・IQR・ジニ係数・変動係数
- **凡例コントロール**: デュアルレンジスライダ、自動/手動切替、7 色 sequential + 4 色 diverging パレット + カスタム
- **CSV ダウンロード**: 表示中データの CSV エクスポート
```

- [ ] **Step 3: ディレクトリ構成セクションを spec 4.1 ベースに更新**

```markdown
## ディレクトリ構成

\`\`\`
NDB-Open_2026JASTRO/
├── index.html                  v2.0 Webアプリ本体（D3.js）
├── data/                       Webアプリ配信用データ
│   ├── dashboard_data.json       全部入り JSON（scripts/10 出力）
│   └── prefectures.geojson       都道府県境界 GeoJSON
├── scripts/                    R データパイプライン
│   ├── 01_download_ndb_data.R          NDB Open Data ダウンロード
│   ├── 02_download_facility_data.R     医療施設調査
│   ├── 03_download_physician_data.R    医師統計
│   ├── 04_download_population_data.R   人口推計
│   ├── 05_download_geo_data.R          地理データ
│   └── 10_prepare_web_data.R           統合 JSON 生成
├── rawdata_dl/                 R が落とした生データ（gitignore）
├── _legacy/                    v1.00 退避（参照用）
├── DATA_SOURCES.md             データソース詳細
├── LICENSE                     CC BY 4.0
└── README.md                   本ファイル
\`\`\`
```

- [ ] **Step 4: データパイプラインセクション**

```markdown
## データパイプライン

R スクリプトを順次実行:

\`\`\`r
setwd("C:/path/to/NDB-Open_2026JASTRO")
source("scripts/01_download_ndb_data.R")        # NDB ダウンロード
source("scripts/02_download_facility_data.R")   # 医療施設調査
source("scripts/03_download_physician_data.R")  # 医師統計
source("scripts/04_download_population_data.R") # 人口
source("scripts/05_download_geo_data.R")        # 地理
source("scripts/10_prepare_web_data.R")         # → data/dashboard_data.json
\`\`\`

必要パッケージ:

\`\`\`r
install.packages(c("here","readxl","dplyr","tidyr","stringr","zoo","jsonlite","foreign"))
\`\`\`
```

- [ ] **Step 5: コミット**

```bash
git add README.md
git commit -m "docs: README.mdをv2.0に更新"
```

---

### Task 15: 最終確認とマージ準備

**Files:**
- Verify: 全体

- [ ] **Step 1: git log で変更履歴確認**

```bash
git log --oneline -10
```

- [ ] **Step 2: 全ファイルがコミット済みであることを確認**

```bash
git status
```
Expected: working tree clean（rawdata_dl/ は ignored）

- [ ] **Step 3: ブラウザで最終確認**

`python -m http.server 8000` で再起動し、Task 13 の全項目を 1 回パスする。

- [ ] **Step 4: 完了報告**

`docs/superpowers/specs/2026-05-25-ndb-open-v2-upgrade-design.md` の「受け入れ条件」6 項目を 1 つずつチェック:

- [ ] ルート `index.html` で v2.0 として全機能（A/B/比、施設指標、分母9種）が動作する
- [ ] サイドバーから「地理単位」パネルが消えている
- [ ] 二次医療圏は UI からもツールチップからも一切現れない
- [ ] `scripts/01〜05` と `10` を実行すると `data/dashboard_data.json` と `data/prefectures.geojson` が生成される
- [ ] 旧 v1.00 アセットは `_legacy/` 配下に退避済み
- [ ] README.md が v2.0 を反映している

すべて満たせば v2.0 アップグレード完了。

---

## ロールバック手順

万一不具合があった場合:

```bash
# 完了直前のコミットに戻る
git reset --hard <commit-before-v2.0>

# または特定タスクのみ取り消し
git revert <commit-hash>
```

`_legacy/index.html` から旧 v1.00 を復活させる場合:

```bash
git mv _legacy/index.html index.html
git mv _legacy/data/ndb_radiation.json data/ndb_radiation.json
git mv _legacy/data/prefectures.geojson data/prefectures.geojson
```
