################################################################################
# 02_analyze_M_radiation.R
# NDB Open Data M放射線治療 都道府県別算定回数 集計・分析
#
# 目的: M001 体外照射（および任意の分類コード）の都道府県別算定回数を
#       年度横断的に集計・可視化する
#
# 注意:
#   - NDB Open Data上の分類コード体系:
#     M000  = 放射線治療管理料
#     M000-2 = 放射性同位元素内用療法管理料
#     M001  = 体外照射
#     M001-2 = ガンマナイフによる定位放射線治療
#     M001-3 = 直線加速器による放射線治療
#     M001-4 = 粒子線治療
#     M003  = 電磁波温熱療法
#     M004  = 密封小線源治療
#     M005  = 血液照射
#
#   - 10未満の値は "‐"（全角ダッシュ）で秘匿されている
#   - 各xlsxには「外来」「入院」等のシートがある
################################################################################

library(readxl)
library(dplyr)
library(tidyr)
library(stringr)
library(ggplot2)

# =============================================================================
# 設定
# =============================================================================

# 分析対象の分類コード（変更可能）
TARGET_CODE <- "M001"   # 体外照射
# TARGET_CODE <- "M000" # 放射線治療管理料 に変更する場合はこちら

# データディレクトリ
data_dir <- here::here("rawdata", "M_radiation_pref")

# 出力ディレクトリ
output_dir <- here::here("output")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# NDB各回のメタ情報
ndb_meta <- data.frame(
  edition  = 1:10,
  fy_label = c("H26(2014)", "H27(2015)", "H28(2016)", "H29(2017)", "H30(2018)",
               "R01(2019)", "R02(2020)", "R03(2021)", "R04(2022)", "R05(2023)"),
  fy_year  = 2014:2023,
  stringsAsFactors = FALSE
)

# 都道府県コード・名称
pref_codes <- sprintf("%02d", 1:47)
pref_names <- c(
  "北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県",
  "茨城県", "栃木県", "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県",
  "新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県",
  "岐阜県", "静岡県", "愛知県", "三重県", "滋賀県", "京都府", "大阪府",
  "兵庫県", "奈良県", "和歌山県", "鳥取県", "島根県", "岡山県",
  "広島県", "山口県", "徳島県", "香川県", "愛媛県", "高知県",
  "福岡県", "佐賀県", "長崎県", "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県"
)
pref_df <- data.frame(pref_code = pref_codes, pref_name = pref_names,
                       stringsAsFactors = FALSE)

# =============================================================================
# 1. XLSXファイル読み込み・パース関数
# =============================================================================

#' NDB M放射線治療 都道府県別 xlsxの1シートをパースする
#'
#' @param file_path xlsxファイルパス
#' @param sheet_name シート名 (e.g., "外来", "入院")
#' @return data.frame (long format)
parse_ndb_sheet <- function(file_path, sheet_name) {
  # ヘッダーなしで読み込み
  raw <- tryCatch(
    read_excel(file_path, sheet = sheet_name, col_names = FALSE,
               col_types = "text"),
    error = function(e) {
      message(sprintf("  シート '%s' の読み込みに失敗: %s", sheet_name, e$message))
      return(NULL)
    }
  )
  if (is.null(raw) || nrow(raw) < 5) return(NULL)

  # 列数の確認（基本53列: 6メタ列 + 47都道府県）
  ncols <- ncol(raw)

  # ヘッダー行を特定（「分類」を含む行）
  header_row <- which(grepl("分類", raw[[1]], fixed = TRUE))
  if (length(header_row) == 0) return(NULL)
  header_row <- header_row[1]

  # データ開始行（ヘッダー行の2行後: ヘッダー行 + 都道府県名行 + データ開始）
  data_start <- header_row + 2

  if (data_start > nrow(raw)) return(NULL)

  # データ部分を抽出
  dat <- raw[data_start:nrow(raw), ]

  # 列名設定
  # 列1: 分類コード, 列2: 分類名称, 列3: 診療行為コード, 列4: 診療行為名称
  # 列5: 点数, 列6: 総計, 列7-53: 都道府県(01-47)
  meta_cols <- min(6, ncols)
  pref_start <- meta_cols + 1
  pref_end   <- min(ncols, meta_cols + 47)

  colnames(dat)[1:meta_cols] <- c("class_code", "class_name",
                                   "procedure_code", "procedure_name",
                                   "points", "total")[1:meta_cols]
  if (pref_end >= pref_start) {
    colnames(dat)[pref_start:pref_end] <- sprintf("pref_%02d", 1:(pref_end - pref_start + 1))
  }

  # 分類コードの前方補完（グループ内でNAになっている行を埋める）
  dat$class_code <- zoo::na.locf(
    ifelse(dat$class_code == "" | is.na(dat$class_code), NA, dat$class_code),
    na.rm = FALSE
  )
  dat$class_name <- zoo::na.locf(
    ifelse(dat$class_name == "" | is.na(dat$class_name), NA, dat$class_name),
    na.rm = FALSE
  )

  # long format に変換
  pref_cols <- colnames(dat)[grepl("^pref_", colnames(dat))]

  dat_long <- dat |>
    select(class_code, class_name, procedure_code, procedure_name,
           points, total, all_of(pref_cols)) |>
    pivot_longer(
      cols = all_of(pref_cols),
      names_to = "pref_col",
      values_to = "count_raw"
    ) |>
    mutate(
      pref_code = str_extract(pref_col, "\\d+"),
      sheet = sheet_name
    )

  return(dat_long)
}

