################################################################################
# 05_prepare_web_data.R
# Webアプリ用データの準備
#
# M放射線治療・K手術・D検査の都道府県別算定回数データを読み込み、
# JSON形式で出力する。
# K843~K843-4 (手術), D413, D009 (検査) を追加対象とする。
################################################################################

library(readxl)
library(dplyr)
library(tidyr)
library(stringr)
library(jsonlite)

# =============================================================================
# 設定
# =============================================================================

data_dir   <- here::here("rawdata")
output_dir <- here::here("output")
web_data_dir <- here::here("data")
dir.create(web_data_dir, recursive = TRUE, showWarnings = FALSE)

pref_names <- c(
  "北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県",
  "茨城県", "栃木県", "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県",
  "新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県",
  "岐阜県", "静岡県", "愛知県", "三重県", "滋賀県", "京都府", "大阪府",
  "兵庫県", "奈良県", "和歌山県", "鳥取県", "島根県", "岡山県",
  "広島県", "山口県", "徳島県", "香川県", "愛媛県", "高知県",
  "福岡県", "佐賀県", "長崎県", "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県"
)
pref_codes <- sprintf("%02d", 1:47)
pref_df <- data.frame(pref_code = pref_codes, pref_name = pref_names,
                       stringsAsFactors = FALSE)

ndb_meta <- data.frame(
  edition  = 1:10,
  fy_year  = 2014:2023,
  stringsAsFactors = FALSE
)

# セクション定義: どのディレクトリからどの分類コードを取得するか
section_defs <- list(
  list(
    label  = "M放射線治療",
    dir    = file.path(data_dir, "M_radiation_pref"),
    prefix = "M_radiation_pref",
    filter = NULL   # 全コード取得
  ),
  list(
    label  = "K手術",
    dir    = file.path(data_dir, "K_surgery_pref"),
    prefix = "K_surgery_pref",
    filter = "^K843"   # K843, K843-2, K843-3, K843-4
  ),
  list(
    label  = "D検査",
    dir    = file.path(data_dir, "D_exam_pref"),
    prefix = "D_exam_pref",
    filter = "^D(413|009)$"   # D413, D009
  )
)

# =============================================================================
# 1. NDB XLSXパース関数
# =============================================================================

parse_ndb_sheet <- function(file_path, sheet_name) {
  raw <- tryCatch(
    read_excel(file_path, sheet = sheet_name, col_names = FALSE, col_types = "text"),
    error = function(e) { return(NULL) }
  )
  if (is.null(raw) || nrow(raw) < 5) return(NULL)

  ncols <- ncol(raw)

  # ヘッダ行検出: M/D形式は列1に"分類"、K形式は列1に"款"(列2に"分類")
  header_row <- which(grepl("分類", raw[[1]], fixed = TRUE))
  has_section_col <- FALSE
  if (length(header_row) == 0 && ncols >= 2) {
    header_row <- which(grepl("款", raw[[1]], fixed = TRUE))
    if (length(header_row) > 0) has_section_col <- TRUE
  }
  if (length(header_row) == 0) return(NULL)
  header_row <- header_row[1]
  data_start <- header_row + 2
  if (data_start > nrow(raw)) return(NULL)

  dat <- raw[data_start:nrow(raw), ]

  if (has_section_col) {
    # K手術形式: 款 | 分類コード | 分類名称 | 診療行為コード | 診療行為 | 点数 | 総計 | 都道府県...
    meta_cols <- min(7, ncols)
    pref_start <- meta_cols + 1
    pref_end   <- min(ncols, meta_cols + 47)
    colnames(dat)[1:meta_cols] <- c("section", "class_code", "class_name",
                                     "procedure_code", "procedure_name",
                                     "points", "total")[1:meta_cols]
  } else {
    # M/D形式: 分類コード | 分類名称 | 診療行為コード | 診療行為名称 | 点数 | 総計 | 都道府県...
    meta_cols <- min(6, ncols)
    pref_start <- meta_cols + 1
    pref_end   <- min(ncols, meta_cols + 47)
    colnames(dat)[1:meta_cols] <- c("class_code", "class_name",
                                     "procedure_code", "procedure_name",
                                     "points", "total")[1:meta_cols]
  }

  if (pref_end >= pref_start) {
    colnames(dat)[pref_start:pref_end] <- sprintf("pref_%02d", 1:(pref_end - pref_start + 1))
  }

  dat$class_code <- zoo::na.locf(
    ifelse(dat$class_code == "" | is.na(dat$class_code), NA, dat$class_code), na.rm = FALSE)
  dat$class_name <- zoo::na.locf(
    ifelse(dat$class_name == "" | is.na(dat$class_name), NA, dat$class_name), na.rm = FALSE)

  pref_cols <- colnames(dat)[grepl("^pref_", colnames(dat))]

  dat |>
    select(class_code, class_name, procedure_code, procedure_name,
           points, total, all_of(pref_cols)) |>
    pivot_longer(cols = all_of(pref_cols), names_to = "pref_col", values_to = "count_raw") |>
    mutate(pref_code = str_extract(pref_col, "\\d+"), sheet = sheet_name)
}

