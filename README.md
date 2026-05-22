# NDB Open Data - 都道府県別 算定回数マップ

NDB（レセプト情報・特定健診等情報データベース）オープンデータを用いて、医科診療行為の都道府県別算定回数をインタラクティブに可視化するWebアプリケーションです。

## 機能

- **コロプレスマップ**: D3.js による都道府県別塗り分け地図（沖縄インセット付き）
- **診療行為の階層選択**: 分類コード単位でのチェックボックスツリー（複数選択・合算対応）
- **年度スライダー**: 2014〜2023年度を切り替え（自動再生アニメーション付き）
- **統計パネル**: 合計・平均・四分位・ジニ係数・変動係数をリアルタイム表示
- **凡例スケール調整**: 自動/手動切替
- **CSVダウンロード**: 表示中のデータをCSVエクスポート

## 対象データ

| 区分 | 分類コード | 内容 |
|------|-----------|------|
| M 放射線治療 | M000〜M005 | 体外照射、ガンマナイフ、粒子線治療 等 |
| K 手術 | K843〜K843-4 | 前立腺悪性腫瘍手術 等 |
| D 検査 | D413, D009 | 前立腺針生検法、腫瘍マーカー 等 |

## デモ

ローカルで動かす場合:

```bash
# プロジェクトルートで HTTP サーバーを起動
python -m http.server 8000

# ブラウザで開く
# http://localhost:8000
```

> GitHub Pages で公開する場合は、リポジトリの Settings → Pages で Source を `main` ブランチのルートに設定してください。

## ディレクトリ構成

```
NDB-Open/
├── index.html                  Webアプリ本体（D3.js）
├── data/                       Webアプリ用データ
│   ├── ndb_radiation.json        算定回数JSON（全分類・全年度）
│   └── prefectures.geojson       都道府県境界GeoJSON
├── scripts/                    Rデータパイプライン
│   ├── 01_download_ndb_data.R    NDBデータのダウンロード
│   ├── 02_analyze_M_radiation.R  M放射線治療の集計・可視化
│   ├── 03_per_capita_analysis.R  人口あたり算定回数の分析
│   ├── 04_choropleth_map.R       コロプレスマップ（静的画像）
│   └── 05_prepare_web_data.R     Webアプリ用JSON生成
├── rawdata/                    元データ（XLSX・人口推計）
│   ├── M_radiation_pref/         M放射線治療 都道府県別XLSX（10年分）
│   ├── K_surgery_pref/           K手術 都道府県別XLSX（10年分）
│   ├── D_exam_pref/              D検査 都道府県別XLSX（10年分）
│   ├── population_pref_*.xls(x)  総務省 人口推計
│   └── prefectures.geojson       都道府県境界（元ファイル）
├── output/                     分析結果（PNG・CSV）
├── DATA_SOURCES.md             データソース詳細ドキュメント
├── LICENSE                     CC BY 4.0
└── README.md                   本ファイル
```

## データパイプライン（再現手順）

Rスクリプトを順番に実行することで、元データのダウンロードからWebアプリ用JSONの生成まで再現できます。

```r
# 1. NDB Open Data のダウンロード（厚生労働省サイトから30ファイル）
source("scripts/01_download_ndb_data.R")

# 2. M放射線治療の集計・可視化（→ output/ に PNG・CSV）
source("scripts/02_analyze_M_radiation.R")

# 3. 人口あたり算定回数の分析（→ output/ に PNG・CSV）
source("scripts/03_per_capita_analysis.R")

# 4. コロプレスマップの作成（→ output/ に PNG）
source("scripts/04_choropleth_map.R")

# 5. Webアプリ用JSON生成（→ data/ に JSON・GeoJSON）
source("scripts/05_prepare_web_data.R")
```

### 必要なRパッケージ

| パッケージ | 用途 | 使用スクリプト |
|-----------|------|--------------|
| `here` | プロジェクトルート管理 | 全スクリプト |
| `readxl` | Excel (.xls/.xlsx) 読み込み | 01, 02, 03, 05 |
| `dplyr` | データ操作 | 02, 03, 04, 05 |
| `tidyr` | データ整形 | 02, 03, 05 |
| `stringr` | 文字列処理 | 02, 03, 05 |
| `zoo` | 前方補完 | 02, 05 |
| `ggplot2` | グラフ描画 | 02, 03, 04 |
| `scales` | 軸ラベル書式 | 02, 03, 04 |
| `sf` | 地理空間データ | 04 |
| `jsonlite` | JSON出力 | 05 |

```r
install.packages(c("here", "readxl", "dplyr", "tidyr", "stringr",
                    "zoo", "ggplot2", "scales", "sf", "jsonlite"))
```

## データソース

- **NDB Open Data**: 厚生労働省 https://www.mhlw.go.jp/stf/seisakunitsuite/bunya/0000177182.html
- **人口推計**: 総務省統計局 https://www.stat.go.jp/data/jinsui/2.html
- **都道府県境界**: 国土数値情報 N03（行政区域）を基に簡素化 ([smartnews-smri/japan-topography](https://github.com/smartnews-smri/japan-topography))

詳細は [DATA_SOURCES.md](DATA_SOURCES.md) を参照してください。

## ライセンス

[CC BY 4.0](LICENSE)

本プロジェクトのコード・分析結果は CC BY 4.0 でライセンスされています。
元データの利用条件は各提供元の規約に従ってください。
