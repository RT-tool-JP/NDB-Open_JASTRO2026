################################################################################
# 10_prepare_web_data.R
# 全データ統合 → JSON出力 (webapp用)
#
# NDB都道府県/二次医療圏 + 医療施設調査 + 医師統計 + 人口 → JSON
################################################################################

library(readxl)
library(dplyr)
library(tidyr)
library(stringr)
library(jsonlite)
library(zoo)

base_dir <- getwd()
data_dir <- file.path(base_dir, "rawdata_dl")
output_dir <- file.path(base_dir, "data")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# =============================================================================
# 共通設定
# =============================================================================
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

# CP932 CSV読み込みヘルパー
read_cp932 <- function(filepath) {
  raw <- readLines(filepath, encoding = "CP932", warn = FALSE)
  iconv(raw, from = "CP932", to = "UTF-8")
}

# =============================================================================
# 1. NDB都道府県データ パース
# =============================================================================
cat("=== 1. NDB都道府県データ ===\n")

ndb_meta <- data.frame(edition = 1:11, fy_year = 2014:2024, stringsAsFactors = FALSE)

section_defs <- list(
  list(label = "M放射線治療", dir = file.path(data_dir, "ndb_pref/M_radiation_pref"),
       prefix = "M_radiation_pref", filter = NULL),
  list(label = "K手術", dir = file.path(data_dir, "ndb_pref/K_surgery_pref"),
       prefix = "K_surgery_pref", filter = "^K843"),
  list(label = "D検査", dir = file.path(data_dir, "ndb_pref/D_exam_pref"),
       prefix = "D_exam_pref", filter = "^D(413|009)$")
)

parse_ndb_sheet <- function(file_path, sheet_name) {
  raw <- tryCatch(
    read_excel(file_path, sheet = sheet_name, col_names = FALSE, col_types = "text"),
    error = function(e) NULL)
  if (is.null(raw) || nrow(raw) < 5) return(NULL)
  ncols <- ncol(raw)

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
    meta_cols <- min(7, ncols)
    pref_start <- meta_cols + 1
    pref_end <- min(ncols, meta_cols + 47)
    colnames(dat)[1:meta_cols] <- c("section", "class_code", "class_name",
                                     "procedure_code", "procedure_name",
                                     "points", "total")[1:meta_cols]
  } else {
    meta_cols <- min(6, ncols)
    pref_start <- meta_cols + 1
    pref_end <- min(ncols, meta_cols + 47)
    colnames(dat)[1:meta_cols] <- c("class_code", "class_name",
                                     "procedure_code", "procedure_name",
                                     "points", "total")[1:meta_cols]
  }

  if (pref_end >= pref_start) {
    colnames(dat)[pref_start:pref_end] <- sprintf("pref_%02d", 1:(pref_end - pref_start + 1))
  }

  dat$class_code <- na.locf(ifelse(dat$class_code == "" | is.na(dat$class_code), NA, dat$class_code), na.rm = FALSE)
  dat$class_name <- na.locf(ifelse(dat$class_name == "" | is.na(dat$class_name), NA, dat$class_name), na.rm = FALSE)

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

all_data <- list()
for (sec in section_defs) {
  cat(sprintf("  %s: ", sec$label))
  if (!dir.exists(sec$dir)) { cat("DIR NOT FOUND\n"); next }
  sec_count <- 0
  for (i in seq_len(nrow(ndb_meta))) {
    fname <- sprintf("ndb%02d_%s_%d.xlsx", ndb_meta$edition[i], sec$prefix, ndb_meta$fy_year[i])
    fpath <- file.path(sec$dir, fname)
    if (!file.exists(fpath)) next
    dat <- tryCatch(parse_ndb_file(fpath, ndb_meta$edition[i], ndb_meta$fy_year[i]),
                    error = function(e) NULL)
    if (!is.null(dat) && nrow(dat) > 0) {
      if (!is.null(sec$filter)) dat <- dat |> filter(grepl(sec$filter, class_code))
      if (nrow(dat) > 0) { all_data[[length(all_data) + 1]] <- dat; sec_count <- sec_count + nrow(dat) }
    }
  }
  cat(sprintf("%d rows\n", sec_count))
}

ndb_all <- bind_rows(all_data) |>
  mutate(count = case_when(
    count_raw %in% c("-", "\u2010", "\uff0d", "\u2015") ~ NA_real_,
    count_raw == "" | is.na(count_raw) ~ NA_real_,
    TRUE ~ suppressWarnings(as.numeric(count_raw))
  )) |>
  left_join(pref_df, by = "pref_code")

cat(sprintf("  NDB都道府県 合計: %d rows\n", nrow(ndb_all)))

# 階層構造
proc_meta <- ndb_all |>
  mutate(points_num = suppressWarnings(as.numeric(points))) |>
  filter(!is.na(procedure_code), procedure_code != "") |>
  group_by(class_code, procedure_code) |>
  summarise(
    class_name = last(class_name[order(fy_year)]),
    procedure_name = last(procedure_name[order(fy_year)]),
    points = max(points_num, na.rm = TRUE),
    max_year = max(fy_year), .groups = "drop") |>
  mutate(points = ifelse(is.infinite(points), NA_real_, points)) |>
  group_by(procedure_code) |>
  slice_max(max_year, n = 1, with_ties = FALSE) |>
  ungroup() |> select(-max_year) |>
  arrange(class_code, procedure_code)

cat(sprintf("  診療行為数: %d\n", nrow(proc_meta)))

# 集計（外来+入院合算）
ndb_pref_agg <- ndb_all |>
  filter(!is.na(procedure_code), procedure_code != "") |>
  group_by(class_code, procedure_code, pref_code, fy_year) |>
  summarise(total_count = if (all(is.na(count))) NA_real_ else sum(count, na.rm = TRUE),
            .groups = "drop")

# 国の総計(秘匿前の真の全国値)= 総計列(外来+入院)。欠損レコード率の算出に使用。
# 総計は各診療行為コード×シートで全都道府県行に同値が入るため first() で取得し、外来+入院を合算。
ndb_national_agg <- ndb_all |>
  filter(!is.na(procedure_code), procedure_code != "") |>
  mutate(total_num = case_when(
    total %in% c("-", "‐", "－", "―") ~ NA_real_,
    total == "" | is.na(total) ~ NA_real_,
    TRUE ~ suppressWarnings(as.numeric(total))
  )) |>
  group_by(procedure_code, fy_year, sheet) |>
  summarise(sheet_total = first(total_num), .groups = "drop") |>
  group_by(procedure_code, fy_year) |>
  summarise(national_total = if (all(is.na(sheet_total))) NA_real_ else sum(sheet_total, na.rm = TRUE),
            .groups = "drop")

# =============================================================================
# 2. NDB二次医療圏データ パース
# =============================================================================
cat("\n=== 2. NDB二次医療圏データ ===\n")

parse_ndb_sma_sheet <- function(file_path, sheet_name) {
  raw <- tryCatch(
    read_excel(file_path, sheet = sheet_name, col_names = FALSE, col_types = "text"),
    error = function(e) NULL)
  if (is.null(raw) || nrow(raw) < 5) return(NULL)
  ncols <- ncol(raw)

  header_row <- which(grepl("分類", raw[[1]], fixed = TRUE))
  has_section_col <- FALSE
  if (length(header_row) == 0 && ncols >= 2) {
    header_row <- which(grepl("款", raw[[1]], fixed = TRUE))
    if (length(header_row) > 0) has_section_col <- TRUE
  }
  if (length(header_row) == 0) return(NULL)
  header_row <- header_row[1]

  # 二次医療圏コード行 (header_row + 1)
  sma_code_row <- header_row + 1
  sma_codes <- as.character(raw[sma_code_row, ])

  data_start <- header_row + 2
  if (data_start > nrow(raw)) return(NULL)
  dat <- raw[data_start:nrow(raw), ]

  if (has_section_col) {
    meta_cols <- 7
    colnames(dat)[1:meta_cols] <- c("section", "class_code", "class_name",
                                     "procedure_code", "procedure_name",
                                     "points", "total")
  } else {
    meta_cols <- 6
    colnames(dat)[1:meta_cols] <- c("class_code", "class_name",
                                     "procedure_code", "procedure_name",
                                     "points", "total")
  }

  # 二次医療圏列: meta_cols+1 から最後まで
  sma_start <- meta_cols + 1
  n_sma <- ncols - meta_cols
  if (n_sma <= 0) return(NULL)

  # 二次医療圏コードを取得
  region_codes <- sma_codes[sma_start:ncols]
  # 4桁コードのみ使用（空やNAは除外）
  valid_mask <- !is.na(region_codes) & grepl("^\\d{4}$", region_codes)
  valid_cols <- which(valid_mask) + meta_cols

  if (length(valid_cols) == 0) return(NULL)
  valid_codes <- region_codes[valid_mask]

  # 列名設定
  for (j in seq_along(valid_cols)) {
    colnames(dat)[valid_cols[j]] <- paste0("sma_", valid_codes[j])
  }

  dat$class_code <- na.locf(ifelse(dat$class_code == "" | is.na(dat$class_code), NA, dat$class_code), na.rm = FALSE)
  dat$class_name <- na.locf(ifelse(dat$class_name == "" | is.na(dat$class_name), NA, dat$class_name), na.rm = FALSE)

  sma_cols <- colnames(dat)[grepl("^sma_", colnames(dat))]

  dat |>
    select(class_code, class_name, procedure_code, procedure_name,
           points, total, all_of(sma_cols)) |>
    pivot_longer(cols = all_of(sma_cols), names_to = "sma_col", values_to = "count_raw") |>
    mutate(sma_code = str_extract(sma_col, "\\d+"), sheet = sheet_name)
}

sma_section_defs <- list(
  list(label = "M放射線治療", dir = file.path(data_dir, "ndb_sma/M_radiation_sma"),
       prefix = "M_radiation_sma", filter = NULL),
  list(label = "K手術", dir = file.path(data_dir, "ndb_sma/K_surgery_sma"),
       prefix = "K_surgery_sma", filter = "^K843"),
  list(label = "D検査", dir = file.path(data_dir, "ndb_sma/D_exam_sma"),
       prefix = "D_exam_sma", filter = "^D(413|009)$")
)

