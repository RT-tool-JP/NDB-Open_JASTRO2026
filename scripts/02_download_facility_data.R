################################################################################
# 02_download_facility_data.R
# 医療施設調査 ダウンロードスクリプト
#
# データ元: e-Stat 医療施設調査 (toukei=00450021, tstat=000001030908)
# https://www.e-stat.go.jp/stat-search/files?toukei=00450021&tstat=000001030908
#
# 対象:
#   1. 都道府県別 病院数 (T1/G1) - 毎年
#   2. 都道府県別 従事者数 (T81/G31) - 静態調査年 (2014,2017,2020,2023)
#   3. 都道府県別 放射線治療 (T75/E65) - 静態調査年
#   4. 都道府県別 100床あたり従事者数 (T85/G32) - 静態調査年
#   5. 都道府県別 常勤換算医師数 (T88/G33/G17) - 静態調査年
#   6. 二次医療圏別 病院数 (N1/E1) - 静態調査年
#
# ダウンロードURL:
#   https://www.e-stat.go.jp/stat-search/file-download?statInfId=XXX&fileKind=1
#   ※ fileKind=1 (CSV形式)
################################################################################

data_dir <- file.path(getwd(), "rawdata_dl", "facility")
dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)

estat_url <- function(stat_inf_id) {
  sprintf("https://www.e-stat.go.jp/stat-search/file-download?statInfId=%s&fileKind=1",
          stat_inf_id)
}

# =============================================================================
# 1. 都道府県別 病院数 (T1/G1) - 毎年利用可能
# =============================================================================
hospital_count_files <- list(
  list(year = 2014, id = "000031336317", table = "G1"),
  list(year = 2015, id = "000031448426", table = "G1"),
  list(year = 2016, id = "000031627841", table = "G1"),
  list(year = 2017, id = "000031780608", table = "G1"),
  list(year = 2018, id = "000031862110", table = "T1"),
  list(year = 2019, id = "000031982258", table = "T1"),
  list(year = 2020, id = "000032191859", table = "T1"),
  list(year = 2021, id = "000032235643", table = "T1"),
  list(year = 2022, id = "000040102812", table = "T1"),
  list(year = 2023, id = "000040222772", table = "T1"),
  # 令和6年(2024)動態調査 都道府県編 第1表 病院数(2025-09-26公開)
  list(year = 2024, id = "000040321933", table = "T1")
)

# =============================================================================
# 2. 都道府県別 従事者数 (T81/G31) - 静態調査年のみ
# =============================================================================
staff_files <- list(
  # 2014: G17は医師数(常勤換算)のみ。包括的な従事者表は上巻にある
  list(year = 2017, id = "000031780638", table = "G31",
       label = "従事者数(職種・都道府県・精神科-一般病院)"),
  list(year = 2020, id = "000032191940", table = "T82",
       label = "従事者数(職種・都道府県・精神科-一般病院)"),
  list(year = 2023, id = "000040222852", table = "T81",
       label = "従事者数(職種・都道府県・精神科-一般病院)")
)

# =============================================================================
# 3. 都道府県別 放射線治療 (T75/E65) - 静態調査年のみ
# =============================================================================
radiation_files <- list(
  list(year = 2014, id = "000031336444", table = "E65"),
  list(year = 2017, id = "000031780738", table = "E65"),
  list(year = 2020, id = "000032191933", table = "T75"),
  list(year = 2023, id = "000040222846", table = "T75")
)

# =============================================================================
# 4. 都道府県別 100床あたり従事者数 (T85/G32) - 静態調査年のみ
# =============================================================================
staff_per_bed_files <- list(
  list(year = 2017, id = "000031780639", table = "G32"),
  list(year = 2020, id = "000032191943", table = "T85"),
  list(year = 2023, id = "000040222856", table = "T85")
)

# =============================================================================
# 5. 都道府県別 常勤換算医師数 (T88/G33/G17) - 静態調査年
# =============================================================================
fte_physician_files <- list(
  list(year = 2014, id = "000031336333", table = "G17",
       label = "医師数(常勤換算・性・診療科目・都道府県)"),
  list(year = 2017, id = "000031780640", table = "G33",
       label = "常勤換算医師数・人口10万対(年次・都道府県)"),
  list(year = 2020, id = "000032191947", table = "T89",
       label = "常勤換算医師数・人口10万対(年次・都道府県)"),
  list(year = 2023, id = "000040222859", table = "T88",
       label = "常勤換算医師数・人口10万対(年次・都道府県)")
)

# =============================================================================
# 6. 二次医療圏別 病院数 (N1/E1) - 静態調査年
# =============================================================================
sma_hospital_files <- list(
  list(year = 2014, id = "000031336380", table = "E1"),
  list(year = 2017, id = "000031780674", table = "E1"),
  list(year = 2020, id = "000032191990", table = "N1"),
  list(year = 2023, id = "000040222901", table = "N1")
)

# =============================================================================
# 7. 二次医療圏別 放射線治療 (E36/E35/N34) - 静態調査年
# =============================================================================
sma_radiation_files <- list(
  list(year = 2014, id = "000031336415", table = "E36"),
  list(year = 2017, id = "000031780708", table = "E35"),
  list(year = 2020, id = "000032192023", table = "N34"),
  list(year = 2023, id = "000040222934", table = "N34")
)

# =============================================================================
# ダウンロード関数
# =============================================================================
download_estat <- function(file_list, category_name, subdir = NULL) {
  cat(sprintf("\n--- %s ---\n", category_name))
  dest_dir <- if (!is.null(subdir)) file.path(data_dir, subdir) else data_dir
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)

  for (f in file_list) {
    fname <- sprintf("facility_%s_%s_%d.csv",
                     gsub("[^a-zA-Z0-9]", "_", tolower(category_name)),
                     f$table, f$year)
    dest <- file.path(dest_dir, fname)

    if (file.exists(dest)) {
      cat(sprintf("  [%d] %s => skip\n", f$year, fname))
      next
    }

    cat(sprintf("  [%d] %s => downloading...", f$year, fname))
    tryCatch({
      download.file(estat_url(f$id), dest, mode = "wb", quiet = TRUE)
      cat(sprintf(" OK (%s bytes)\n", format(file.size(dest), big.mark = ",")))
    }, error = function(e) {
      cat(sprintf(" ERROR: %s\n", e$message))
    })
    Sys.sleep(1)
  }
}

# =============================================================================
# ダウンロード実行
# =============================================================================
cat("=== 医療施設調査 ダウンロード ===\n")

download_estat(hospital_count_files, "hospitals_pref")
download_estat(staff_files, "staff_pref")
download_estat(radiation_files, "radiation_pref")
download_estat(staff_per_bed_files, "staff_per_bed_pref")
download_estat(fte_physician_files, "fte_physician_pref")
download_estat(sma_hospital_files, "hospitals_sma", subdir = "sma")
download_estat(sma_radiation_files, "radiation_sma", subdir = "sma")

cat("\n=== 医療施設調査 ダウンロード完了 ===\n")
