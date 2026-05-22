# 使用データ一覧

本プロジェクトで使用したデータソースとその構造を記録する。

---

## 1. NDB Open Data（厚生労働省）

### 概要

- **正式名称**: NDBオープンデータ（ナショナルデータベース オープンデータ）
- **提供元**: 厚生労働省
- **ポータルページ**: https://www.mhlw.go.jp/stf/seisakunitsuite/bunya/0000177182.html
- **対象**: 医科診療行為 M放射線治療 都道府県別算定回数
- **ファイル形式**: XLSX（Excel）※ CSVではない
- **収録年度**: 第1回（H26/FY2014）〜第10回（R5/FY2023）

### 各回のページURL

| 回 | 年度 | ページURL |
|---:|------|----------|
| 1 | H26 (FY2014) | https://www.mhlw.go.jp/stf/seisakunitsuite/bunya/0000139390.html |
| 2 | H27 (FY2015) | https://www.mhlw.go.jp/stf/seisakunitsuite/bunya/0000177221.html |
| 3 | H28 (FY2016) | https://www.mhlw.go.jp/stf/seisakunitsuite/bunya/0000177221_00002.html |
| 4 | H29 (FY2017) | https://www.mhlw.go.jp/stf/seisakunitsuite/bunya/0000177221_00003.html |
| 5 | H30 (FY2018) | https://www.mhlw.go.jp/stf/seisakunitsuite/bunya/0000177221_00008.html |
| 6 | R01 (FY2019) | https://www.mhlw.go.jp/stf/seisakunitsuite/bunya/0000177221_00010.html |
| 7 | R02 (FY2020) | https://www.mhlw.go.jp/stf/seisakunitsuite/bunya/0000177221_00011.html |
| 8 | R03 (FY2021) | https://www.mhlw.go.jp/stf/seisakunitsuite/bunya/0000177221_00012.html |
| 9 | R04 (FY2022) | https://www.mhlw.go.jp/stf/seisakunitsuite/bunya/0000177221_00014.html |
| 10 | R05 (FY2023) | https://www.mhlw.go.jp/stf/seisakunitsuite/bunya/0000177221_00016.html |

### ダウンロードURL（M放射線治療 都道府県別算定回数）

| 回 | 年度 | 保存ファイル名 | ダウンロードURL |
|---:|------|---------------|----------------|
| 1 | FY2014 | `ndb01_M_radiation_pref_2014.xlsx` | https://www.mhlw.go.jp/file/06-Seisakujouhou-12400000-Hokenkyoku/0000140365.xlsx |
| 2 | FY2015 | `ndb02_M_radiation_pref_2015.xlsx` | https://www.mhlw.go.jp/file/06-Seisakujouhou-12400000-Hokenkyoku/0000177272.xlsx |
| 3 | FY2016 | `ndb03_M_radiation_pref_2016.xlsx` | https://www.mhlw.go.jp/content/12400000/000347734.xlsx |
| 4 | FY2017 | `ndb04_M_radiation_pref_2017.xlsx` | https://www.mhlw.go.jp/content/12400000/000711871.xlsx |
| 5 | FY2018 | `ndb05_M_radiation_pref_2018.xlsx` | https://www.mhlw.go.jp/content/12400000/000539735.xlsx |
| 6 | FY2019 | `ndb06_M_radiation_pref_2019.xlsx` | https://www.mhlw.go.jp/content/12400000/000821502.xlsx |
| 7 | FY2020 | `ndb07_M_radiation_pref_2020.xlsx` | https://www.mhlw.go.jp/content/12400000/001262199.xlsx |
| 8 | FY2021 | `ndb08_M_radiation_pref_2021.xlsx` | https://www.mhlw.go.jp/content/12400000/001122166.xlsx |
| 9 | FY2022 | `ndb09_M_radiation_pref_2022.xlsx` | https://www.mhlw.go.jp/content/12400000/001258359.xlsx |
| 10 | FY2023 | `ndb10_M_radiation_pref_2023.xlsx` | https://www.mhlw.go.jp/content/12400000/001493244.xlsx |

### データ構造（XLSX）

各ファイルはシート単位で外来/入院を区分。

**シート構成:**