sma_editions <- data.frame(edition = 6:11, fy_year = 2019:2024, stringsAsFactors = FALSE)

sma_data <- list()
for (sec in sma_section_defs) {
  cat(sprintf("  %s: ", sec$label))
  if (!dir.exists(sec$dir)) { cat("DIR NOT FOUND\n"); next }
  sec_count <- 0
  for (i in seq_len(nrow(sma_editions))) {
    fname <- sprintf("ndb%02d_%s_%d.xlsx", sma_editions$edition[i], sec$prefix, sma_editions$fy_year[i])
    fpath <- file.path(sec$dir, fname)
    if (!file.exists(fpath)) next
    dat <- tryCatch({
      sheets <- excel_sheets(fpath)
      target_sheets <- sheets[sheets %in% c("外来", "入院")]
      bind_rows(lapply(target_sheets, function(s) parse_ndb_sma_sheet(fpath, s)))
    }, error = function(e) { cat(sprintf("ERR(%s) ", e$message)); NULL })
    if (!is.null(dat) && nrow(dat) > 0) {
      dat$edition <- sma_editions$edition[i]
      dat$fy_year <- sma_editions$fy_year[i]
      if (!is.null(sec$filter)) dat <- dat |> filter(grepl(sec$filter, class_code))
      if (nrow(dat) > 0) { sma_data[[length(sma_data) + 1]] <- dat; sec_count <- sec_count + nrow(dat) }
    }
  }
  cat(sprintf("%d rows\n", sec_count))
}

ndb_sma_all <- if (length(sma_data) > 0) {
  bind_rows(sma_data) |>
    mutate(count = case_when(
      count_raw %in% c("-", "\u2010", "\uff0d", "\u2015") ~ NA_real_,
      count_raw == "" | is.na(count_raw) ~ NA_real_,
      TRUE ~ suppressWarnings(as.numeric(count_raw))
    ))
} else {
  data.frame()
}

cat(sprintf("  NDB二次医療圏 合計: %d rows\n", nrow(ndb_sma_all)))

# 集計
ndb_sma_agg <- if (nrow(ndb_sma_all) > 0) {
  ndb_sma_all |>
    filter(!is.na(procedure_code), procedure_code != "") |>
    group_by(class_code, procedure_code, sma_code, fy_year) |>
    summarise(total_count = if (all(is.na(count))) NA_real_ else sum(count, na.rm = TRUE),
              .groups = "drop")
} else {
  data.frame()
}

# =============================================================================
# 2b. NDB性年齢別データ パース (SCR計算用)
# =============================================================================
cat("\n=== 2b. NDB性年齢別データ (SCR用) ===\n")

sexage_section_defs <- list(
  list(label = "M放射線治療", dir = file.path(data_dir, "ndb_pref/M_radiation_sexage"),
       prefix = "M_radiation_sexage", filter = NULL),
  list(label = "K手術", dir = file.path(data_dir, "ndb_pref/K_surgery_sexage"),
       prefix = "K_surgery_sexage", filter = "^K843"),
  list(label = "D検査", dir = file.path(data_dir, "ndb_pref/D_exam_sexage"),
       prefix = "D_exam_sexage", filter = "^D(413|009)$")
)

# Normalize age group name: "0～4歳" → "0-4", "90歳以上" → "90+"
normalize_age <- function(x) {
  x <- trimws(x)
  x <- gsub("[　 ]+", "", x)
  x <- gsub("歳以上$", "+", x)
  x <- gsub("歳$", "", x)
  x <- gsub("～", "-", x)
  x
}

parse_ndb_sexage_sheet <- function(file_path, sheet_name) {
  raw <- tryCatch(
    read_excel(file_path, sheet = sheet_name, col_names = FALSE, col_types = "text"),
    error = function(e) NULL)
  if (is.null(raw) || nrow(raw) < 5) return(NULL)
  ncols <- ncol(raw)

  header_row <- which(grepl("分類", raw[[1]], fixed = TRUE))
  has_section_col <- FALSE
  if (length(header_row) == 0 && ncols >= 2) {
    header_row <- which(grepl("款", raw[[1]], fixed = TRUE))
    if (length(header_row) > 0) has_section_col <- TRUE
  }
  if (length(header_row) == 0) return(NULL)
  header_row <- header_row[1]

  meta_cols <- if (has_section_col) 7 else 6

  # Sex labels are on the header row itself (same row as "分類")
  # Age labels are on the next row (header_row + 1)
  sex_labels <- as.character(raw[header_row, ])
  age_row <- header_row + 1
  if (age_row > nrow(raw)) return(NULL)
  age_labels_raw <- as.character(raw[age_row, ])

  male_start <- NA; female_start <- NA
  for (j in (meta_cols + 1):ncols) {
    lab <- trimws(sex_labels[j])
    if (!is.na(lab) && grepl("^男", lab) && is.na(male_start)) male_start <- j
    if (!is.na(lab) && grepl("^女", lab) && is.na(female_start)) female_start <- j
  }
  if (is.na(male_start)) return(NULL)

  male_end <- if (!is.na(female_start)) female_start - 1 else ncols
  female_end <- ncols

  sa_cols <- list()
  for (j in male_start:male_end) {
    age <- trimws(age_labels_raw[j])
    if (!is.na(age) && age != "" && !grepl("総|合計", age)) {
      sa_cols[[length(sa_cols) + 1]] <- list(col = j, sex = "M", age = normalize_age(age))
    }
  }
  if (!is.na(female_start)) {
    for (j in female_start:female_end) {
      age <- trimws(age_labels_raw[j])
      if (!is.na(age) && age != "" && !grepl("総|合計", age)) {
        sa_cols[[length(sa_cols) + 1]] <- list(col = j, sex = "F", age = normalize_age(age))
      }
    }
  }
  if (length(sa_cols) == 0) return(NULL)

  data_start <- header_row + 2
  if (data_start > nrow(raw)) return(NULL)
  dat <- raw[data_start:nrow(raw), ]

  if (has_section_col) {
    colnames(dat)[1:meta_cols] <- c("section", "class_code", "class_name",
                                     "procedure_code", "procedure_name",
                                     "points", "total")[1:meta_cols]
  } else {
    colnames(dat)[1:meta_cols] <- c("class_code", "class_name",
                                     "procedure_code", "procedure_name",
                                     "points", "total")[1:meta_cols]
  }

  dat$class_code <- na.locf(
    ifelse(dat$class_code == "" | is.na(dat$class_code), NA, dat$class_code),
    na.rm = FALSE)

  valid <- !is.na(dat$procedure_code) & dat$procedure_code != ""
  if (!any(valid)) return(NULL)
  dat <- dat[valid, ]

  results <- list()
  for (sa in sa_cols) {
    vals <- as.character(dat[[sa$col]])
    counts <- case_when(
      vals %in% c("-", "\u2010", "\uff0d", "\u2015") ~ NA_real_,
      vals == "" | is.na(vals) ~ NA_real_,
      TRUE ~ suppressWarnings(as.numeric(vals))
    )
    results[[length(results) + 1]] <- data.frame(
      class_code = dat$class_code, procedure_code = dat$procedure_code,
      sex = sa$sex, age_group = sa$age, count = counts,
      stringsAsFactors = FALSE)
  }

  bind_rows(results) |> mutate(sheet = sheet_name)
}

sexage_all_data <- list()
for (sec in sexage_section_defs) {
  cat(sprintf("  %s: ", sec$label))
  if (!dir.exists(sec$dir)) { cat("DIR NOT FOUND\n"); next }
  sec_count <- 0
  for (i in seq_len(nrow(ndb_meta))) {
    fname <- sprintf("ndb%02d_%s_%d.xlsx", ndb_meta$edition[i], sec$prefix, ndb_meta$fy_year[i])
    fpath <- file.path(sec$dir, fname)
    if (!file.exists(fpath)) next
    tryCatch({
      sheets <- excel_sheets(fpath)
      target_sheets <- sheets[sheets %in% c("外来", "入院")]
      dat <- bind_rows(lapply(target_sheets, function(s) parse_ndb_sexage_sheet(fpath, s)))
      if (nrow(dat) > 0) {
        dat$fy_year <- ndb_meta$fy_year[i]
        if (!is.null(sec$filter)) dat <- dat |> filter(grepl(sec$filter, class_code))
        if (nrow(dat) > 0) {
          sexage_all_data[[length(sexage_all_data) + 1]] <- dat
          sec_count <- sec_count + nrow(dat)
        }
      }
    }, error = function(e) cat(sprintf("ERR(%s) ", e$message)))
  }
  cat(sprintf("%d rows\n", sec_count))
}

# Aggregate: sum 外来+入院 per procedure × sex × age × year
ndb_sexage_agg <- if (length(sexage_all_data) > 0) {
  bind_rows(sexage_all_data) |>
    group_by(procedure_code, sex, age_group, fy_year) |>
    summarise(national_count = if (all(is.na(count))) NA_real_
              else sum(count, na.rm = TRUE), .groups = "drop")
} else {
  data.frame()
}

# Combine NDB 85-89 + 90+ into 85+ to align with population age groups
if (nrow(ndb_sexage_agg) > 0) {
  ndb_sexage_agg <- ndb_sexage_agg |>
    mutate(age_group = ifelse(age_group %in% c("85-89", "90+"), "85+", age_group)) |>
    group_by(procedure_code, sex, age_group, fy_year) |>
    summarise(national_count = if (all(is.na(national_count))) NA_real_
              else sum(national_count, na.rm = TRUE), .groups = "drop")
}

cat(sprintf("  NDB性年齢別 合計: %d rows (procs: %d, ages: %s)\n",
            nrow(ndb_sexage_agg), n_distinct(ndb_sexage_agg$procedure_code),
            paste(sort(unique(ndb_sexage_agg$age_group)), collapse = ", ")))

# =============================================================================
# 3. 病院数（都道府県）
# =============================================================================
cat("\n=== 3. 病院数（都道府県）===\n")

