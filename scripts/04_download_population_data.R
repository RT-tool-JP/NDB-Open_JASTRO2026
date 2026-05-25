################################################################################
# 04_download_population_data.R
# 人口推計データ ダウンロード (総人口 + 年齢階級別 → 65歳以上人口)
#
# データ元: 総務省統計局 人口推計（各年10月1日現在）
# e-Stat: https://www.e-stat.go.jp/ (toukei=00200524)
#
# 総人口: Table 7 (都道府県、男女別人口) - 複数年統合ファイル
# 高齢者人口: Table 10 (都道府県、年齢5歳階級別人口) - 各年個別ファイル
#   ※国勢調査年(2010,2015,2020)はTable 2形式
################################################################################

library(readxl)
library(dplyr)

data_dir <- file.path(getwd(), "rawdata_dl", "population")
dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)

estat_url <- function(stat_inf_id) {
  sprintf("https://www.e-stat.go.jp/stat-search/file-download?statInfId=%s&fileKind=0",
          stat_inf_id)
}

# =============================================================================
# 1. 総人口データ (既存方式: 複数年統合ファイル)
# =============================================================================
total_pop_files <- list(
  list(url = estat_url("000029026254"),
       dest = file.path(data_dir, "population_total_pref_2014.xls"),
       format = "xls", years = 2010:2014),
  list(url = estat_url("000031921674"),
       dest = file.path(data_dir, "population_total_pref_2019.xls"),
       format = "xls", years = 2015:2019),
  list(url = estat_url("000040166077"),
       dest = file.path(data_dir, "population_total_pref_2023.xlsx"),
       format = "xlsx", years = c(2015, 2020:2023))
)

# =============================================================================
# 2. 年齢階級別人口 (Table 10: 5歳階級 × 都道府県)
#    65歳以上 = 65-69 + 70-74 + 75-79 + 80-84 + 85歳以上 を合算
# =============================================================================
age_group_files <- list(
  list(year = 2014, id = "000029026259", format = "xls",  is_census = FALSE),
  list(year = 2015, id = "000031495550", format = "xls",  is_census = TRUE),  # 拡張子と実形式の不整合修正
  list(year = 2016, id = "000031560319", format = "xls",  is_census = FALSE),
  list(year = 2017, id = "000031690323", format = "xls",  is_census = FALSE),
  list(year = 2018, id = "000031807147", format = "xls",  is_census = FALSE),
  list(year = 2019, id = "000031921679", format = "xls",  is_census = FALSE),
  list(year = 2020, id = "000032153670", format = "xlsx", is_census = TRUE),
  list(year = 2021, id = "000032191051", format = "xlsx", is_census = FALSE),  # 拡張子と実形式の不整合修正
  list(year = 2022, id = "000040045496", format = "xlsx", is_census = FALSE),
  list(year = 2023, id = "000040166082", format = "xlsx", is_census = FALSE)
)

# =============================================================================
# ダウンロード実行
# =============================================================================
cat("=== 人口推計データ ダウンロード ===\n\n")

# --- 総人口ファイル ---
cat("--- 総人口 (都道府県別) ---\n")
for (pf in total_pop_files) {
  if (file.exists(pf$dest)) {
    cat(sprintf("  %s => skip\n", basename(pf$dest)))
    next
  }
  cat(sprintf("  %s => downloading...", basename(pf$dest)))
  tryCatch({
    download.file(pf$url, pf$dest, mode = "wb", quiet = TRUE)
    cat(sprintf(" OK (%s bytes)\n", format(file.size(pf$dest), big.mark = ",")))
  }, error = function(e) cat(sprintf(" ERROR: %s\n", e$message)))
  Sys.sleep(1)
}

# --- 年齢階級別ファイル ---
cat("\n--- 年齢階級別人口 (都道府県別・5歳階級) ---\n")
for (af in age_group_files) {
  fname <- sprintf("population_age5_pref_%d.%s", af$year, af$format)
  dest <- file.path(data_dir, fname)

  if (file.exists(dest)) {
    cat(sprintf("  [%d] %s => skip\n", af$year, fname))
    next
  }

  cat(sprintf("  [%d] %s => downloading...", af$year, fname))
  tryCatch({
    download.file(estat_url(af$id), dest, mode = "wb", quiet = TRUE)
    cat(sprintf(" OK (%s bytes)\n", format(file.size(dest), big.mark = ",")))
  }, error = function(e) cat(sprintf(" ERROR: %s\n", e$message)))
  Sys.sleep(1)
}

# =============================================================================
# パース: 総人口
# =============================================================================
cat("\n=== 総人口データのパース ===\n")

# --- 旧形式(.xls) ---
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

# --- 新形式(.xlsx) ---
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

pop_all <- list()
pop_2014 <- parse_pop_xls(total_pop_files[[1]]$dest, 2010:2014)
pop_all[[1]] <- pop_2014 |> filter(year == 2014)
pop_2019 <- parse_pop_xls(total_pop_files[[2]]$dest, 2015:2019)
pop_all[[2]] <- pop_2019
pop_2023 <- parse_pop_xlsx(total_pop_files[[3]]$dest, c(2015, 2020:2023))
pop_all[[3]] <- pop_2023 |> filter(year >= 2020)

pop_total <- bind_rows(pop_all) |>
  mutate(population = population_1000 * 1000) |>
  select(pref_code, year, population) |>
  arrange(year, pref_code)

cat(sprintf("総人口: %d records (%d prefectures x %d years)\n",
            nrow(pop_total), n_distinct(pop_total$pref_code), n_distinct(pop_total$year)))

