################################################################################
# 01_download_ndb_data.R
# NDB Open Data (第1回〜第10回) 都道府県別・二次医療圏別・性年齢別 算定回数 ダウンロード
# 対象: M放射線治療, K手術, D検査
#
# データ元: 厚生労働省 NDBオープンデータ
# https://www.mhlw.go.jp/stf/seisakunitsuite/bunya/0000177182.html
#
# 二次医療圏別データは第6回(FY2019)以降のみ利用可能(D/K/M)
# 性年齢別データは全回(第1回〜第10回)で利用可能 — SCR計算用
################################################################################

data_dir <- file.path(getwd(), "rawdata_dl")

# =============================================================================
# 都道府県別 セクション定義 (第1回〜第10回, FY2014-2023)
# =============================================================================
pref_sections <- list(
  list(
    section = "M_radiation", label = "M放射線治療",
    dir = file.path(data_dir, "ndb_pref", "M_radiation_pref"),
    prefix = "M_radiation_pref",
    urls = c(
      "https://www.mhlw.go.jp/file/06-Seisakujouhou-12400000-Hokenkyoku/0000140365.xlsx",
      "https://www.mhlw.go.jp/file/06-Seisakujouhou-12400000-Hokenkyoku/0000177272.xlsx",
      "https://www.mhlw.go.jp/content/12400000/000347734.xlsx",
      "https://www.mhlw.go.jp/content/12400000/000711871.xlsx",
      "https://www.mhlw.go.jp/content/12400000/000539735.xlsx",
      "https://www.mhlw.go.jp/content/12400000/000821502.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001262199.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001122166.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001258359.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001493244.xlsx"
    )
  ),
  list(
    section = "K_surgery", label = "K手術",
    dir = file.path(data_dir, "ndb_pref", "K_surgery_pref"),
    prefix = "K_surgery_pref",
    urls = c(
      "https://www.mhlw.go.jp/file/06-Seisakujouhou-12400000-Hokenkyoku/0000140361.xlsx",
      "https://www.mhlw.go.jp/file/06-Seisakujouhou-12400000-Hokenkyoku/0000177267.xlsx",
      "https://www.mhlw.go.jp/content/12400000/000347728.xlsx",
      "https://www.mhlw.go.jp/content/12400000/000711860.xlsx",
      "https://www.mhlw.go.jp/content/12400000/000539727.xlsx",
      "https://www.mhlw.go.jp/content/12400000/000821489.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001262186.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001122126.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001258347.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001493188.xlsx"
    )
  ),
  list(
    section = "D_exam", label = "D検査",
    dir = file.path(data_dir, "ndb_pref", "D_exam_pref"),
    prefix = "D_exam_pref",
    urls = c(
      "https://www.mhlw.go.jp/file/06-Seisakujouhou-12400000-Hokenkyoku/0000171424.xlsx",
      "https://www.mhlw.go.jp/file/06-Seisakujouhou-12400000-Hokenkyoku/0000177244.xlsx",
      "https://www.mhlw.go.jp/content/12400000/000347713.xlsx",
      "https://www.mhlw.go.jp/content/12400000/000711837.xlsx",
      "https://www.mhlw.go.jp/content/12400000/000539671.xlsx",
      "https://www.mhlw.go.jp/content/12400000/000821450.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001262145.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001122097.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001258315.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001493093.xlsx"
    )
  )
)

# =============================================================================
# 二次医療圏別 セクション定義 (第6回〜第10回, FY2019-2023のみ)
# =============================================================================
sma_sections <- list(
  list(
    section = "M_radiation", label = "M放射線治療(二次医療圏)",
    dir = file.path(data_dir, "ndb_sma", "M_radiation_sma"),
    prefix = "M_radiation_sma",
    # editions 6-10 (FY2019-2023)
    editions = 6:10,
    fy_years = 2019:2023,
    urls = c(
      "https://www.mhlw.go.jp/content/12400000/000821503.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001262201.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001122168.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001258361.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001493246.xlsx"
    )
  ),
  list(
    section = "K_surgery", label = "K手術(二次医療圏)",
    dir = file.path(data_dir, "ndb_sma", "K_surgery_sma"),
    prefix = "K_surgery_sma",
    editions = 6:10,
    fy_years = 2019:2023,
    urls = c(
      "https://www.mhlw.go.jp/content/12400000/000821490.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001262188.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001122128.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001258349.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001493192.xlsx"
    )
  ),
  list(
    section = "D_exam", label = "D検査(二次医療圏)",
    dir = file.path(data_dir, "ndb_sma", "D_exam_sma"),
    prefix = "D_exam_sma",
    editions = 6:10,
    fy_years = 2019:2023,
    urls = c(
      "https://www.mhlw.go.jp/content/12400000/000821451.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001262151.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001122099.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001258317.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001493098.xlsx"
    )
  )
)

# =============================================================================
# ダウンロード実行: 都道府県別
# =============================================================================
cat("=== NDB Open Data 都道府県別算定回数 ダウンロード ===\n\n")

