################################################################################
# 03_download_physician_data.R
# 医師・歯科医師・薬剤師統計 ダウンロードスクリプト
#
# データ元: e-Stat 医師・歯科医師・薬剤師統計
# 旧称: 医師・歯科医師・薬剤師調査 (〜2016)
# toukei=00450026
# 調査周期: 2年ごと (2014, 2016, 2018, 2020, 2022)
#
# 対象テーブル:
#   - 医師数 (都道府県別・業務の種別)
#   - 2022年のみ 二次医療圏・市区町村別も含む
################################################################################

data_dir <- file.path(getwd(), "rawdata_dl", "physician")
dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)

estat_url <- function(stat_inf_id) {
  sprintf("https://www.e-stat.go.jp/stat-search/file-download?statInfId=%s&fileKind=1",
          stat_inf_id)
}

# =============================================================================
# ファイル定義
# =============================================================================
# 都道府県別 医師数 (2年ごと)
physician_files <- list(
  # 2014: 旧調査 Table 3 (医師数・平均年齢，業務の種別・性・年齢階級・従業地による都道府県別)
  list(year = 2014, id = "000031336127", table = "T03",
       label = "医師数(業務の種別・性・年齢階級・都道府県)"),

  # 2016: Table 27 (医師数，主たる従業地による都道府県・主たる業務の種別)
  list(year = 2016, id = "000031653219", table = "T27",
       label = "医師数(都道府県・主たる業務の種別)"),

  # 2018: Table 27 (同上)
  list(year = 2018, id = "000031889120", table = "T27",
       label = "医師数(都道府県・主たる業務の種別)"),

  # 2020: Table 27 (同上)
  list(year = 2020, id = "000032179746", table = "T27",
       label = "医師数(都道府県・主たる業務の種別)"),

  # 2022: Table 25 (医療施設従事医師数 by 二次医療圏・市区町村・診療科)
  # ※二次医療圏レベルのデータも含む
  list(year = 2022, id = "000040155795", table = "T25",
       label = "医療施設従事医師数(二次医療圏・市区町村・診療科)"),

  # 2022 (令和4年): 第2表 都道府県別医師数(届出総数=343,275, 主たる業務の種別)。
  #   従来は第25表(医療施設従事医師数=327,444, 同統計の内訳1列)を流用しており
  #   系列に谷が生じていたため、届出総数の本表へ切替。列構成は2020第27表/2024第2表と同一。
  #   T02 は T25 より辞書順で先 → 都道府県別医師数パーサ(重複は先勝ち)で本表が採用される。
  #   第25表は放射線科医抽出(col37)用に引き続き使用。
  list(year = 2022, id = "000040155753", table = "T02",
       label = "医師数(主たる従業地による都道府県・主たる業務の種別)"),

  # 2024 (令和6年): 2025-12-23公表。都道府県別医師数総数は第2表を使用。
  #   ※ T02 は T26 よりファイル名が辞書順で先になるため、10_prepare の
  #     都道府県別医師数パーサ(重複は先勝ち)で第2表の総数が採用される。
  list(year = 2024, id = "000040383754", table = "T02",
       label = "医師数(主たる従業地による都道府県・主たる業務の種別)"),

  # 2024 (令和6年): 第26表。放射線科医抽出用(col37=放射線科, 2022年T25の後継)。
  #   二次医療圏・市区町村レベルの診療科(複数回答)別。
  list(year = 2024, id = "000040383778", table = "T26",
       label = "医療施設従事医師数(二次医療圏・市区町村・診療科 複数回答)")
)

# =============================================================================
# ダウンロード実行
# =============================================================================
cat("=== 医師統計 ダウンロード ===\n\n")

for (f in physician_files) {
  fname <- sprintf("physician_%s_%d.csv", f$table, f$year)
  dest <- file.path(data_dir, fname)

  if (file.exists(dest)) {
    cat(sprintf("[%d] %s => skip\n", f$year, fname))
    next
  }

  cat(sprintf("[%d] %s (%s) => downloading...", f$year, fname, f$label))
  tryCatch({
    download.file(estat_url(f$id), dest, mode = "wb", quiet = TRUE)
    cat(sprintf(" OK (%s bytes)\n", format(file.size(dest), big.mark = ",")))
  }, error = function(e) {
    cat(sprintf(" ERROR: %s\n", e$message))
  })
  Sys.sleep(1)
}

cat("\n=== 医師統計 ダウンロード完了 ===\n")

# ダウンロード済みファイル一覧
cat("\nダウンロード済みファイル:\n")
files <- list.files(data_dir, full.names = TRUE)
for (f in files) {
  cat(sprintf("  %s (%s bytes)\n", basename(f), format(file.size(f), big.mark = ",")))
}
