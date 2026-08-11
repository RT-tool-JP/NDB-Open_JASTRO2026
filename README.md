# NDB Open Data - 都道府県別ダッシュボード v2.0

NDB（レセプト情報・特定健診等情報データベース）オープンデータと医療施設調査・医師統計を組み合わせ、都道府県別の医療提供体制をインタラクティブに可視化する Web アプリケーションです。

## 機能

- **コロプレスマップ**: D3.js による都道府県別塗り分け地図（沖縄インセット、ズーム/パン対応）
- **A/B 切替・A/B 比表示**: 2 つの設定（表示A・表示B）を独立に保持。A・B 比モードは diverging palette で発散を可視化
- **年次推移モード**: 表示A / 表示B / A・B 比 の 3 サブチャートを縦並びで描画。表示値・ジニ係数・変動係数の系列をチェックボックスで切替
- **分子の選択**
  - NDB 算定（M放射線治療、K手術、D検査）— 階層チェックボックスで複数選択・合算
  - 施設指標（病院数、医師数、放射線科医、看護師、診療放射線技師、リニアック・体外照射・ガンマナイフ・腔内/組織内）
- **分母の選択（9 種）**: 実数 / 人口10万 / 65歳以上人口10万 / SCR（年齢・性別調整） / リニアック1台 / 病院1施設 / 放射線科医1人 / 看護師1人(常勤換算) / 放射線技師1人(常勤換算)
- **配色**: 7 種の sequential + 4 種の diverging + カスタムカラー。表示A/表示B/A・B比 で独立に保持
- **凡例コントロール**: デュアルレンジスライダ、min/max 手動指定、自動/手動切替
- **年度スライダー**: 2014〜2024 年度、自動再生（範囲はデータから自動導出）
- **統計パネル**: 全国合計・平均・四分位・IQR・ジニ係数・変動係数
- **CSV ダウンロード**: 表示中データの CSV エクスポート（年次推移モードでは全年度集計版）
- **免責事項**: 起動時オーバーレイ＋サイドバーから再表示可能

## デモ

ローカル起動:

```bash
# プロジェクトルートで HTTP サーバーを起動
python -m http.server 8000

# ブラウザで開く
# http://localhost:8000
```

GitHub Pages 公開時はリポジトリの Settings → Pages で Source を `master` のルートに設定してください。

## ディレクトリ構成

```
NDB-Open_2026JASTRO/
├── index.html                  Web アプリ本体（D3.js v7、シングル HTML）
├── data/                       Web アプリ配信用データ
│   ├── dashboard_data.json       全部入り JSON（scripts/10 + scripts/11 が出力）
│   ├── prefectures.geojson       都道府県境界 GeoJSON
│   ├── xofigo_drug_pref_counts.csv   ゾーフィゴ薬剤数量の都道府県別抽出結果
│   └── xofigo_drug_sources.csv       ゾーフィゴ薬剤数量の出典・抽出ログ
├── scripts/                    R データパイプライン
│   ├── 01_download_ndb_data.R          NDB Open Data ダウンロード
│   ├── 02_download_facility_data.R     医療施設調査
│   ├── 03_download_physician_data.R    医師・歯科医師・薬剤師統計
│   ├── 04_download_population_data.R   人口推計（総人口＋5歳階級別）
│   ├── 05_download_geo_data.R          地理データ（都道府県 GeoJSON）
│   ├── extract_ndb11_zip.py            第11回以降 ZIP からの xlsx 抽出（Shift-JIS 対応）
│   ├── 10_prepare_web_data.R           統合 JSON 生成
│   └── 11_add_xofigo_drug_counts.py    DL済み処方薬データからゾーフィゴをJSONへ追加
├── rawdata_dl/                 R が落とした生データ（gitignore）
├── _legacy/                    v1.00 退避（参照用、index.html 等）
├── docs/superpowers/           設計書・実装プラン
├── DATA_SOURCES.md             データソース詳細
├── LICENSE                     CC BY 4.0
└── README.md                   本ファイル
```

## データパイプライン（再現手順）

R スクリプトを順番に実行することで、生データのダウンロードから Web アプリ用 JSON の生成まで再現できます。