for (sec in pref_sections) {
  dir.create(sec$dir, recursive = TRUE, showWarnings = FALSE)
  cat(sprintf("--- %s ---\n", sec$label))

  for (i in 1:10) {
    fname <- sprintf("ndb%02d_%s_%d.xlsx", i, sec$prefix, 2013 + i)
    dest  <- file.path(sec$dir, fname)

    if (file.exists(dest)) {
      cat(sprintf("[%2d/10] %s => skip\n", i, fname))
      next
    }

    cat(sprintf("[%2d/10] %s => downloading...", i, fname))
    tryCatch({
      download.file(sec$urls[i], dest, mode = "wb", quiet = TRUE)
      cat(sprintf(" OK (%s bytes)\n", format(file.size(dest), big.mark = ",")))
    }, error = function(e) {
      cat(sprintf(" ERROR: %s\n", e$message))
    })
    Sys.sleep(1)
  }
  cat("\n")
}

# =============================================================================
# ダウンロード実行: 二次医療圏別
# =============================================================================
cat("=== NDB Open Data 二次医療圏別算定回数 ダウンロード ===\n\n")

for (sec in sma_sections) {
  dir.create(sec$dir, recursive = TRUE, showWarnings = FALSE)
  cat(sprintf("--- %s ---\n", sec$label))

  for (j in seq_along(sec$editions)) {
    ed <- sec$editions[j]
    fy <- sec$fy_years[j]
    fname <- sprintf("ndb%02d_%s_%d.xlsx", ed, sec$prefix, fy)
    dest  <- file.path(sec$dir, fname)

    if (file.exists(dest)) {
      cat(sprintf("[ed%02d] %s => skip\n", ed, fname))
      next
    }

    cat(sprintf("[ed%02d] %s => downloading...", ed, fname))
    tryCatch({
      download.file(sec$urls[j], dest, mode = "wb", quiet = TRUE)
      cat(sprintf(" OK (%s bytes)\n", format(file.size(dest), big.mark = ",")))
    }, error = function(e) {
      cat(sprintf(" ERROR: %s\n", e$message))
    })
    Sys.sleep(1)
  }
  cat("\n")
}

# =============================================================================
# 性年齢別 セクション定義 (第1回〜第10回, FY2014-2023) — SCR計算用
# =============================================================================
sexage_sections <- list(
  list(
    section = "M_radiation", label = "M放射線治療(性年齢別)",
    dir = file.path(data_dir, "ndb_pref", "M_radiation_sexage"),
    prefix = "M_radiation_sexage",
    urls = c(
      "https://www.mhlw.go.jp/file/06-Seisakujouhou-12400000-Hokenkyoku/0000140364.xlsx",
      "https://www.mhlw.go.jp/file/06-Seisakujouhou-12400000-Hokenkyoku/0000177271.xlsx",
      "https://www.mhlw.go.jp/content/12400000/000347733.xlsx",
      "https://www.mhlw.go.jp/content/12400000/000711870.xlsx",
      "https://www.mhlw.go.jp/content/12400000/000539734.xlsx",
      "https://www.mhlw.go.jp/content/12400000/000821501.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001262198.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001122165.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001258358.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001493243.xlsx"
    )
  ),
  list(
    section = "K_surgery", label = "K手術(性年齢別)",
    dir = file.path(data_dir, "ndb_pref", "K_surgery_sexage"),
    prefix = "K_surgery_sexage",
    urls = c(
      "https://www.mhlw.go.jp/file/06-Seisakujouhou-12400000-Hokenkyoku/0000140360.xlsx",
      "https://www.mhlw.go.jp/file/06-Seisakujouhou-12400000-Hokenkyoku/0000177266.xlsx",
      "https://www.mhlw.go.jp/content/12400000/000347727.xlsx",
      "https://www.mhlw.go.jp/content/12400000/000711858.xlsx",
      "https://www.mhlw.go.jp/content/12400000/000539726.xlsx",
      "https://www.mhlw.go.jp/content/12400000/000821487.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001262185.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001122125.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001258346.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001493186.xlsx"
    )
  ),
  list(
    section = "D_exam", label = "D検査(性年齢別)",
    dir = file.path(data_dir, "ndb_pref", "D_exam_sexage"),
    prefix = "D_exam_sexage",
    urls = c(
      "https://www.mhlw.go.jp/file/06-Seisakujouhou-12400000-Hokenkyoku/0000140356.xlsx",
      "https://www.mhlw.go.jp/file/06-Seisakujouhou-12400000-Hokenkyoku/0000177242.xlsx",
      "https://www.mhlw.go.jp/content/12400000/000347712.xlsx",
      "https://www.mhlw.go.jp/content/12400000/000711834.xlsx",
      "https://www.mhlw.go.jp/content/12400000/000539670.xlsx",
      "https://www.mhlw.go.jp/content/12400000/000821449.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001262144.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001122096.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001258296.xlsx",
      "https://www.mhlw.go.jp/content/12400000/001493092.xlsx"
    )
  )
)

# =============================================================================
# ダウンロード実行: 性年齢別 (SCR計算用)
# =============================================================================
cat("=== NDB Open Data 性年齢別算定回数 ダウンロード ===\n\n")