parse_ndb_file <- function(file_path, edition, fy_year) {
  sheets <- excel_sheets(file_path)
  target_sheets <- sheets[sheets %in% c("外来", "入院")]
  result <- bind_rows(lapply(target_sheets, function(s) parse_ndb_sheet(file_path, s)))
  if (nrow(result) == 0) return(NULL)
  result$edition <- edition
  result$fy_year <- fy_year
  result
}

# =============================================================================
# 2. 全セクション・全年度データ読み込み
# =============================================================================

cat("=== NDB全データ読み込み ===\n")

all_data <- list()

for (sec in section_defs) {
  cat(sprintf("\n--- %s ---\n", sec$label))
  if (!dir.exists(sec$dir)) {
    cat(sprintf("  ディレクトリが存在しません: %s\n  01_download_ndb_data.R を実行してください。\n", sec$dir))
    next
  }

  for (i in seq_len(nrow(ndb_meta))) {
    fname <- sprintf("ndb%02d_%s_%d.xlsx", ndb_meta$edition[i], sec$prefix, ndb_meta$fy_year[i])
    fpath <- file.path(sec$dir, fname)
    if (!file.exists(fpath)) { cat(sprintf("  SKIP: %s\n", fname)); next }

    cat(sprintf("  [%2d] %s ...", i, fname))
    dat <- tryCatch(parse_ndb_file(fpath, ndb_meta$edition[i], ndb_meta$fy_year[i]),
                    error = function(e) { cat(sprintf(" ERROR: %s", e$message)); NULL })
    if (!is.null(dat) && nrow(dat) > 0) {
      # 分類コードフィルタ（指定がある場合のみ）
      if (!is.null(sec$filter)) {
        dat <- dat |> filter(grepl(sec$filter, class_code))
      }
      if (nrow(dat) > 0) {
        all_data[[length(all_data) + 1]] <- dat
        cat(sprintf(" %d rows\n", nrow(dat)))
      } else {
        cat(" (no matching codes)\n")
      }
    } else {
      cat(" (skip)\n")
    }
  }
}

ndb_all <- bind_rows(all_data) |>
  mutate(
    count = case_when(
      count_raw %in% c("-", "\u2010", "\uff0d", "\u2015") ~ NA_real_,
      count_raw == "" | is.na(count_raw) ~ NA_real_,
      TRUE ~ suppressWarnings(as.numeric(count_raw))
    )
  ) |>
  left_join(pref_df, by = "pref_code")

cat(sprintf("\n全データ: %d rows\n", nrow(ndb_all)))

# =============================================================================
# 3. 階層構造の構築（分類コード → 診療行為コード）
# =============================================================================

cat("\n=== 階層構造の構築 ===\n")

proc_meta <- ndb_all |>
  mutate(points_num = suppressWarnings(as.numeric(points))) |>
  filter(!is.na(procedure_code), procedure_code != "") |>
  group_by(class_code, procedure_code) |>
  summarise(
    class_name = last(class_name[order(fy_year)]),
    procedure_name = last(procedure_name[order(fy_year)]),
    points = max(points_num, na.rm = TRUE),
    max_year = max(fy_year),
    .groups = "drop"
  ) |>
  mutate(points = ifelse(is.infinite(points), NA_real_, points)) |>
  group_by(procedure_code) |>
  slice_max(max_year, n = 1, with_ties = FALSE) |>
  ungroup() |>
  select(-max_year) |>
  arrange(class_code, procedure_code)

cat(sprintf("診療行為数: %d\n", nrow(proc_meta)))

code_list <- proc_meta |>
  distinct(class_code, class_name) |>
  arrange(class_code)
cat("\n分類コード一覧:\n")
print(code_list)