# =============================================================================
# パース: 年齢階級別 → 65歳以上人口の抽出
# =============================================================================
cat("\n=== 年齢階級別人口のパース (65歳以上抽出) ===\n")

# 各ファイルの構造を調査して65歳以上を抽出
parse_age_group_file <- function(file_path, year, format, is_census) {
  df <- read_excel(file_path, sheet = 1, col_names = FALSE, col_types = "text")

  cat(sprintf("  [%d] %d rows x %d cols ...", year, nrow(df), ncol(df)))

  # ファイル構造を探索: 都道府県ごとの65歳以上人口を抽出
  # 戦略: 「65」を含む行または列を探し、都道府県コードと紐づける
  # 構造は年ごとに異なるため、柔軟にパースする

  result <- tryCatch({
    # まず全データをテキストとして読み、構造を判定
    # 一般的なTable 10の構造:
    # - ヘッダ行に年齢階級名 (「0〜4歳」「5〜9歳」...「85歳以上」)
    # - 行方向に都道府県 (01-47)
    # - 値は千人単位

    # ヘッダ行を探す: 「0〜4」「0～4」「0-4」を含む行
    header_candidates <- which(sapply(1:min(30, nrow(df)), function(r) {
      any(grepl("0.{0,2}4", as.character(df[r, ]), perl = TRUE), na.rm = TRUE)
    }))

    if (length(header_candidates) == 0) {
      cat(" (header not found, skipping)\n")
      return(NULL)
    }

    # 65歳以上の列を特定
    header_row <- header_candidates[1]
    header_vals <- as.character(df[header_row, ])

    # 65歳以上に該当する列インデックスを検出
    elderly_cols <- which(grepl("(65|70|75|80|85)", header_vals))

    if (length(elderly_cols) == 0) {
      cat(" (age 65+ columns not found)\n")
      return(NULL)
    }

    cat(sprintf(" header_row=%d, elderly_cols=%s", header_row, paste(elderly_cols, collapse=",")))

    # データ行を処理: 都道府県コードを含む行を探す
    pref_data <- list()
    for (r in (header_row + 1):min(nrow(df), header_row + 200)) {
      # 都道府県コード(2桁数字)を探す
      row_vals <- as.character(df[r, ])
      pref_code <- NA_character_

      # 各列を確認: 01-47の2桁コードを探す
      for (c in 1:min(15, ncol(df))) {
        v <- trimws(as.character(df[[c]][r]))
        if (!is.na(v) && grepl("^0[1-9]$|^[1-3][0-9]$|^4[0-7]$", v)) {
          pref_code <- v
          break
        }
        # 5桁コード (01000-47000)
        if (!is.na(v) && grepl("^(0[1-9]|[1-3][0-9]|4[0-7])000$", v)) {
          pref_code <- sprintf("%02d", as.integer(v) / 1000)
          break
        }
      }

      if (!is.na(pref_code)) {
        # 65歳以上各列の値を合算
        elderly_total <- 0
        all_na <- TRUE
        for (ec in elderly_cols) {
          val <- suppressWarnings(as.numeric(as.character(df[[ec]][r])))
          if (!is.na(val)) {
            elderly_total <- elderly_total + val
            all_na <- FALSE
          }
        }
        if (!all_na) {
          pref_data[[length(pref_data) + 1]] <- data.frame(
            pref_code = pref_code, year = year,
            elderly_pop_1000 = elderly_total,
            stringsAsFactors = FALSE)
        }
      }
    }

    if (length(pref_data) == 0) {
      cat(" (no prefecture data found)\n")
      return(NULL)
    }

    out <- bind_rows(pref_data)
    # 総人口ブロック（男女計）のみ取得: 最初の47件
    if (nrow(out) > 47) {
      out <- out[1:47, ]
    }
    cat(sprintf(" => %d prefectures\n", nrow(out)))
    out
  }, error = function(e) {
    cat(sprintf(" ERROR: %s\n", e$message))
    NULL
  })

  result
}

elderly_all <- list()
for (af in age_group_files) {
  fname <- sprintf("population_age5_pref_%d.%s", af$year, af$format)
  fpath <- file.path(data_dir, fname)
  if (!file.exists(fpath)) {
    cat(sprintf("  [%d] file not found, skipping\n", af$year))
    next
  }
  result <- parse_age_group_file(fpath, af$year, af$format, af$is_census)
  if (!is.null(result) && nrow(result) > 0) {
    elderly_all[[length(elderly_all) + 1]] <- result
  }
}

if (length(elderly_all) > 0) {
  pop_elderly <- bind_rows(elderly_all) |>
    mutate(population_65plus = elderly_pop_1000 * 1000) |>
    select(pref_code, year, population_65plus) |>
    arrange(year, pref_code)

  cat(sprintf("\n高齢者人口: %d records (%d prefectures x %d years)\n",
              nrow(pop_elderly), n_distinct(pop_elderly$pref_code),
              n_distinct(pop_elderly$year)))
} else {
  pop_elderly <- data.frame(pref_code = character(), year = integer(),
                             population_65plus = numeric())
  cat("\nWARNING: 高齢者人口データのパースに失敗しました\n")
}

# =============================================================================
# CSV出力
# =============================================================================
cat("\n=== CSV出力 ===\n")

write.csv(pop_total, file.path(data_dir, "population_total_pref.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")
cat(sprintf("  population_total_pref.csv (%d rows)\n", nrow(pop_total)))

write.csv(pop_elderly, file.path(data_dir, "population_elderly_pref.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")
cat(sprintf("  population_elderly_pref.csv (%d rows)\n", nrow(pop_elderly)))

cat("\n=== 人口推計 ダウンロード・パース完了 ===\n")
