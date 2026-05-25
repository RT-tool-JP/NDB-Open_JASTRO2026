################################################################################
# 01_download_ndb_data.R
# NDB Open Data (第1回〜第10回) 都道府県別算定回数 ダウンロードスクリプト
# 対象: M放射線治療, K手術, D検査
#
# データ元: 厚生労働省 NDBオープンデータ
# https://www.mhlw.go.jp/stf/seisakunitsuite/bunya/0000177182.html
#
# 注意: ファイル形式はCSVではなくXLSX (Excel)
################################################################################

# =============================================================================
# セクション定義
# =============================================================================
fy_labels <- c("H26(2014)", "H27(2015)", "H28(2016)", "H29(2017)", "H30(2018)",
               "R01(2019)", "R02(2020)", "R03(2021)", "R04(2022)", "R05(2023)")

sections <- list(
  list(
    section = "M_radiation", label = "M放射線治療",
    dir = here::here("rawdata", "M_radiation_pref"),
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
    dir = here::here("rawdata", "K_surgery_pref"),
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
    dir = here::here("rawdata", "D_exam_pref"),
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
# ダウンロード実行
# =============================================================================
cat("=== NDB Open Data 都道府県別算定回数 ダウンロード ===\n\n")

for (sec in sections) {
  dir.create(sec$dir, recursive = TRUE, showWarnings = FALSE)
  cat(sprintf("--- %s ---\n", sec$label))

  for (i in 1:10) {
    fname <- sprintf("ndb%02d_%s_%d.xlsx", i, sec$prefix, 2013 + i)
    dest  <- file.path(sec$dir, fname)

    if (file.exists(dest)) {
      cat(sprintf("[%2d/10] %s => 既にダウンロード済み (skip)\n", i, fname))
      next
    }

    cat(sprintf("[%2d/10] %s => ダウンロード中...", i, fname))
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

cat("=== ダウンロード完了 ===\n")