# =============================================================================
# 4. 診療行為 × 都道府県 × 年度 の集計（外来+入院合算、NA保持）
# =============================================================================

cat("\n=== 診療行為レベル集計中 ===\n")

agg <- ndb_all |>
  filter(!is.na(procedure_code), procedure_code != "") |>
  group_by(class_code, procedure_code, pref_code, pref_name, fy_year) |>
  summarise(
    total_count = if (all(is.na(count))) NA_real_ else sum(count, na.rm = TRUE),
    .groups = "drop"
  )

cat(sprintf("集計レコード数: %d\n", nrow(agg)))
cat(sprintf("  うちNA: %d\n", sum(is.na(agg$total_count))))

# =============================================================================
# 5. 人口データ読み込み
# =============================================================================

cat("\n=== 人口データ読み込み ===\n")

pop_csv <- file.path(data_dir, "population_by_pref_year.csv")
if (!file.exists(pop_csv)) {
  stop("population_by_pref_year.csv が見つかりません。03_per_capita_analysis.R を先に実行してください。")
}

pop <- read.csv(pop_csv, stringsAsFactors = FALSE) |>
  mutate(pref_code = sprintf("%02d", as.integer(pref_code)))

cat(sprintf("人口データ: %d records\n", nrow(pop)))

# =============================================================================
# 6. JSON出力
# =============================================================================

cat("\n=== JSON出力 ===\n")

# --- 6a. 階層構造（分類コード → 診療行為リスト） ---
codes_hierarchy <- list()
for (i in seq_len(nrow(code_list))) {
  cc <- code_list$class_code[i]
  cn <- code_list$class_name[i]
  procs <- proc_meta |> filter(class_code == cc)
  proc_list <- lapply(seq_len(nrow(procs)), function(j) {
    list(
      id   = procs$procedure_code[j],
      name = procs$procedure_name[j],
      points = if (is.na(procs$points[j])) NULL else procs$points[j]
    )
  })
  codes_hierarchy[[length(codes_hierarchy) + 1]] <- list(
    code = cc, name = cn, procedures = proc_list
  )
}

# --- 6b. 人口データ ---
pop_nested <- list()
for (i in seq_len(nrow(pop))) {
  pc <- pop$pref_code[i]
  yr <- as.character(pop$year[i])
  if (is.null(pop_nested[[pc]])) pop_nested[[pc]] <- list()
  pop_nested[[pc]][[yr]] <- pop$population[i]
}

# --- 6c. 算定回数データ（診療行為コードレベル、NA=null） ---
counts_nested <- list()
for (i in seq_len(nrow(agg))) {
  proc <- agg$procedure_code[i]
  pc   <- agg$pref_code[i]
  yr   <- as.character(agg$fy_year[i])
  val  <- agg$total_count[i]
  if (is.null(counts_nested[[proc]])) counts_nested[[proc]] <- list()
  if (is.null(counts_nested[[proc]][[pc]])) counts_nested[[proc]][[pc]] <- list()
  # NA → null in JSON (秘匿データ)
  if (is.na(val)) {
    counts_nested[[proc]][[pc]][[yr]] <- NA_real_
  } else {
    counts_nested[[proc]][[pc]][[yr]] <- val
  }
}

# --- 6d. 都道府県コード→名前マッピング ---
pref_map <- setNames(as.list(pref_names), pref_codes)

# --- 組み立て ---
web_data <- list(
  codes = codes_hierarchy,
  years = 2014:2023,
  prefectures = pref_map,
  population = pop_nested,
  counts = counts_nested
)

json_path <- file.path(web_data_dir, "ndb_radiation.json")
write(toJSON(web_data, auto_unbox = TRUE, pretty = FALSE, null = "null", na = "null"), json_path)
cat(sprintf("JSON出力: %s (%s bytes)\n", json_path,
            format(file.size(json_path), big.mark = ",")))

# =============================================================================
# 7. GeoJSONコピー
# =============================================================================

geojson_src <- file.path(data_dir, "prefectures.geojson")
geojson_dst <- file.path(web_data_dir, "prefectures.geojson")

if (file.exists(geojson_src)) {
  file.copy(geojson_src, geojson_dst, overwrite = TRUE)
  cat(sprintf("GeoJSON: %s\n", geojson_dst))
} else {
  cat("WARNING: prefectures.geojson が見つかりません。04_choropleth_map.R を先に実行してください。\n")
}

cat("\n=== 完了 ===\n")