#' 1つのNDB xlsxファイルを全シート読み込んでパース
#'
#' @param file_path xlsxファイルパス
#' @param edition NDB回次
#' @param fy_year 年度
#' @return data.frame (long format)
parse_ndb_file <- function(file_path, edition, fy_year) {
  sheets <- excel_sheets(file_path)
  # 「外来」「入院」シートのみ対象（加算シートは除外）
  target_sheets <- sheets[sheets %in% c("外来", "入院")]

  all_data <- lapply(target_sheets, function(s) {
    parse_ndb_sheet(file_path, s)
  })

  result <- bind_rows(all_data)
  if (nrow(result) == 0) return(NULL)

  result$edition <- edition
  result$fy_year <- fy_year

  return(result)
}

# =============================================================================
# 2. 全年度データの読み込み
# =============================================================================

cat("=== NDB M放射線治療 都道府県別算定回数データの読み込み ===\n\n")

all_data <- list()

for (i in seq_len(nrow(ndb_meta))) {
  fname <- sprintf("ndb%02d_M_radiation_pref_%d.xlsx",
                    ndb_meta$edition[i], ndb_meta$fy_year[i])
  fpath <- file.path(data_dir, fname)

  if (!file.exists(fpath)) {
    cat(sprintf("[%2d] %s => ファイルが見つかりません。01_download_ndb_data.R を実行してください。\n",
                ndb_meta$edition[i], fname))
    next
  }

  cat(sprintf("[%2d] %s (%s) => 読み込み中...",
              ndb_meta$edition[i], fname, ndb_meta$fy_label[i]))

  dat <- tryCatch(
    parse_ndb_file(fpath, ndb_meta$edition[i], ndb_meta$fy_year[i]),
    error = function(e) {
      cat(sprintf(" ERROR: %s\n", e$message))
      return(NULL)
    }
  )

  if (!is.null(dat) && nrow(dat) > 0) {
    all_data[[length(all_data) + 1]] <- dat
    cat(sprintf(" OK (%d rows)\n", nrow(dat)))
  } else {
    cat(" (データなし)\n")
  }
}

# 全年度結合
ndb_all <- bind_rows(all_data)
cat(sprintf("\n全データ: %d 行\n", nrow(ndb_all)))

# =============================================================================
# 3. データクリーニング
# =============================================================================

cat("\n=== データクリーニング ===\n")