for (sec in sexage_sections) {
  dir.create(sec$dir, recursive = TRUE, showWarnings = FALSE)
  cat(sprintf("--- %s ---\n", sec$label))

  for (i in 1:10) {
    fname <- sprintf("ndb%02d_%s_%d.xlsx", i, sec$prefix, 2013 + i)
    dest  <- file.path(sec$dir, fname)

    if (file.exists(dest)) {
      cat(sprintf("[%2d/10] %s => skip\n", i, fname))
      next
    }

    cat(sprintf("[%2d/10] %s => downloading...", i, fname))
    tryCatch({
      download.file(sec$urls[i], dest, mode = "wb", quiet = TRUE)
      cat(sprintf(" OK (%s bytes)\n", format(file.size(dest), big.mark = ",")))
    }, error = function(e) {
      cat(sprintf(" ERROR: %s\n", e$message))
    })
    Sys.sleep(1)
  }
  cat("\n")
}

# =============================================================================
# 第11回(FY2024)以降: 医科診療行為(算定回数) ZIP一括配布への対応
#   第11回からファイル配布形式がZIP一括化された(個別xlsx直リンク廃止)。
#   ZIPをDLし、Pythonヘルパー(extract_ndb11_zip.py)で3指標×3軸=9ファイルを
#   従来命名(ndb11_<section>_2024.xlsx)で配置する。
#   ZIP内ファイル名がShift-JISのため、UTF-8 native R(>=4.2)では正しく解凍できず、
#   cp932を確実に扱えるPythonに抽出を委譲する。
# =============================================================================
cat("=== 第11回(FY2024) ZIP一括ダウンロード・抽出 ===\n\n")

# 公費レセプトを「含まない」データ(第1〜10回の個別xlsxと同等。プロジェクト方針)
ndb11_zip_url <- "https://www.mhlw.go.jp/content/12400000/001712210.zip"

ndb11_targets <- c(
  file.path(data_dir, "ndb_pref/M_radiation_pref/ndb11_M_radiation_pref_2024.xlsx"),
  file.path(data_dir, "ndb_pref/M_radiation_sexage/ndb11_M_radiation_sexage_2024.xlsx"),
  file.path(data_dir, "ndb_sma/M_radiation_sma/ndb11_M_radiation_sma_2024.xlsx"),
  file.path(data_dir, "ndb_pref/K_surgery_pref/ndb11_K_surgery_pref_2024.xlsx"),
  file.path(data_dir, "ndb_pref/K_surgery_sexage/ndb11_K_surgery_sexage_2024.xlsx"),
  file.path(data_dir, "ndb_sma/K_surgery_sma/ndb11_K_surgery_sma_2024.xlsx"),
  file.path(data_dir, "ndb_pref/D_exam_pref/ndb11_D_exam_pref_2024.xlsx"),
  file.path(data_dir, "ndb_pref/D_exam_sexage/ndb11_D_exam_sexage_2024.xlsx"),
  file.path(data_dir, "ndb_sma/D_exam_sma/ndb11_D_exam_sma_2024.xlsx")
)

if (all(file.exists(ndb11_targets))) {
  cat("第11回 9ファイルは抽出済み => skip\n\n")
} else {
  zip_dir <- file.path(data_dir, "_ndb_zip")
  dir.create(zip_dir, recursive = TRUE, showWarnings = FALSE)
  zip_path <- file.path(zip_dir, "ndb11_iryo_santei_kohi_nashi_2024.zip")

  if (!file.exists(zip_path) || file.size(zip_path) < 1e6) {
    cat(sprintf("ZIP ダウンロード中... (%s)\n", basename(zip_path)))
    tryCatch({
      download.file(ndb11_zip_url, zip_path, mode = "wb", quiet = TRUE)
      cat(sprintf("  OK (%s bytes)\n", format(file.size(zip_path), big.mark = ",")))
    }, error = function(e) cat(sprintf("  ERROR: %s\n", e$message)))
  } else {
    cat(sprintf("ZIP は取得済み => skip (%s)\n", basename(zip_path)))
  }

  # Pythonヘルパーで9ファイルを抽出(Shift-JIS名対応)
  helper <- file.path(getwd(), "scripts", "extract_ndb11_zip.py")
  py <- Sys.which("python")
  if (py == "") py <- Sys.which("python3")
  if (py == "") {
    cat("WARNING: python が見つかりません。第11回ZIPの抽出をスキップしました。\n")
    cat("  手動で実行してください:\n")
    cat(sprintf("  python \"%s\" \"%s\" \"%s\" 11 2024\n", helper, zip_path, data_dir))
  } else if (file.exists(zip_path)) {
    cat("Python抽出ヘルパー実行中...\n")
    status <- system2(py, c(shQuote(helper), shQuote(zip_path), shQuote(data_dir), "11", "2024"))
    if (status != 0) cat("WARNING: 抽出ヘルパーがエラーを返しました。出力を確認してください。\n")
  }
  cat("\n")
}

cat("=== NDB ダウンロード完了 ===\n")