| 回 | シート |
|----|--------|
| 第1〜2回 | `外来`, `入院` |
| 第3回以降 | `外来`, `外来（加算）`, `入院`, `入院（加算）` |

分析では `外来` と `入院` シートのみ使用（加算シートは除外）。

**レイアウト（外来・入院シート共通）:**

```
行1: 診療年月・カテゴリ等の説明文（1セル結合）
行2: (空行)
行3: ヘッダー行1  → 分類コード | 分類名称 | 診療行為コード | 診療行為名称 | 点数 | 総計 | 01 | 02 | ... | 47
行4: ヘッダー行2  → (空)       | (空)     | (空)           | (空)         | (空) | (空) | 北海道 | 青森県 | ... | 沖縄県
行5〜: データ行
```

- 列1（col A）: **分類コード** — グループの先頭行にのみ記載、以降は空欄（前方補完が必要）
- 列2（col B）: **分類名称** — 同上
- 列3（col C）: **診療行為コード**（9桁数値の文字列）
- 列4（col D）: **診療行為名称**
- 列5（col E）: **点数**
- 列6（col F）: **総計**（全国合計）
- 列7〜53（col G〜BA）: **都道府県別算定回数**（01:北海道 〜 47:沖縄県）

**秘匿処理**: 集計結果が10未満の場合は `‐`（全角ダッシュ U+2010）で表示。10未満の箇所が1箇所の場合は10以上の最小値も `‐` で表示。

**分類コード体系（M放射線治療）:**

| コード | 名称 |
|--------|------|
| M000 | 放射線治療管理料 |
| M000-2 | 放射性同位元素内用療法管理料 |
| M001 | 体外照射 |
| M001-2 | ガンマナイフによる定位放射線治療 |
| M001-3 | 直線加速器による放射線治療 |
| M001-4 | 粒子線治療 |
| M001-5 | ホウ素中性子捕捉療法（第8回〜） |
| M002 | 全身照射（一部年度のみ） |
| M003 | 電磁波温熱療法 |
| M004 | 密封小線源治療 |
| M005 | 血液照射 |

---

## 2. 人口推計（総務省統計局）

### 概要

- **正式名称**: 人口推計 各年10月1日現在人口
- **提供元**: 総務省統計局
- **ポータルページ**: https://www.stat.go.jp/data/jinsui/2.html
- **e-Stat**: https://www.e-stat.go.jp/stat-search/files?toukei=00200524
- **対象表**: 第5表「都道府県，男女別人口－総人口，日本人人口（各年10月1日現在）」
- **利用データ**: 総人口・男女計
- **ファイル形式**: XLS（旧形式）または XLSX

### ダウンロードURL

e-Stat の file-download エンドポイントから `statInfId` と `fileKind=0`（Excel形式）で取得。

| 対象年 | 収録年 | statInfId | 保存ファイル名 | ダウンロードURL |
|--------|--------|-----------|---------------|----------------|
| 2014 | 2010-2014 | 000029026254 | `population_pref_2014.xls` | https://www.e-stat.go.jp/stat-search/file-download?statInfId=000029026254&fileKind=0 |
| 2019 | 2015-2019 | 000031921674 | `population_pref_2019.xls` | https://www.e-stat.go.jp/stat-search/file-download?statInfId=000031921674&fileKind=0 |
| 2023 | 2015,2020-2023 | 000040166077 | `population_pref_2023.xlsx` | https://www.e-stat.go.jp/stat-search/file-download?statInfId=000040166077&fileKind=0 |

3ファイルを組み合わせて2014〜2023年の全10年分を構成:

- 2014年 → `population_pref_2014.xls` の最終年列
- 2015〜2019年 → `population_pref_2019.xls`
- 2020〜2023年 → `population_pref_2023.xlsx`

### データ構造

#### 旧形式（.xls）: 2014年版・2019年版

Composite Document File V2（OLE2形式）。`readxl::read_excel()` で読み取り可能。

```
行1-18: ヘッダー・メタ情報
  行13: 年ラベル（例: "平成22年", "2015年" 等）→ 列13〜17
  行15: 西暦ラベル（例: "2010", "2011", ...）→ 列13〜17
行19:   全国合計行
行20-66: 都道府県データ（01:北海道 〜 47:沖縄県）← 総人口・男女計の第1ブロック
行67〜:  第2ブロック以降（男のみ、女のみ、日本人人口等）→ 使用しない
```