# 2023ファイルに2002-2023の全年度が含まれている
# 列マッピング: col6=2014, col7=2017, col8=2020, col9=2022, col10=2023
# 2014-2023は個別ファイルからも取得可能
# → 各年のファイルの最新値列を使用
hospital_pref <- list()

# 各年度ファイルから、そのファイル固有の年度データを取得
hosp_files <- list.files(file.path(data_dir, "facility"),
                          pattern = "hospitals_pref.*\\.(csv)$", full.names = TRUE)

for (hf in hosp_files) {
  year_match <- regmatches(hf, regexpr("\\d{4}\\.csv", hf))
  if (length(year_match) == 0) next
  yr <- as.integer(sub("\\.csv$", "", year_match))

  lines <- read_cp932(hf)
  # ヘッダ行を探す: "2002" や "('05)" を含む行
  header_idx <- grep("2002|\\('05\\)|施設|実数", lines)
  if (length(header_idx) == 0) next

  # "年度ラベル行" (L4相当) から年度→列番号のマッピングを構築
  # データ行は header_idx の後ろ (全国、都道府県...)
  # 簡略化: 最終年のデータ = "実数" 列 (最後から2番目の数値列)
  data_start <- max(header_idx) + 2  # 空行を挟む場合がある
  for (i in data_start:min(data_start + 5, length(lines))) {
    if (grepl("全", lines[i])) { data_start <- i + 1; break }
  }

  for (i in data_start:min(length(lines), data_start + 47)) {
    parts <- strsplit(lines[i], ",")[[1]]
    if (length(parts) < 3) next
    pref_name <- trimws(gsub("\u3000", "", parts[1]))
    # 最後の数値列の1つ前が実数（最後は人口10万対）
    nums <- suppressWarnings(as.numeric(parts[-1]))
    valid_nums <- which(!is.na(nums))
    if (length(valid_nums) >= 2) {
      hosp_count <- nums[valid_nums[length(valid_nums) - 1]]
      pref_idx <- i - data_start + 1
      if (pref_idx >= 1 && pref_idx <= 47) {
        pc <- sprintf("%02d", pref_idx)
        hospital_pref[[length(hospital_pref) + 1]] <- data.frame(
          pref_code = pc, year = yr, hospitals = as.integer(hosp_count),
          stringsAsFactors = FALSE)
      }
    }
  }
}

hospital_pref_df <- if (length(hospital_pref) > 0) bind_rows(hospital_pref) else data.frame()
cat(sprintf("  病院数: %d records (%d years)\n",
            nrow(hospital_pref_df), n_distinct(hospital_pref_df$year)))

# =============================================================================
# 4. 放射線治療設備（都道府県）
# =============================================================================
cat("\n=== 4. 放射線治療設備（都道府県）===\n")

# T75/E65 format:
# Cols: 都道府県, 総数, Xﾘﾝ(施設,患者,台), CTﾘﾝ(施設,患者,台),
#       計画装置(施設,患者,台), 体外照射(施設,患者),
#       リニアック(施設,患者,台), ガンマナイフ(施設,患者,台),
#       腔内(施設,患者)
# → 台数と患者数を抽出

radiation_items <- list(
  list(id = "rt_plan_equip", name = "放射線治療計画装置 台数", col = 11),
  list(id = "rt_plan_patients", name = "放射線治療計画装置 患者数", col = 10),
  list(id = "rt_external_facilities", name = "体外照射 施設数", col = 12),
  list(id = "rt_external_patients", name = "体外照射 患者数", col = 13),
  list(id = "rt_linac_facilities", name = "リニアック 施設数", col = 14),
  list(id = "rt_linac_patients", name = "リニアック 患者数", col = 15),
  list(id = "rt_linac_units", name = "リニアック 台数", col = 16),
  list(id = "rt_gamma_facilities", name = "ガンマナイフ 施設数", col = 17),
  list(id = "rt_gamma_patients", name = "ガンマナイフ 患者数", col = 18),
  list(id = "rt_gamma_units", name = "ガンマナイフ 台数", col = 19),
  list(id = "rt_brachy_facilities", name = "腔内・組織内 施設数", col = 20),
  list(id = "rt_brachy_patients", name = "腔内・組織内 患者数", col = 21)
)

radiation_pref <- list()
rad_files <- list.files(file.path(data_dir, "facility"),
                         pattern = "radiation_pref.*\\.csv$", full.names = TRUE)

for (rf in rad_files) {
  year_match <- regmatches(rf, regexpr("\\d{4}\\.csv", rf))
  if (length(year_match) == 0) next
  yr <- as.integer(sub("\\.csv$", "", year_match))

  lines <- read_cp932(rf)
  # データ行を探す: "全" で始まる行の次が都道府県
  national_idx <- grep("^全", lines)
  if (length(national_idx) == 0) next
  data_start <- national_idx[1] + 1

  for (i in data_start:min(length(lines), data_start + 47)) {
    parts <- strsplit(lines[i], ",")[[1]]
    if (length(parts) < 10) next
    pref_idx <- i - data_start + 1
    if (pref_idx < 1 || pref_idx > 47) next
    pc <- sprintf("%02d", pref_idx)

    for (item in radiation_items) {
      if (item$col <= length(parts)) {
        val <- trimws(parts[item$col])
        val_num <- suppressWarnings(as.numeric(val))
        if (is.na(val_num) && val == "-") val_num <- NA_real_
        radiation_pref[[length(radiation_pref) + 1]] <- data.frame(
          pref_code = pc, year = yr, item_id = item$id,
          value = val_num, stringsAsFactors = FALSE)
      }
    }
  }
}

radiation_pref_df <- if (length(radiation_pref) > 0) bind_rows(radiation_pref) else data.frame()
cat(sprintf("  放射線治療: %d records (%d years)\n",
            nrow(radiation_pref_df), n_distinct(radiation_pref_df$year)))

# =============================================================================
# 5. 医師数（都道府県）
# =============================================================================
cat("\n=== 5. 医師数（都道府県）===\n")

physician_pref <- list()
phys_files <- list.files(file.path(data_dir, "physician"), pattern = "\\.csv$", full.names = TRUE)

for (pf in phys_files) {
  year_match <- regmatches(pf, regexpr("\\d{4}\\.csv", pf))
  if (length(year_match) == 0) next
  yr <- as.integer(sub("\\.csv$", "", year_match))

  # 診療科別(医療施設従事)表(第43/24/25/26表)は放射線科医抽出専用。都道府県医師数総数には使わない。
  if (grepl("(T24|T25|T26|T43)", basename(pf))) next

  lines <- read_cp932(pf)

  # T25形式(2022): "01北海道" (半角2桁+名前), col2=総数
  #   → SMA行 "0101南渡島" や市区町村行 "01202函館市" を除外するため
  #     正確に2桁+非数字で都道府県のみ抽出
  # T27形式(2016,2018,2020): "０１　北海道" (全角2桁), col4=総数
  # T03形式(2014): 別のヘッダ構造

  is_t25 <- grepl("T25", basename(pf))

  # 第3表(2014)特例: 都道府県は全角コード"０１　北　海　道"の名称行で表され、
  # 届出総数は直後の "総数,総数,<値>" 行の col3 にある(名称行の col2-6 は空)。
  # 汎用処理では名称行で数値が拾えず、年齢階級行を誤マッチするため専用に抽出する。
  is_t03 <- grepl("T03", basename(pf))
  if (is_t03) {
    zen3 <- c("０","１","２","３","４","５","６","７","８","９"); han3 <- as.character(0:9)
    for (i in seq_along(lines)) {
      parts <- strsplit(lines[i], ",")[[1]]
      if (length(parts) < 1) next
      col1 <- trimws(parts[1])
      m <- regmatches(col1, regexpr("^[０-９]{2}", col1))
      if (length(m) == 0) next
      code_str <- m
      for (k in seq_along(zen3)) code_str <- gsub(zen3[k], han3[k], code_str)
      pref_code <- substr(code_str, 1, 2)
      if (!(pref_code %in% pref_codes)) next
      for (j in (i + 1):min(i + 3, length(lines))) {
        p2 <- strsplit(lines[j], ",")[[1]]
        if (length(p2) >= 3 && trimws(gsub("　", "", p2[2])) == "総数") {
          total <- suppressWarnings(as.numeric(trimws(p2[3])))
          if (!is.na(total) && total > 0) {
            physician_pref[[length(physician_pref) + 1]] <- data.frame(
              pref_code = pref_code, year = yr, physicians = as.integer(total),
              stringsAsFactors = FALSE)
          }
          break
        }
      }
    }
    next
  }

  for (i in seq_along(lines)) {
    parts <- strsplit(lines[i], ",")[[1]]
    if (length(parts) < 2) next

    col1 <- trimws(parts[1])
    pref_code <- NULL

    # パターン1: "０１北海道" or "０１　北　海　道" (全角数字)
    m <- regmatches(col1, regexpr("^[０-９]{2}", col1))
    if (length(m) > 0) {
      zen <- c("０","１","２","３","４","５","６","７","８","９")
      han <- as.character(0:9)
      code_str <- col1
      for (k in seq_along(zen)) code_str <- gsub(zen[k], han[k], code_str)
      pref_code <- substr(code_str, 1, 2)
    }

    # パターン2: "01北海道" (半角2桁 + 直後に非数字) — T25形式
    # SMA "0101..." や市区町村 "01202..." を除外するため、2桁の後に数字が続かないことを確認
    if (is.null(pref_code) && grepl("^(0[1-9]|[1-3][0-9]|4[0-7])[^0-9]", col1)) {
      pref_code <- substr(col1, 1, 2)
    }

    if (!is.null(pref_code) && pref_code %in% pref_codes) {
      # 総数 = parts内の最初の非空数値（全形式共通）
      # T27_2016: col2=総数, T27_2020: col4=総数(先頭に空列), T25_2022: col2=総数
      total <- NA_real_
      for (c in 2:min(6, length(parts))) {
        v <- suppressWarnings(as.numeric(trimws(parts[c])))
        if (!is.na(v)) { total <- v; break }
      }
      if (!is.na(total) && total > 0) {
        physician_pref[[length(physician_pref) + 1]] <- data.frame(
          pref_code = pref_code, year = yr, physicians = as.integer(total),
          stringsAsFactors = FALSE)
      }
    }
  }
}