ndb_clean <- ndb_all |>
  mutate(
    # "‐"（全角ダッシュ）や "-"（半角ハイフン）を NA に変換
    count = case_when(
      count_raw %in% c("-", "‐", "－", "―") ~ NA_real_,
      count_raw == "" | is.na(count_raw)     ~ NA_real_,
      TRUE ~ suppressWarnings(as.numeric(count_raw))
    ),
    total_num = case_when(
      total %in% c("-", "‐", "－", "―") ~ NA_real_,
      total == "" | is.na(total)         ~ NA_real_,
      TRUE ~ suppressWarnings(as.numeric(total))
    ),
    points_num = suppressWarnings(as.numeric(points))
  )

# 都道府県名を付与
ndb_clean <- ndb_clean |>
  left_join(pref_df, by = "pref_code")

cat(sprintf("クリーニング後: %d 行\n", nrow(ndb_clean)))

# =============================================================================
# 4. 対象分類コードの集計
# =============================================================================

cat(sprintf("\n=== 分類コード '%s' の集計 ===\n", TARGET_CODE))

# 利用可能な分類コード一覧を表示
cat("\n--- 全分類コード一覧 ---\n")
code_summary <- ndb_clean |>
  distinct(class_code, class_name) |>
  arrange(class_code)
print(code_summary, n = 30)

# 対象コードでフィルタ
target_data <- ndb_clean |>
  filter(class_code == TARGET_CODE)

if (nrow(target_data) == 0) {
  stop(sprintf("分類コード '%s' のデータが見つかりません。", TARGET_CODE))
}

cat(sprintf("\n対象データ: %d 行\n", nrow(target_data)))
cat(sprintf("分類名称: %s\n", unique(target_data$class_name)[1]))

# --- 4a. 都道府県別 × 年度別 合計算定回数 ---
pref_year_summary <- target_data |>
  group_by(fy_year, pref_code, pref_name, sheet) |>
  summarise(
    total_count  = sum(count, na.rm = TRUE),
    n_procedures = n_distinct(procedure_code),
    n_suppressed = sum(is.na(count)),
    .groups = "drop"
  )

# 外来・入院合算
pref_year_total <- pref_year_summary |>
  group_by(fy_year, pref_code, pref_name) |>
  summarise(
    total_count  = sum(total_count, na.rm = TRUE),
    n_procedures = max(n_procedures),
    .groups = "drop"
  )

cat("\n--- 都道府県別 × 年度別 合計算定回数（外来+入院） ---\n")

# ワイド形式に変換して表示
pref_year_wide <- pref_year_total |>
  select(fy_year, pref_name, total_count) |>
  pivot_wider(names_from = fy_year, values_from = total_count) |>
  arrange(match(pref_name, pref_names))

print(pref_year_wide, n = 50)

# --- 4b. 外来/入院別 都道府県サマリー ---
cat("\n--- 外来/入院別 全年度合計 上位10都道府県 ---\n")
sheet_pref_summary <- target_data |>
  group_by(sheet, pref_code, pref_name) |>
  summarise(total_count = sum(count, na.rm = TRUE), .groups = "drop") |>
  arrange(sheet, desc(total_count))

for (s in unique(sheet_pref_summary$sheet)) {
  cat(sprintf("\n[%s]\n", s))
  print(
    sheet_pref_summary |>
      filter(sheet == s) |>
      head(10) |>
      as.data.frame(),
    row.names = FALSE
  )
}

# --- 4c. 診療行為別の内訳 ---
cat("\n--- 診療行為別 全国合計 ---\n")
procedure_summary <- target_data |>
  group_by(procedure_code, procedure_name, points_num) |>
  summarise(
    total_count  = sum(count, na.rm = TRUE),
    n_years      = n_distinct(fy_year),
    .groups = "drop"
  ) |>
  arrange(desc(total_count))

print(procedure_summary, n = 30)

# =============================================================================
# 5. 可視化
# =============================================================================

cat("\n=== グラフ作成 ===\n")

class_name_short <- unique(target_data$class_name)[1]

# --- 5a. 年度別 全国合計推移 ---
year_total <- target_data |>
  group_by(fy_year, sheet) |>
  summarise(total_count = sum(count, na.rm = TRUE), .groups = "drop")