**列構成:**

| 列番号 | 内容 | 備考 |
|--------|------|------|
| 1 | データ種別コード | "00500" |
| 3 | ブロック識別 | ファイルにより異なる（"01" or "06" 等） |
| 4 | 区分 | "01" |
| 8 | 地域名（全国行） | "全国" |
| 9 | 都道府県番号 | "01"〜"47"（2桁文字列） |
| 10 | 都道府県名 | "北海道　　　　" 等（全角スペースパディングあり） |
| 13〜17 | 人口（千人） | 5年分の時系列。年の対応は行13・行15で確認 |

**注意**: 第1ブロック（行20〜66の47行）が「総人口・男女計」。同じ構造の後続ブロック（男、女、日本人人口の男女計・男・女）が続くため、最初の47件のみ取得する。

#### 新形式（.xlsx）: 2023年版

e-Stat のDB書き出し形式（通常のXLSX）。

```
行1-3: 空行
行4-6: メタ情報（統計名、表番号、表題）
行7:   ヘッダー行
  列8: 人口区分  列9: 性別  列10: 都道府県コード  列11: 地域  列12: 区分  列13: 単位
  列14〜18: 年ラベル（"2015年", "2020年", "2021年", "2022年", "2023年"）
行8〜: データ行
```

**列構成:**

| 列番号 | 内容 | 値の例 |
|--------|------|--------|
| 8 | 人口区分 | "総人口", "日本人人口" |
| 9 | 性別 | "男女計", "男", "女" |
| 10 | 都道府県コード | "00000"(全国), "01000"(北海道), ... "47000"(沖縄) |
| 11 | 地域名 | "全国", "北海道", ... |
| 12 | 区分 | "人口" |
| 13 | 単位 | "千人" |
| 14〜18 | 人口（千人） | 5列分（年の構成はヘッダー行7参照） |

**フィルタ条件**: 人口区分="総人口" AND 性別="男女計" AND 都道府県コード≠"00000"

### 各年の statInfId 一覧（参考）

表番号5のstatInfIdは年度ごとに異なる。以下は追加で年度別に取得する場合の参考値。

| 対象年 | statInfId |
|--------|-----------|
| 2014 | 000029026254 |
| 2015 | （2019年版ファイルに内包） |
| 2016 | 000031560314 |
| 2017 | 000031690318 |
| 2018 | 000031807142 |
| 2019 | 000031921674 |
| 2020 | （2023年版ファイルに内包） |
| 2021 | （同上） |
| 2022 | （同上） |
| 2023 | 000040166077 |

---

## 3. 都道府県境界データ（国土数値情報）

### 概要

- **原典**: 国土交通省 国土数値情報 N03（行政区域）
- **国土数値情報ポータル**: https://nlftp.mlit.go.jp/ksj/
- **利用データ**: 都道府県単位に集約・簡素化されたGeoJSON
- **提供元（加工データ）**: smartnews-smri/japan-topography (GitHub)
- **リポジトリ**: https://github.com/smartnews-smri/japan-topography
- **ファイル形式**: GeoJSON
- **利用スクリプト**: `04_choropleth_map.R`

### ダウンロードURL

| 保存ファイル名 | ダウンロードURL |
|---------------|----------------|
| `prefectures.geojson` | https://raw.githubusercontent.com/smartnews-smri/japan-topography/main/data/municipality/geojson/s0010/prefectures.json |

※ 国土数値情報 N03（行政区域）データを都道府県単位に集約・簡素化（simplify ratio: s0010）したもの。

### データ構造（GeoJSON）

Feature Collection 形式。各 Feature が1都道府県のポリゴンに対応。

**主要プロパティ:**

| プロパティ | 内容 | 値の例 |
|-----------|------|--------|
| `N03_001` | 都道府県名 | "北海道", "青森県", ... "沖縄県" |
| `geometry` | ポリゴン（MultiPolygon） | 都道府県境界の座標列 |

- スクリプト内で `N03_001` を `pref_name` にリネームして使用
- CRS: EPSG:4326（WGS84 緯度経度）
- 47 features（47都道府県）

### ライセンス