physician_pref_df <- if (length(physician_pref) > 0) {
  bind_rows(physician_pref) |>
    group_by(pref_code, year) |>
    slice_head(n = 1) |>  # 重複除去（最初のマッチのみ）
    ungroup()
} else {
  data.frame()
}
cat(sprintf("  医師数: %d records (%d years)\n",
            nrow(physician_pref_df), n_distinct(physician_pref_df$year)))

# =============================================================================
# 5b. 診療放射線技師・看護師（都道府県, 常勤換算）
# =============================================================================
cat("\n=== 5b. 診療放射線技師・看護師 ===\n")

staff_pref <- list()
staff_files <- list.files(file.path(data_dir, "facility"),
                          pattern = "staff_pref_(G31|T8[12])_\\d{4}\\.csv$",
                          full.names = TRUE)

# col12=看護師, col22=診療放射線技師 (FTE) — stable across G31/T82/T81
for (sf in staff_files) {
  year_match <- regmatches(sf, regexpr("\\d{4}\\.csv", sf))
  if (length(year_match) == 0) next
  yr <- as.integer(sub("\\.csv$", "", year_match))

  d <- tryCatch(
    read.csv(sf, header = FALSE, fileEncoding = "CP932", stringsAsFactors = FALSE),
    error = function(e) NULL)
  if (is.null(d)) next

  # Find 全国 row
  nat_row <- which(grepl("^全", trimws(d[[1]])))[1]
  if (is.na(nat_row)) next

  for (pi in 1:47) {
    r <- nat_row + pi
    if (r > nrow(d)) break
    pc <- sprintf("%02d", pi)
    nurse_val <- suppressWarnings(as.numeric(trimws(as.character(d[r, 12]))))
    rt_val <- suppressWarnings(as.numeric(trimws(as.character(d[r, 22]))))
    if (!is.na(nurse_val)) {
      staff_pref[[length(staff_pref) + 1]] <- data.frame(
        pref_code = pc, year = yr, item_id = "nurses", value = nurse_val,
        stringsAsFactors = FALSE)
    }
    if (!is.na(rt_val)) {
      staff_pref[[length(staff_pref) + 1]] <- data.frame(
        pref_code = pc, year = yr, item_id = "rad_technologists", value = rt_val,
        stringsAsFactors = FALSE)
    }
  }
}

staff_pref_df <- if (length(staff_pref) > 0) bind_rows(staff_pref) else data.frame()
cat(sprintf("  スタッフ: %d records (%d years)\n",
            nrow(staff_pref_df), n_distinct(staff_pref_df$year)))
for (item in c("nurses", "rad_technologists")) {
  sub <- staff_pref_df[staff_pref_df$item_id == item, ]
  if (nrow(sub) > 0) {
    cat(sprintf("    %s: %d records, 全国合計(最新)=%.1f\n",
                item, nrow(sub),
                sum(sub$value[sub$year == max(sub$year)], na.rm = TRUE)))
  }
}

# =============================================================================
# 5c. 放射線科医（都道府県 + 二次医療圏）
# =============================================================================
cat("\n=== 5c. 放射線科医 ===\n")

rad_doctor_pref <- list()
rad_doctor_sma <- list()

# --- 放射線科医: 医師統計の都道府県×診療科(複数回答, 医療施設従事)表から放射線科を抽出 ---
# 全隔年(2014/16/18/20/22/24)を同一基準(医療施設従事=病院+診療所・複数回答)で取得。
# 表番号・列位置・行レイアウトが年で異なる:
#   2014/16=第43表, 2018/20=閲覧第24表, 2022=第25表, 2024=第26表
#   放射線科の列: 2014/16/18/22/24=col37, 2020=col40(診療科追加でずれ)
#   県名: 2014-2020=全角("０１　北　海　道"/"０１北海道"), 2022/24=半角("01北海道")
#   2020のみ col1="医療施設従事"・県コードがcol2 と列構成が異なる
# → 放射線科の列はヘッダから検出し、県コードは先頭数列から正規化して判定(全年対応)。
collect_rad_specialty <- function(file_path, yr) {
  pref <- list(); sma <- list()
  if (!file.exists(file_path)) return(list(pref = pref, sma = sma))
  zen <- c("０","１","２","３","４","５","６","７","８","９")
  normz <- function(s) {
    s <- as.character(s); if (length(s) == 0 || is.na(s)) return("")
    for (k in seq_along(zen)) s <- gsub(zen[k], k - 1, s, fixed = TRUE)
    gsub(" ", "", gsub("　", "", s), fixed = TRUE)
  }
  d <- read.csv(file_path, header = FALSE, fileEncoding = "CP932", stringsAsFactors = FALSE)
  nc <- ncol(d)
  # 放射線科の列をヘッダ行(上位8行)から完全一致で検出
  radcol <- NA_integer_
  for (hr in 1:min(8, nrow(d))) {
    for (cc in 1:nc) {
      v <- gsub("　", "", trimws(as.character(d[hr, cc])))
      if (!is.na(v) && v == "放射線科") { radcol <- cc; break }
    }
    if (!is.na(radcol)) break
  }
  if (is.na(radcol)) {
    cat(sprintf("    WARNING: 放射線科 列が見つかりません: %s\n", basename(file_path)))
    return(list(pref = pref, sma = sma))
  }
  for (r in seq_len(nrow(d))) {
    code <- NA_character_; is_sma <- FALSE
    for (cc in 1:min(3, nc)) {                    # 県コードは先頭数列のいずれか
      cell <- normz(d[r, cc])
      if (grepl("^(0[1-9]|[1-3][0-9]|4[0-7])[^0-9]", cell)) { code <- substr(cell, 1, 2); is_sma <- FALSE; break }
      lead <- regmatches(cell, regexpr("^[0-9]+", cell))
      if (length(lead) > 0 && nchar(lead) == 4) { code <- lead; is_sma <- TRUE; break }
    }
    if (is.na(code)) next
    vs <- trimws(as.character(d[r, radcol]))
    val <- suppressWarnings(as.integer(vs))
    if (!is.na(vs) && vs == "-") val <- 0L
    if (is.na(val)) next
    rec <- data.frame(code = code, year = yr, rad_doctors = val, stringsAsFactors = FALSE)
    if (is_sma) { names(rec)[1] <- "sma_code"; sma[[length(sma) + 1]] <- rec }
    else        { names(rec)[1] <- "pref_code"; pref[[length(pref) + 1]] <- rec }
  }
  list(pref = pref, sma = sma)
}

for (rt in list(list(f = "physician_T43_2014.csv", y = 2014L),
                list(f = "physician_T43_2016.csv", y = 2016L),
                list(f = "physician_T24_2018.csv", y = 2018L),
                list(f = "physician_T24_2020.csv", y = 2020L),
                list(f = "physician_T25_2022.csv", y = 2022L),
                list(f = "physician_T26_2024.csv", y = 2024L))) {
  res <- collect_rad_specialty(file.path(data_dir, "physician", rt$f), rt$y)
  rad_doctor_pref <- c(rad_doctor_pref, res$pref)
  rad_doctor_sma  <- c(rad_doctor_sma,  res$sma)
}

rad_doctor_pref_df <- if (length(rad_doctor_pref) > 0) {
  bind_rows(rad_doctor_pref) |>
    group_by(pref_code, year) |> slice_head(n = 1) |> ungroup()
} else data.frame()

rad_doctor_sma_df <- if (length(rad_doctor_sma) > 0) {
  bind_rows(rad_doctor_sma) |>
    group_by(sma_code, year) |> slice_head(n = 1) |> ungroup()
} else data.frame()

cat(sprintf("  放射線科医(都道府県): %d records (%d years)\n",
            nrow(rad_doctor_pref_df), n_distinct(rad_doctor_pref_df$year)))
cat(sprintf("  放射線科医(SMA): %d records (%d years)\n",
            nrow(rad_doctor_sma_df), n_distinct(rad_doctor_sma_df$year)))

# =============================================================================
# 6. 人口データ
# =============================================================================
cat("\n=== 6. 人口データ ===\n")

# --- 6a. 総人口 ---
parse_pop_xls <- function(file_path, target_years) {
  df <- read_excel(file_path, sheet = 1, col_names = FALSE, col_types = "text")
  result <- list()
  year_cols <- 13:17
  found_count <- 0
  for (i in 20:nrow(df)) {
    pref_num <- as.character(df[[9]][i])
    if (!is.na(pref_num) && grepl("^[0-4][0-9]$", pref_num)) {
      found_count <- found_count + 1
      if (found_count > 47) break
      for (j in seq_along(year_cols)) {
        if (j <= length(target_years)) {
          pop_val <- suppressWarnings(as.numeric(as.character(df[[year_cols[j]]][i])))
          if (!is.na(pop_val)) {
            result[[length(result) + 1]] <- data.frame(
              pref_code = pref_num, year = target_years[j],
              population_1000 = pop_val, stringsAsFactors = FALSE)
          }
        }
      }
    }
  }
  bind_rows(result)
}

parse_pop_xlsx <- function(file_path, target_years) {
  df <- read_excel(file_path, sheet = 1, col_names = FALSE, col_types = "text")
  result <- list()
  year_cols <- 14:18
  for (i in 8:nrow(df)) {
    pref_code_raw <- as.character(df[[10]][i])
    pop_type <- as.character(df[[8]][i])
    sex <- as.character(df[[9]][i])
    if (!is.na(pref_code_raw) && grepl("^\\d{5}$", pref_code_raw) &&
        pref_code_raw != "00000") {
      if (!is.na(pop_type) && grepl("総人口", pop_type) &&
          !is.na(sex) && grepl("男女計", sex)) {
        pref_code <- sprintf("%02d", as.integer(pref_code_raw) / 1000)
        for (j in seq_along(year_cols)) {
          if (j <= length(target_years)) {
            pop_val <- suppressWarnings(as.numeric(as.character(df[[year_cols[j]]][i])))
            if (!is.na(pop_val)) {
              result[[length(result) + 1]] <- data.frame(
                pref_code = pref_code, year = target_years[j],
                population_1000 = pop_val, stringsAsFactors = FALSE)
            }
          }
        }
      }
    }
  }
  bind_rows(result)
}