```r
setwd("C:/path/to/NDB-Open_2026JASTRO")
source("scripts/01_download_ndb_data.R")        # 厚労省 NDB ダウンロード
source("scripts/02_download_facility_data.R")   # e-Stat 医療施設調査
source("scripts/03_download_physician_data.R")  # e-Stat 医師統計
source("scripts/04_download_population_data.R") # 総務省 人口推計
source("scripts/05_download_geo_data.R")        # 都道府県 GeoJSON
source("scripts/10_prepare_web_data.R")         # → data/dashboard_data.json
```

ダウンロード済みファイルは skip ロジックにより再ダウンロード不要です。

ゾーフィゴ静注は医科診療行為ではなく処方薬（注射・薬効分類別数量）のため、NDB 一括収集済みデータから追加抽出します。`10_prepare_web_data.R` 実行後に次を実行してください。

```powershell
python scripts\11_add_xofigo_drug_counts.py
```

### 必要な R パッケージ

| パッケージ | 用途 |
|-----------|------|
| `readxl` | Excel (.xls/.xlsx) 読み込み |
| `dplyr` | データ操作 |
| `tidyr` | データ整形 |
| `stringr` | 文字列処理 |
| `zoo` | 前方補完 |
| `jsonlite` | JSON 出力 |
| `foreign` | DBF ファイル読み込み（A38 地理データ用） |
| `sf` | 地理空間データ |

```r
install.packages(c("readxl","dplyr","tidyr","stringr","zoo","jsonlite","foreign","sf"))
```

### Python（ZIP抽出・ゾーフィゴ追加）

第11回（FY2024）から NDB の医科診療行為（算定回数）が ZIP 一括配布に変更されました。ZIP 内のファイル名が Shift-JIS（cp932）で格納されており、UTF-8 ネイティブの R（Windows / R ≥ 4.2）の `unzip()` では正しく取り出せないため、`01_download_ndb_data.R` は標準ライブラリのみの Python ヘルパー `scripts/extract_ndb11_zip.py` を呼び出して 9 ファイル（3 指標 × 3 集計軸）を抽出します。Python 3 が PATH 上に必要です。

ゾーフィゴ抽出の `scripts/11_add_xofigo_drug_counts.py` は Excel 読み取りに `openpyxl` を使用します。

## データソース

- **NDB Open Data**: 厚生労働省 https://www.mhlw.go.jp/stf/seisakunitsuite/bunya/0000177182.html
- **医療施設調査**: e-Stat https://www.e-stat.go.jp/ (toukei=00450021)
- **医師・歯科医師・薬剤師統計**: e-Stat (toukei=00450026)
- **人口推計**: 総務省統計局 https://www.stat.go.jp/data/jinsui/2.html
- **都道府県境界**: smartnews-smri/japan-topography (国土数値情報 N03 簡素化)

詳細は [DATA_SOURCES.md](DATA_SOURCES.md) を参照してください。

## ライセンス

[CC BY 4.0](LICENSE)

本プロジェクトのコード・分析結果は CC BY 4.0 でライセンスされています。元データの利用条件は各提供元の規約に従ってください。

## バージョン履歴

- **v2.2** (2026-08-04): DL済み NDB 処方薬データからゾーフィゴ静注（医薬品コード `622489201`、薬価基準収載コード `4291432A1025`）の注射薬・都道府県別薬効分類別数量を追加。第10回・第11回は公費レセプトを含まない ZIP を使用。
- **v2.1** (2026-06-25): NDB オープンデータ第11回（FY2024）に対応。人口推計 2024・医師統計 2024・医療施設動態調査 病院数 2024 を追加。第11回からの ZIP 一括配布形式に対応（`scripts/extract_ndb11_zip.py`）。年スライダーをデータ駆動化（範囲を `DATA.ndb.years` から自動導出）。
- **v2.0** (2026-05-25): 試験版ベースに刷新。A/B 切替・A/B 比・年次推移モード、施設指標、分母 9 種を追加。
- **v1.00** (2026-02-13): 初期リリース。NDB 算定回数の人口10万あたりマップ。