国土数値情報は国土交通省が提供するオープンデータ。利用規約は以下を参照:
- https://nlftp.mlit.go.jp/ksj/other/agreement.html

---

## 4. ディレクトリ構成

```
NDB-Open/
├── index.html                      # Webアプリ本体（D3.js）
├── data/                           # Webアプリ用データ
│   ├── ndb_radiation.json            # 算定回数JSON（全分類・全年度）
│   └── prefectures.geojson           # 都道府県境界GeoJSON
├── scripts/                        # Rデータパイプライン
│   ├── 01_download_ndb_data.R        # NDBデータのダウンロード
│   ├── 02_analyze_M_radiation.R      # M放射線治療の都道府県別集計
│   ├── 03_per_capita_analysis.R      # 人口あたり算定回数の分析
│   ├── 04_choropleth_map.R           # コロプレスマップ（塗り分け地図）
│   └── 05_prepare_web_data.R         # Webアプリ用JSON生成
├── rawdata/                        # 元データ
│   ├── M_radiation_pref/             # NDB M放射線治療 都道府県別XLSX
│   │   ├── ndb01_M_radiation_pref_2014.xlsx
│   │   ├── ...
│   │   └── ndb10_M_radiation_pref_2023.xlsx
│   ├── K_surgery_pref/               # NDB K手術 都道府県別XLSX
│   ├── D_exam_pref/                  # NDB D検査 都道府県別XLSX
│   ├── population_pref_2014.xls      # 人口推計(2010-2014)
│   ├── population_pref_2019.xls      # 人口推計(2015-2019)
│   ├── population_pref_2023.xlsx     # 人口推計(2015,2020-2023)
│   ├── population_by_pref_year.csv   # 整形済み人口データ(出力)
│   └── prefectures.geojson           # 都道府県境界GeoJSON
├── output/                         # 分析結果
│   ├── M001_yearly_trend.png
│   ├── M001_pref_2023.png
│   ├── M001_top10_trend.png
│   ├── M001_pref_year_wide.csv
│   ├── M001_detail.csv
│   ├── M001_percapita_pref_2023.png
│   ├── M001_percapita_national_trend.png
│   ├── M001_percapita_top_bottom5.png
│   ├── M001_percapita_heatmap.png
│   ├── M001_percapita_wide.csv
│   ├── M001_percapita_detail.csv
│   ├── M001_choropleth_2023.png
│   ├── M001_deviation_map_2023.png
│   └── M001_choropleth_years.png
├── DATA_SOURCES.md                 # 本ファイル
├── README.md                       # プロジェクト説明
└── LICENSE                         # CC BY 4.0
```

---

## 5. 再現手順

```r
# 1. NDBデータのダウンロード
source("scripts/01_download_ndb_data.R")

# 2. M放射線治療の集計（TARGET_CODE を変更可能）
source("scripts/02_analyze_M_radiation.R")

# 3. 人口あたり算定回数の分析
source("scripts/03_per_capita_analysis.R")

# 4. コロプレスマップの作成（03_ の出力が必要）
source("scripts/04_choropleth_map.R")

# 5. Webアプリ用JSON生成（03_ の出力が必要）
source("scripts/05_prepare_web_data.R")
```

`02_analyze_M_radiation.R`、`03_per_capita_analysis.R`、`04_choropleth_map.R` の冒頭にある `TARGET_CODE` を変更することで、M000（放射線治療管理料）等の他の分類コードについても同様の分析が可能。

### 必要なRパッケージ

| パッケージ | 用途 | 使用スクリプト |
|-----------|------|--------------|
| `here` | プロジェクトルート管理 | 全スクリプト |
| `readxl` | Excel (.xls/.xlsx) 読み込み | 01, 02, 03, 05 |
| `dplyr` | データ操作 | 02, 03, 04, 05 |
| `tidyr` | データ整形（pivot等） | 02, 03, 05 |
| `stringr` | 文字列処理 | 02, 03, 05 |
| `zoo` | 前方補完 (`na.locf`) | 02, 05 |
| `ggplot2` | グラフ描画 | 02, 03, 04 |
| `scales` | 軸ラベルの書式 | 02, 03, 04 |
| `sf` | 地理空間データ（GeoJSON読み込み・描画） | 04 |
| `jsonlite` | JSON出力 | 05 |