pop_files <- list(
  list(path = file.path(data_dir, "population/population_total_pref_2014.xls"),
       years = 2010:2014, format = "xls"),
  list(path = file.path(data_dir, "population/population_total_pref_2019.xls"),
       years = 2015:2019, format = "xls"),
  list(path = file.path(data_dir, "population/population_total_pref_2023.xlsx"),
       years = c(2015, 2020:2023), format = "xlsx"),
  list(path = file.path(data_dir, "population/population_total_pref_2024.xlsx"),
       years = c(2020:2024), format = "xlsx")
)

pop_all <- list()
for (pf in pop_files) {
  if (!file.exists(pf$path)) next
  tryCatch({
    if (pf$format == "xls") {
      pop_all[[length(pop_all) + 1]] <- parse_pop_xls(pf$path, pf$years)
    } else {
      pop_all[[length(pop_all) + 1]] <- parse_pop_xlsx(pf$path, pf$years)
    }
  }, error = function(e) cat(sprintf("  ERROR parsing %s: %s\n", basename(pf$path), e$message)))
}

pop_total <- bind_rows(pop_all) |>
  filter(year >= 2014) |>
  mutate(population = population_1000 * 1000) |>
  group_by(pref_code, year) |>
  slice_head(n = 1) |>
  ungroup() |>
  select(pref_code, year, population) |>
  arrange(year, pref_code)

cat(sprintf("  総人口: %d records (%d prefectures x %d years)\n",
            nrow(pop_total), n_distinct(pop_total$pref_code), n_distinct(pop_total$year)))

# --- 6b. 高齢者人口 (65歳以上) ---
parse_elderly_old <- function(file_path, year) {
  # 旧形式(.xls): 31列, Row14にヘッダ
  # Col 9=都道府県コード, 13=総数, 27=65~69, 28=70~74, 29=75~79, 30=80~84, 31=85歳以上
  # Row 20 = 全国 (col12="Japan"), Row 21-67 = 都道府県 (col9=01-47)
  df <- read_excel(file_path, sheet = 1, col_names = FALSE, col_types = "text")
  elderly_cols <- 27:31  # 65-69, 70-74, 75-79, 80-84, 85+
  result <- list()

  for (i in 16:min(nrow(df), 200)) {
    # 列9で都道府県コードを確認
    pref_code_raw <- as.character(df[[9]][i])
    if (is.na(pref_code_raw) || !grepl("^[0-4][0-9]$", pref_code_raw)) next

    total_val <- suppressWarnings(as.numeric(as.character(df[[13]][i])))
    if (is.na(total_val)) next

    # 65歳以上を合算
    elderly_sum <- 0
    for (ec in elderly_cols) {
      if (ec <= ncol(df)) {
        v <- suppressWarnings(as.numeric(as.character(df[[ec]][i])))
        if (!is.na(v)) elderly_sum <- elderly_sum + v
      }
    }

    if (elderly_sum > 0) {
      result[[length(result) + 1]] <- data.frame(
        pref_code = pref_code_raw, year = year,
        elderly_pop_1000 = elderly_sum, stringsAsFactors = FALSE)
    }
    if (length(result) >= 47) break
  }

  if (length(result) > 0) bind_rows(result) else NULL
}

parse_elderly_new <- function(file_path, year) {
  # 新形式(.xlsx DB): 34列, Row7にヘッダ
  # Col 10=人口区分, 11=都道府県コード(5桁), 13=性別
  # Col 16=総数, 30=65~69歳, 31=70~74歳, 32=75~79歳, 33=80~84歳, 34=85歳以上
  df <- read_excel(file_path, sheet = 1, col_names = FALSE, col_types = "text")
  elderly_cols <- 30:34
  result <- list()

  for (i in 8:nrow(df)) {
    pref_code_raw <- as.character(df[[11]][i])  # 都道府県コード列
    pop_type <- as.character(df[[10]][i])  # 人口区分

    if (is.na(pref_code_raw)) next
    # 5桁コード(01000-47000) かつ "総人口" かつ "男女計"
    if (!grepl("^(0[1-9]|[1-3][0-9]|4[0-7])000$", pref_code_raw)) next
    if (!is.na(pop_type) && !grepl("総人口", pop_type)) next

    sex <- as.character(df[[13]][i])
    if (!is.na(sex) && !grepl("男女計", sex)) next

    pref_code <- sprintf("%02d", as.integer(pref_code_raw) / 1000)

    elderly_sum <- 0
    for (ec in elderly_cols) {
      if (ec <= ncol(df)) {
        v <- suppressWarnings(as.numeric(as.character(df[[ec]][i])))
        if (!is.na(v)) elderly_sum <- elderly_sum + v
      }
    }

    if (elderly_sum > 0) {
      result[[length(result) + 1]] <- data.frame(
        pref_code = pref_code, year = year,
        elderly_pop_1000 = elderly_sum, stringsAsFactors = FALSE)
    }
  }

  if (length(result) > 0) bind_rows(result) else NULL
}

elderly_all <- list()
age_files <- list.files(file.path(data_dir, "population"), pattern = "age5", full.names = TRUE)

for (af in age_files) {
  yr_match <- regmatches(af, regexpr("\\d{4}\\.", af))
  if (length(yr_match) == 0) next
  yr <- as.integer(sub("\\.$", "", yr_match))
  ext <- tools::file_ext(af)

  cat(sprintf("  [%d] %s ...", yr, basename(af)))
  tryCatch({
    # 旧形式(31列)か新形式(34列)か判定
    df_check <- read_excel(af, sheet = 1, col_names = FALSE, col_types = "text", n_max = 10)
    n_cols <- ncol(df_check)

    if (n_cols <= 32) {
      result <- parse_elderly_old(af, yr)
    } else {
      result <- parse_elderly_new(af, yr)
    }

    if (!is.null(result) && nrow(result) > 0) {
      elderly_all[[length(elderly_all) + 1]] <- result
      cat(sprintf(" %d prefectures\n", nrow(result)))
    } else {
      cat(" (no data extracted)\n")
    }
  }, error = function(e) cat(sprintf(" ERROR: %s\n", e$message)))
}

pop_elderly <- if (length(elderly_all) > 0) {
  bind_rows(elderly_all) |>
    mutate(population_65plus = elderly_pop_1000 * 1000) |>
    group_by(pref_code, year) |>
    slice_head(n = 1) |>
    ungroup() |>
    select(pref_code, year, population_65plus) |>
    arrange(year, pref_code)
} else {
  data.frame(pref_code = character(), year = integer(), population_65plus = numeric())
}

cat(sprintf("  高齢者人口: %d records (%d years)\n",
            nrow(pop_elderly), n_distinct(pop_elderly$year)))

# 欠測年の補間: 2015(国勢調査年版の取込不可)・2020(ソース欠如時)等を線形補間で補完。
# 各都道府県について 2014:2024 の欠測年を前後の実測年から線形補間(範囲外は最近接年で外挿)。
elderly_target_years <- 2014:2024
if (nrow(pop_elderly) > 0) {
  interp_rows <- list()
  interp_years <- integer(0)
  for (pc in unique(pop_elderly$pref_code)) {
    sub <- pop_elderly[pop_elderly$pref_code == pc, ]
    hv <- sub$year
    vmap <- setNames(sub$population_65plus, as.character(sub$year))
    for (ty in elderly_target_years) {
      if (ty %in% hv) next
      lower <- hv[hv < ty]; upper <- hv[hv > ty]
      if (length(lower) > 0 && length(upper) > 0) {
        y0 <- max(lower); y1 <- min(upper)
        v0 <- vmap[[as.character(y0)]]; v1 <- vmap[[as.character(y1)]]
        val <- round(v0 + (v1 - v0) * (ty - y0) / (y1 - y0))
      } else if (length(lower) > 0) {
        val <- vmap[[as.character(max(lower))]]
      } else if (length(upper) > 0) {
        val <- vmap[[as.character(min(upper))]]
      } else next
      interp_rows[[length(interp_rows) + 1]] <- data.frame(
        pref_code = pc, year = ty, population_65plus = val, stringsAsFactors = FALSE)
      interp_years <- c(interp_years, ty)
    }
  }
  if (length(interp_rows) > 0) {
    pop_elderly <- bind_rows(pop_elderly, bind_rows(interp_rows)) |>
      arrange(year, pref_code)
    cat(sprintf("  高齢者人口(補間後): %d records, 補間 %d 件 (補間年: %s)\n",
                nrow(pop_elderly), length(interp_rows),
                paste(sort(unique(interp_years)), collapse = ", ")))
  }
}

# --- 6d. 人口（都道府県, 性年齢別 → SCR用）---
cat("  --- 都道府県人口（性年齢別, SCR用）---\n")

pop_age_groups <- c("0-4", "5-9", "10-14", "15-19", "20-24", "25-29", "30-34", "35-39",
                    "40-44", "45-49", "50-54", "55-59", "60-64", "65-69", "70-74", "75-79",
                    "80-84", "85+")