g1 <- ggplot(year_total, aes(x = fy_year, y = total_count, fill = sheet)) +
  geom_col(position = "stack") +
  scale_x_continuous(breaks = 2014:2023) +
  scale_y_continuous(labels = scales::comma) +
  labs(
    title = sprintf("NDB Open Data: %s(%s) 年度別算定回数推移",
                     TARGET_CODE, class_name_short),
    x = "年度", y = "算定回数", fill = "区分"
  ) +
  theme_minimal(base_family = "HiraginoSans-W3") +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

ggsave(file.path(output_dir, sprintf("%s_yearly_trend.png", TARGET_CODE)),
       g1, width = 10, height = 6, dpi = 150)
cat("  年度別推移グラフ: output/", sprintf("%s_yearly_trend.png\n", TARGET_CODE))

# --- 5b. 都道府県別 最新年度 ---
latest_year <- max(target_data$fy_year)
pref_latest <- target_data |>
  filter(fy_year == latest_year) |>
  group_by(pref_code, pref_name) |>
  summarise(total_count = sum(count, na.rm = TRUE), .groups = "drop") |>
  mutate(pref_name = factor(pref_name, levels = rev(pref_names)))

g2 <- ggplot(pref_latest, aes(x = pref_name, y = total_count)) +
  geom_col(fill = "steelblue") +
  coord_flip() +
  scale_y_continuous(labels = scales::comma) +
  labs(
    title = sprintf("NDB Open Data: %s(%s) 都道府県別算定回数 (%d年度)",
                     TARGET_CODE, class_name_short, latest_year),
    x = NULL, y = "算定回数（外来+入院）"
  ) +
  theme_minimal(base_family = "HiraginoSans-W3") +
  theme(axis.text.y = element_text(size = 7))

ggsave(file.path(output_dir, sprintf("%s_pref_%d.png", TARGET_CODE, latest_year)),
       g2, width = 10, height = 12, dpi = 150)
cat("  都道府県別グラフ: output/",
    sprintf("%s_pref_%d.png\n", TARGET_CODE, latest_year))

# --- 5c. 上位10都道府県の年度推移 ---
top10_prefs <- pref_year_total |>
  group_by(pref_code, pref_name) |>
  summarise(total_all = sum(total_count, na.rm = TRUE), .groups = "drop") |>
  slice_max(total_all, n = 10) |>
  pull(pref_name)

pref_trend_top10 <- pref_year_total |>
  filter(pref_name %in% top10_prefs)

g3 <- ggplot(pref_trend_top10,
             aes(x = fy_year, y = total_count, color = pref_name)) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 1.5) +
  scale_x_continuous(breaks = 2014:2023) +
  scale_y_continuous(labels = scales::comma) +
  labs(
    title = sprintf("NDB Open Data: %s(%s) 上位10都道府県の年度推移",
                     TARGET_CODE, class_name_short),
    x = "年度", y = "算定回数（外来+入院）", color = "都道府県"
  ) +
  theme_minimal(base_family = "HiraginoSans-W3") +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

ggsave(file.path(output_dir, sprintf("%s_top10_trend.png", TARGET_CODE)),
       g3, width = 12, height = 6, dpi = 150)
cat("  上位10都道府県推移: output/",
    sprintf("%s_top10_trend.png\n", TARGET_CODE))

# =============================================================================
# 6. 結果をCSVに保存
# =============================================================================

cat("\n=== CSV出力 ===\n")

# 都道府県 × 年度 ワイド形式
write.csv(pref_year_wide,
          file.path(output_dir, sprintf("%s_pref_year_wide.csv", TARGET_CODE)),
          row.names = FALSE, fileEncoding = "UTF-8")
cat("  ", sprintf("%s_pref_year_wide.csv\n", TARGET_CODE))

# ロング形式（全詳細）
detail_output <- target_data |>
  select(edition, fy_year, sheet, class_code, class_name,
         procedure_code, procedure_name, points_num,
         pref_code, pref_name, count) |>
  arrange(fy_year, sheet, procedure_code, pref_code)

write.csv(detail_output,
          file.path(output_dir, sprintf("%s_detail.csv", TARGET_CODE)),
          row.names = FALSE, fileEncoding = "UTF-8")
cat("  ", sprintf("%s_detail.csv\n", TARGET_CODE))

cat("\n=== 処理完了 ===\n")