parse_pop_sexage_old <- function(file_path, year) {
  # Old format (.xls, 31 cols)
  # Col 3: sex code ("01"=男女計, "02"=男, "03"=女)
  # Col 9: pref code (2-digit), Cols 14-31: 18 age groups (千人)
  df <- read_excel(file_path, sheet = 1, col_names = FALSE, col_types = "text")
  age_cols <- 14:31
  result <- list()

  for (i in 1:nrow(df)) {
    sex_code <- trimws(as.character(df[[3]][i]))
    pref_code_raw <- as.character(df[[9]][i])
    if (is.na(sex_code) || is.na(pref_code_raw)) next
    if (!(pref_code_raw %in% pref_codes)) next

    sex <- switch(sex_code, "02" = "M", "03" = "F", NULL)
    if (is.null(sex)) next

    for (j in seq_along(age_cols)) {
      if (j > length(pop_age_groups)) break
      val <- suppressWarnings(as.numeric(as.character(df[[age_cols[j]]][i])))
      if (!is.na(val)) {
        result[[length(result) + 1]] <- data.frame(
          pref_code = pref_code_raw, year = year, sex = sex,
          age_group = pop_age_groups[j], population = val * 1000,
          stringsAsFactors = FALSE)
      }
    }
  }

  if (length(result) > 0) bind_rows(result) else NULL
}

parse_pop_sexage_new <- function(file_path, year) {
  # New format (.xlsx, 34 cols)
  # Col 10: 人口区分 (総人口), Col 11: pref code (5-digit)
  # Col 13: sex (男/女/男女計), Cols 17-34: 18 age groups (千人)
  df <- read_excel(file_path, sheet = 1, col_names = FALSE, col_types = "text")
  age_cols <- 17:34
  result <- list()

  for (i in 8:nrow(df)) {
    pref_code_raw <- as.character(df[[11]][i])
    pop_type <- as.character(df[[10]][i])
    sex_label <- as.character(df[[13]][i])
    if (is.na(pref_code_raw) || is.na(sex_label)) next
    if (!grepl("^(0[1-9]|[1-3][0-9]|4[0-7])000$", pref_code_raw)) next
    if (!is.na(pop_type) && !grepl("総人口", pop_type)) next

    sex <- switch(sex_label, "\u7537" = "M", "\u5973" = "F", NULL)
    if (is.null(sex)) next

    pref_code <- sprintf("%02d", as.integer(pref_code_raw) / 1000)

    for (j in seq_along(age_cols)) {
      if (j > length(pop_age_groups)) break
      val <- suppressWarnings(as.numeric(as.character(df[[age_cols[j]]][i])))
      if (!is.na(val)) {
        result[[length(result) + 1]] <- data.frame(
          pref_code = pref_code, year = year, sex = sex,
          age_group = pop_age_groups[j], population = val * 1000,
          stringsAsFactors = FALSE)
      }
    }
  }

  if (length(result) > 0) bind_rows(result) else NULL
}

pop_sexage_all <- list()
for (af in age_files) {
  yr_match <- regmatches(af, regexpr("\\d{4}\\.", af))
  if (length(yr_match) == 0) next
  yr <- as.integer(sub("\\.$", "", yr_match))

  cat(sprintf("  [%d] sexage %s ...", yr, basename(af)))
  tryCatch({
    df_check <- read_excel(af, sheet = 1, col_names = FALSE, col_types = "text", n_max = 10)
    n_cols <- ncol(df_check)

    if (n_cols <= 32) {
      result <- parse_pop_sexage_old(af, yr)
    } else {
      result <- parse_pop_sexage_new(af, yr)
    }

    if (!is.null(result) && nrow(result) > 0) {
      pop_sexage_all[[length(pop_sexage_all) + 1]] <- result
      cat(sprintf(" %d records\n", nrow(result)))
    } else {
      cat(" (no sex/age data)\n")
    }
  }, error = function(e) cat(sprintf(" ERROR: %s\n", e$message)))
}

pop_sexage <- if (length(pop_sexage_all) > 0) {
  bind_rows(pop_sexage_all) |>
    group_by(pref_code, year, sex, age_group) |>
    slice_head(n = 1) |>
    ungroup()
} else {
  data.frame(pref_code = character(), year = integer(), sex = character(),
             age_group = character(), population = numeric())
}

cat(sprintf("  人口（性年齢別）: %d records (%d prefs x %d years x %d ages)\n",
            nrow(pop_sexage), n_distinct(pop_sexage$pref_code),
            n_distinct(pop_sexage$year), n_distinct(pop_sexage$age_group)))

# --- 6c. 二次医療圏人口 (A38-14 + A38-20 線形補間) ---
cat("  --- 二次医療圏人口 (A38-14 + A38-20 線形補間) ---\n")

read_a38_dbf <- function(dbf_path, label) {
  if (!file.exists(dbf_path)) { cat(sprintf("  WARNING: %s not found\n", label)); return(NULL) }
  d <- foreign::read.dbf(dbf_path, as.is = TRUE)
  d |> mutate(sma_code = trimws(as.character(A38b_003))) |>
    filter(nchar(sma_code) == 4) |>
    distinct(sma_code, .keep_all = TRUE) |>
    transmute(sma_code,
              pop_total = as.numeric(A38b_008),
              pop_elderly = as.numeric(A38b_011))
}

a38_14 <- read_a38_dbf(file.path(data_dir, "geo/A38-14_GML/A38-14_2.dbf"), "A38-14")
a38_20 <- read_a38_dbf(file.path(data_dir, "geo/A38-20_GML/A38-20_2.dbf"), "A38-20")

# A38-14 ≈ 2013年人口, A38-20 ≈ 2020年人口
# 2014-2023の各年について線形補間 (2013-2020区間 + 2020以降は2020値で固定)
a38_ref_year_14 <- 2013
a38_ref_year_20 <- 2020

pop_sma_total <- data.frame(sma_code = character(), year = integer(),
                            population = numeric(), stringsAsFactors = FALSE)
pop_sma_elderly <- data.frame(sma_code = character(), year = integer(),
                              population_65plus = numeric(), stringsAsFactors = FALSE)

if (!is.null(a38_14) || !is.null(a38_20)) {
  # Get union of SMA codes
  all_sma <- unique(c(
    if (!is.null(a38_14)) a38_14$sma_code else character(),
    if (!is.null(a38_20)) a38_20$sma_code else character()
  ))
  cat(sprintf("  A38-14: %s regions, A38-20: %s regions, union: %d\n",
              if (!is.null(a38_14)) nrow(a38_14) else "N/A",
              if (!is.null(a38_20)) nrow(a38_20) else "N/A",
              length(all_sma)))

  sma_pop_rows <- list()
  sma_eld_rows <- list()
  for (sc in all_sma) {
    p14 <- if (!is.null(a38_14)) a38_14[a38_14$sma_code == sc, ] else data.frame()
    p20 <- if (!is.null(a38_20)) a38_20[a38_20$sma_code == sc, ] else data.frame()
    has14 <- nrow(p14) > 0 && !is.na(p14$pop_total[1]) && p14$pop_total[1] > 0
    has20 <- nrow(p20) > 0 && !is.na(p20$pop_total[1]) && p20$pop_total[1] > 0

    for (yr in 2014:2024) {
      if (has14 && has20) {
        # Linear interpolation between 2013 and 2020, capped at 2020 for yr > 2020
        t <- min(max((yr - a38_ref_year_14) / (a38_ref_year_20 - a38_ref_year_14), 0), 1)
        pop_t <- round(p14$pop_total[1] + t * (p20$pop_total[1] - p14$pop_total[1]))
        pop_e <- round(p14$pop_elderly[1] + t * (p20$pop_elderly[1] - p14$pop_elderly[1]))
      } else if (has20) {
        pop_t <- p20$pop_total[1]; pop_e <- p20$pop_elderly[1]
      } else if (has14) {
        pop_t <- p14$pop_total[1]; pop_e <- p14$pop_elderly[1]
      } else {
        next
      }
      sma_pop_rows[[length(sma_pop_rows) + 1]] <- data.frame(
        sma_code = sc, year = yr, population = pop_t, stringsAsFactors = FALSE)
      if (!is.na(pop_e)) {
        sma_eld_rows[[length(sma_eld_rows) + 1]] <- data.frame(
          sma_code = sc, year = yr, population_65plus = pop_e, stringsAsFactors = FALSE)
      }
    }
  }

  pop_sma_total <- if (length(sma_pop_rows) > 0) bind_rows(sma_pop_rows) else pop_sma_total
  pop_sma_elderly <- if (length(sma_eld_rows) > 0) bind_rows(sma_eld_rows) else pop_sma_elderly

  cat(sprintf("  SMA総人口: %d records (%d regions x %d years)\n",
              nrow(pop_sma_total), n_distinct(pop_sma_total$sma_code),
              n_distinct(pop_sma_total$year)))
  cat(sprintf("  SMA高齢者人口: %d records\n", nrow(pop_sma_elderly)))

  # Show sample interpolation
  sample_sc <- head(all_sma, 2)
  for (sc in sample_sc) {
    r14 <- pop_sma_total[pop_sma_total$sma_code == sc & pop_sma_total$year == 2014, ]
    r20 <- pop_sma_total[pop_sma_total$sma_code == sc & pop_sma_total$year == 2020, ]
    cat(sprintf("    %s: 2014=%s → 2020=%s (interpolated)\n", sc,
                if (nrow(r14) > 0) format(r14$population, big.mark = ",") else "NA",
                if (nrow(r20) > 0) format(r20$population, big.mark = ",") else "NA"))
  }
} else {
  cat("  WARNING: No A38 DBF found, SMA population not available\n")
}

# =============================================================================
# 7. 二次医療圏マッピング
# =============================================================================
cat("\n=== 7. 二次医療圏マッピング ===\n")

sma_lookup_file <- file.path(data_dir, "geo/sma_lookup.csv")
sma_lookup <- if (file.exists(sma_lookup_file)) {
  read.csv(sma_lookup_file, stringsAsFactors = FALSE, fileEncoding = "UTF-8") |>
    mutate(sma_code = sprintf("%04d", as.integer(sma_code)),
           pref_code = sprintf("%02d", as.integer(pref_code)))
} else {
  cat("  WARNING: sma_lookup.csv not found\n")
  data.frame(sma_code = character(), sma_name = character(), pref_code = character())
}
cat(sprintf("  二次医療圏: %d regions\n", nrow(sma_lookup)))

# =============================================================================
# 8. 病院数（二次医療圏）
# =============================================================================
cat("\n=== 8. 病院数（二次医療圏）===\n")

hospital_sma <- list()
sma_hosp_files <- list.files(file.path(data_dir, "facility/sma"),
                              pattern = "hospitals_sma.*\\.csv$", full.names = TRUE)

for (sf in sma_hosp_files) {
  year_match <- regmatches(sf, regexpr("\\d{4}\\.csv", sf))
  if (length(year_match) == 0) next
  yr <- as.integer(sub("\\.csv$", "", year_match))

  lines <- read_cp932(sf)

  for (i in seq_along(lines)) {
    parts <- strsplit(lines[i], ",")[[1]]
    if (length(parts) < 3) next
    col1 <- trimws(parts[1])

    # 二次医療圏コード: 正確に4桁 + 非数字 (市区町村の5桁コードを除外)
    # "0101　南渡島" → match, "01202 函館市" → no match
    # 先頭の連続数字を抽出し、ちょうど4桁のものだけ使用
    leading_digits <- regmatches(col1, regexpr("^[0-9]+", col1))
    if (length(leading_digits) > 0 && nchar(leading_digits) == 4) {
      sma_code <- leading_digits
      if (sma_code %in% sma_lookup$sma_code) {
        # 施設数 = col 2
        hosp_count <- suppressWarnings(as.integer(trimws(parts[2])))
        if (!is.na(hosp_count)) {
          hospital_sma[[length(hospital_sma) + 1]] <- data.frame(
            sma_code = sma_code, year = yr, hospitals = hosp_count,
            stringsAsFactors = FALSE)
        }
      }
    }
  }
}

hospital_sma_df <- if (length(hospital_sma) > 0) bind_rows(hospital_sma) else data.frame()
cat(sprintf("  SMA病院数: %d records (%d years)\n",
            nrow(hospital_sma_df), n_distinct(hospital_sma_df$year)))

# =============================================================================
# 8b. 放射線治療設備（二次医療圏）
# =============================================================================
cat("\n=== 8b. 放射線治療設備（二次医療圏）===\n")

radiation_sma <- list()
sma_rad_files <- list.files(file.path(data_dir, "facility/sma"),
                             pattern = "radiation_sma.*\\.csv$", full.names = TRUE)

for (sf in sma_rad_files) {
  year_match <- regmatches(sf, regexpr("\\d{4}\\.csv", sf))
  if (length(year_match) == 0) next
  yr <- as.integer(sub("\\.csv$", "", year_match))

  d <- tryCatch(
    read.csv(sf, header = FALSE, fileEncoding = "CP932", stringsAsFactors = FALSE),
    error = function(e) NULL)
  if (is.null(d)) next

  # SMA radiation files have same column layout as pref files
  for (r in 1:nrow(d)) {
    col1 <- trimws(as.character(d[r, 1]))
    leading <- regmatches(col1, regexpr("^[0-9]+", col1))
    if (length(leading) == 0 || nchar(leading) != 4) next
    sc <- leading
    if (!(sc %in% sma_lookup$sma_code)) next

    for (item in radiation_items) {
      if (item$col <= ncol(d)) {
        val_str <- trimws(as.character(d[r, item$col]))
        val_num <- suppressWarnings(as.numeric(val_str))
        if (is.na(val_num) && val_str == "-") val_num <- NA_real_
        radiation_sma[[length(radiation_sma) + 1]] <- data.frame(
          sma_code = sc, year = yr, item_id = item$id,
          value = val_num, stringsAsFactors = FALSE)
      }
    }
  }
}

radiation_sma_df <- if (length(radiation_sma) > 0) bind_rows(radiation_sma) else data.frame()
cat(sprintf("  SMA放射線治療: %d records (%d years)\n",
            nrow(radiation_sma_df), n_distinct(radiation_sma_df$year)))

# =============================================================================
# 8c. SCR (間接標準化算定比) 計算
# =============================================================================
cat("\n=== 8c. SCR計算 ===\n")

scr_df <- data.frame(procedure_code = character(), pref_code = character(),
                     fy_year = integer(), scr_value = numeric(),
                     expected_count = numeric(), stringsAsFactors = FALSE)

if (nrow(ndb_sexage_agg) > 0 && nrow(pop_sexage) > 0) {
  # National population by sex × age × year
  pop_national <- pop_sexage |>
    group_by(year, sex, age_group) |>
    summarise(pop_national = sum(population, na.rm = TRUE), .groups = "drop")

  proc_years <- ndb_sexage_agg |> distinct(procedure_code, fy_year)

  scr_rows <- list()
  for (k in seq_len(nrow(proc_years))) {
    proc <- proc_years$procedure_code[k]
    yr <- proc_years$fy_year[k]

    # National sex/age counts for this procedure × year
    n_sa <- ndb_sexage_agg |>
      filter(procedure_code == proc, fy_year == yr) |>
      select(sex, age_group, national_count)
    if (nrow(n_sa) == 0) next

    # National population for this year (use closest if exact year not available)
    p_nat <- pop_national |> filter(year == yr)
    if (nrow(p_nat) == 0) {
      avail_years <- sort(unique(pop_national$year))
      closest_yr <- avail_years[which.min(abs(avail_years - yr))]
      p_nat <- pop_national |> filter(year == closest_yr)
    }
    if (nrow(p_nat) == 0) next

    # National rates: N_J,sa / P_J,sa
    rates <- n_sa |>
      inner_join(p_nat, by = c("sex", "age_group")) |>
      mutate(rate = ifelse(pop_national > 0, national_count / pop_national, NA_real_)) |>
      filter(!is.na(rate))
    if (nrow(rates) == 0) next

    # Prefecture population for this year
    p_pref <- pop_sexage |> filter(year == yr)
    if (nrow(p_pref) == 0) {
      avail_years <- sort(unique(pop_sexage$year))
      closest_yr <- avail_years[which.min(abs(avail_years - yr))]
      p_pref <- pop_sexage |> filter(year == closest_yr)
    }

    for (pc in pref_codes) {
      p_pref_pc <- p_pref |> filter(pref_code == pc)
      if (nrow(p_pref_pc) == 0) next

      # E_p = Σ_sa (P_p,sa × rate_sa)
      ep_data <- rates |>
        inner_join(p_pref_pc |> select(sex, age_group, population),
                   by = c("sex", "age_group")) |>
        mutate(expected_component = population * rate)
      if (nrow(ep_data) == 0) next

      e_p <- sum(ep_data$expected_component, na.rm = TRUE)
      if (e_p <= 0) next

      # O_p from ndb_pref_agg
      o_p_row <- ndb_pref_agg |>
        filter(procedure_code == proc, pref_code == pc, fy_year == yr)
      if (nrow(o_p_row) == 0 || is.na(o_p_row$total_count[1])) next

      o_p <- o_p_row$total_count[1]
      scr_val <- (o_p / e_p) * 100

      scr_rows[[length(scr_rows) + 1]] <- data.frame(
        procedure_code = proc, pref_code = pc, fy_year = yr,
        scr_value = round(scr_val, 1), expected_count = round(e_p),
        stringsAsFactors = FALSE)
    }
  }

  scr_df <- if (length(scr_rows) > 0) bind_rows(scr_rows) else scr_df
}

cat(sprintf("  SCR計算: %d records (%d procs x %d prefs x %d years)\n",
            nrow(scr_df), n_distinct(scr_df$procedure_code),
            n_distinct(scr_df$pref_code), n_distinct(scr_df$fy_year)))

if (nrow(scr_df) > 0) {
  mean_scr <- mean(scr_df$scr_value, na.rm = TRUE)
  median_scr <- median(scr_df$scr_value, na.rm = TRUE)
  cat(sprintf("  SCR mean=%.1f, median=%.1f (should be near 100)\n", mean_scr, median_scr))

  sample_proc <- scr_df$procedure_code[1]
  sample_yr <- max(scr_df$fy_year[scr_df$procedure_code == sample_proc])
  sample <- scr_df |> filter(procedure_code == sample_proc, fy_year == sample_yr)
  cat(sprintf("  Sample (%s, %d): min=%.1f, max=%.1f, Tokyo=%s\n",
              sample_proc, sample_yr,
              min(sample$scr_value), max(sample$scr_value),
              if (any(sample$pref_code == "13"))
                sprintf("%.1f", sample$scr_value[sample$pref_code == "13"]) else "NA"))
}

# =============================================================================
# 9. JSON出力
# =============================================================================
cat("\n=== 9. JSON出力 ===\n")

# --- 9a. NDB階層構造 ---
code_list <- proc_meta |> distinct(class_code, class_name) |> arrange(class_code)
codes_hierarchy <- list()
for (i in seq_len(nrow(code_list))) {
  cc <- code_list$class_code[i]
  procs <- proc_meta |> filter(class_code == cc)
  proc_list <- lapply(seq_len(nrow(procs)), function(j) {
    list(id = procs$procedure_code[j], name = procs$procedure_name[j],
         points = if (is.na(procs$points[j])) NULL else procs$points[j])
  })
  codes_hierarchy[[length(codes_hierarchy) + 1]] <- list(
    code = cc, name = code_list$class_name[i], procedures = proc_list)
}

# --- 9b. NDB都道府県カウント ---
ndb_pref_counts <- list()
for (i in seq_len(nrow(ndb_pref_agg))) {
  proc <- ndb_pref_agg$procedure_code[i]
  pc <- ndb_pref_agg$pref_code[i]
  yr <- as.character(ndb_pref_agg$fy_year[i])
  val <- ndb_pref_agg$total_count[i]
  if (is.null(ndb_pref_counts[[proc]])) ndb_pref_counts[[proc]] <- list()
  if (is.null(ndb_pref_counts[[proc]][[pc]])) ndb_pref_counts[[proc]][[pc]] <- list()
  ndb_pref_counts[[proc]][[pc]][[yr]] <- if (is.na(val)) NA_real_ else val
}

# --- 9b-2. NDB国の総計(秘匿前の真の全国値; 全国合計表示・欠損レコード率算出用) ---
ndb_national_counts <- list()
for (i in seq_len(nrow(ndb_national_agg))) {
  proc <- ndb_national_agg$procedure_code[i]
  yr <- as.character(ndb_national_agg$fy_year[i])
  val <- ndb_national_agg$national_total[i]
  if (is.null(ndb_national_counts[[proc]])) ndb_national_counts[[proc]] <- list()
  ndb_national_counts[[proc]][[yr]] <- if (is.na(val)) NA_real_ else val
}

# --- 9c. NDB二次医療圏カウント ---
ndb_sma_counts <- list()
if (nrow(ndb_sma_agg) > 0) {
  for (i in seq_len(nrow(ndb_sma_agg))) {
    proc <- ndb_sma_agg$procedure_code[i]
    sc <- ndb_sma_agg$sma_code[i]
    yr <- as.character(ndb_sma_agg$fy_year[i])
    val <- ndb_sma_agg$total_count[i]
    if (is.null(ndb_sma_counts[[proc]])) ndb_sma_counts[[proc]] <- list()
    if (is.null(ndb_sma_counts[[proc]][[sc]])) ndb_sma_counts[[proc]][[sc]] <- list()
    ndb_sma_counts[[proc]][[sc]][[yr]] <- if (is.na(val)) NA_real_ else val
  }
}

# --- 9d. 人口（都道府県）---
pop_total_nested <- list()
for (i in seq_len(nrow(pop_total))) {
  pc <- pop_total$pref_code[i]
  yr <- as.character(pop_total$year[i])
  if (is.null(pop_total_nested[[pc]])) pop_total_nested[[pc]] <- list()
  pop_total_nested[[pc]][[yr]] <- pop_total$population[i]
}

pop_elderly_nested <- list()
for (i in seq_len(nrow(pop_elderly))) {
  pc <- pop_elderly$pref_code[i]
  yr <- as.character(pop_elderly$year[i])
  if (is.null(pop_elderly_nested[[pc]])) pop_elderly_nested[[pc]] <- list()
  pop_elderly_nested[[pc]][[yr]] <- pop_elderly$population_65plus[i]
}

# --- 9d-2. 人口（二次医療圏, A38-14/A38-20 線形補間 年別）---
pop_total_sma_nested <- list()
pop_elderly_sma_nested <- list()

for (i in seq_len(nrow(pop_sma_total))) {
  sc <- pop_sma_total$sma_code[i]
  yr <- as.character(pop_sma_total$year[i])
  pop_val <- pop_sma_total$population[i]
  if (is.null(pop_total_sma_nested[[sc]])) pop_total_sma_nested[[sc]] <- list()
  pop_total_sma_nested[[sc]][[yr]] <- pop_val
}
for (i in seq_len(nrow(pop_sma_elderly))) {
  sc <- pop_sma_elderly$sma_code[i]
  yr <- as.character(pop_sma_elderly$year[i])
  eld_val <- pop_sma_elderly$population_65plus[i]
  if (is.null(pop_elderly_sma_nested[[sc]])) pop_elderly_sma_nested[[sc]] <- list()
  pop_elderly_sma_nested[[sc]][[yr]] <- eld_val
}
cat(sprintf("  SMA人口JSON: total=%d regions, elderly=%d regions\n",
            length(pop_total_sma_nested), length(pop_elderly_sma_nested)))

# --- 9e. 病院数 ---
hospitals_pref_nested <- list()
for (i in seq_len(nrow(hospital_pref_df))) {
  pc <- hospital_pref_df$pref_code[i]
  yr <- as.character(hospital_pref_df$year[i])
  if (is.null(hospitals_pref_nested[[pc]])) hospitals_pref_nested[[pc]] <- list()
  hospitals_pref_nested[[pc]][[yr]] <- hospital_pref_df$hospitals[i]
}

hospitals_sma_nested <- list()
for (i in seq_len(nrow(hospital_sma_df))) {
  sc <- hospital_sma_df$sma_code[i]
  yr <- as.character(hospital_sma_df$year[i])
  if (is.null(hospitals_sma_nested[[sc]])) hospitals_sma_nested[[sc]] <- list()
  hospitals_sma_nested[[sc]][[yr]] <- hospital_sma_df$hospitals[i]
}

# --- 9f. 放射線治療設備 ---
radiation_nested <- list()
for (i in seq_len(nrow(radiation_pref_df))) {
  item <- radiation_pref_df$item_id[i]
  pc <- radiation_pref_df$pref_code[i]
  yr <- as.character(radiation_pref_df$year[i])
  val <- radiation_pref_df$value[i]
  if (is.null(radiation_nested[[item]])) radiation_nested[[item]] <- list()
  if (is.null(radiation_nested[[item]][[pc]])) radiation_nested[[item]][[pc]] <- list()
  radiation_nested[[item]][[pc]][[yr]] <- if (is.na(val)) NA_real_ else val
}

# --- 9g. 医師数 ---
physician_nested <- list()
for (i in seq_len(nrow(physician_pref_df))) {
  pc <- physician_pref_df$pref_code[i]
  yr <- as.character(physician_pref_df$year[i])
  if (is.null(physician_nested[[pc]])) physician_nested[[pc]] <- list()
  physician_nested[[pc]][[yr]] <- physician_pref_df$physicians[i]
}

# --- 9h. 二次医療圏マッピング ---
sma_regions <- list()
for (i in seq_len(nrow(sma_lookup))) {
  sc <- sma_lookup$sma_code[i]
  sma_regions[[sc]] <- list(name = sma_lookup$sma_name[i], pref = sma_lookup$pref_code[i])
}

# --- 9i. 放射線治療アイテム定義 ---
rt_items_list <- lapply(radiation_items, function(x) list(id = x$id, name = x$name))

# --- 9j. SMA放射線治療設備 ---
radiation_sma_nested <- list()
if (nrow(radiation_sma_df) > 0) {
  for (i in seq_len(nrow(radiation_sma_df))) {
    item <- radiation_sma_df$item_id[i]
    sc <- radiation_sma_df$sma_code[i]
    yr <- as.character(radiation_sma_df$year[i])
    val <- radiation_sma_df$value[i]
    if (is.null(radiation_sma_nested[[item]])) radiation_sma_nested[[item]] <- list()
    if (is.null(radiation_sma_nested[[item]][[sc]])) radiation_sma_nested[[item]][[sc]] <- list()
    radiation_sma_nested[[item]][[sc]][[yr]] <- if (is.na(val)) NA_real_ else val
  }
}

# --- 9k. 診療放射線技師・看護師 ---
staff_nested <- list()
if (nrow(staff_pref_df) > 0) {
  for (i in seq_len(nrow(staff_pref_df))) {
    item <- staff_pref_df$item_id[i]
    pc <- staff_pref_df$pref_code[i]
    yr <- as.character(staff_pref_df$year[i])
    val <- staff_pref_df$value[i]
    if (is.null(staff_nested[[item]])) staff_nested[[item]] <- list()
    if (is.null(staff_nested[[item]][[pc]])) staff_nested[[item]][[pc]] <- list()
    staff_nested[[item]][[pc]][[yr]] <- val
  }
}

# --- 9l. 放射線科医 ---
rad_doctor_pref_nested <- list()
for (i in seq_len(nrow(rad_doctor_pref_df))) {
  pc <- rad_doctor_pref_df$pref_code[i]
  yr <- as.character(rad_doctor_pref_df$year[i])
  if (is.null(rad_doctor_pref_nested[[pc]])) rad_doctor_pref_nested[[pc]] <- list()
  rad_doctor_pref_nested[[pc]][[yr]] <- rad_doctor_pref_df$rad_doctors[i]
}

rad_doctor_sma_nested <- list()
for (i in seq_len(nrow(rad_doctor_sma_df))) {
  sc <- rad_doctor_sma_df$sma_code[i]
  yr <- as.character(rad_doctor_sma_df$year[i])
  if (is.null(rad_doctor_sma_nested[[sc]])) rad_doctor_sma_nested[[sc]] <- list()
  rad_doctor_sma_nested[[sc]][[yr]] <- rad_doctor_sma_df$rad_doctors[i]
}

# --- 9m. SCR ---
scr_nested <- list()
if (nrow(scr_df) > 0) {
  for (i in seq_len(nrow(scr_df))) {
    proc <- scr_df$procedure_code[i]
    pc <- scr_df$pref_code[i]
    yr <- as.character(scr_df$fy_year[i])
    if (is.null(scr_nested[[proc]])) scr_nested[[proc]] <- list()
    if (is.null(scr_nested[[proc]][[pc]])) scr_nested[[proc]][[pc]] <- list()
    scr_nested[[proc]][[pc]][[yr]] <- list(
      scr = scr_df$scr_value[i],
      expected = scr_df$expected_count[i]
    )
  }
}
cat(sprintf("  SCR nested: %d procedures\n", length(scr_nested)))

# --- 組み立て ---
web_data <- list(
  ndb = list(
    codes = codes_hierarchy,
    years = 2014:2024,
    counts = list(pref = ndb_pref_counts, national = ndb_national_counts
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

json_path <- file.path(output_dir, "dashboard_data.json")
write(toJSON(web_data, auto_unbox = TRUE, pretty = FALSE, null = "null", na = "null"),
      json_path)
cat(sprintf("  JSON: %s (%s bytes)\n", json_path,
            format(file.size(json_path), big.mark = ",")))

# =============================================================================
# 10. GeoJSONコピー
# =============================================================================
cat("\n=== 10. GeoJSONコピー ===\n")

geo_files <- list(
  c(file.path(data_dir, "geo/prefectures.geojson"),
    file.path(output_dir, "prefectures.geojson"))
  # [v2.0-sma-disabled] 将来 SMA 表示を復活させる場合は次行のコメントを外す
  # , c(file.path(data_dir, "geo/sma.geojson"), file.path(output_dir, "sma.geojson"))
)

for (gf in geo_files) {
  if (file.exists(gf[1])) {
    file.copy(gf[1], gf[2], overwrite = TRUE)
    cat(sprintf("  %s → %s (%s bytes)\n", basename(gf[1]), gf[2],
                format(file.size(gf[2]), big.mark = ",")))
  } else {
    cat(sprintf("  WARNING: %s not found\n", gf[1]))
  }
}

cat("\n=== 完了 ===\n")
