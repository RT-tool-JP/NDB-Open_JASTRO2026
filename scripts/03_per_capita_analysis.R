################################################################################
# 03_per_capita_analysis.R
# NDB Open Data M放射線治療 × 人口推計 → 人口あたり算定回数の分析
#
# 人口データ元: 総務省統計局 人口推計（各年10月1日現在）
# https://www.stat.go.jp/data/jinsui/2.html
# e-Stat: https://www.e-stat.go.jp/
#
# NDB Open Data: 厚生労働省
# https://www.mhlw.go.jp/stf/seisakunitsuite/bunya/0000177182.html
################################################################################

library(readxl)
library(dplyr)
library(tidyr)
library(stringr)
library(ggplot2)

# =============================================================================
# 設定
# =============================================================================

TARGET_CODE <- "M001"  # 体外照射
# TARGET_CODE <- "M000"  # 放射線治療管理料 に変更可能

data_dir   <- here::here("rawdata")
output_dir <- here::here("output")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

pref_names <- c(
  "北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県",
  "茨城県", "栃木県", "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県",
  "新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県",
  "岐阜県", "静岡県", "愛知県", "三重県", "滋賀県", "京都府", "大阪府",
  "兵庫県", "奈良県", "和歌山県", "鳥取県", "島根県", "岡山県",
  "広島県", "山口県", "徳島県", "香川県", "愛媛県", "高知県",
  "福岡県", "佐賀県", "長崎県", "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県"
)

# =============================================================================
# 1. 人口推計データのダウンロード・読み込み
# =============================================================================

cat("=== 人口推計データの取得 ===\n\n")

# --- 1a. ダウンロード ---
pop_files <- list(
  # 2014年ファイル: 2010-2014 (statInfId=000029026254, .xls形式)
  list(url = "https://www.e-stat.go.jp/stat-search/file-download?statInfId=000029026254&fileKind=0",
       dest = file.path(data_dir, "population_pref_2014.xls"),
       format = "xls", years = 2010:2014),
  # 2019年ファイル: 2015-2019 (statInfId=000031921674, .xls形式)
  list(url = "https://www.e-stat.go.jp/stat-search/file-download?statInfId=000031921674&fileKind=0",
       dest = file.path(data_dir, "population_pref_2019.xls"),
       format = "xls", years = 2015:2019),
  # 2023年ファイル: 2015,2020-2023 (statInfId=000040166077, .xlsx形式)
  list(url = "https://www.e-stat.go.jp/stat-search/file-download?statInfId=000040166077&fileKind=0",
       dest = file.path(data_dir, "population_pref_2023.xlsx"),
       format = "xlsx", years = c(2015, 2020:2023))
)

for (pf in pop_files) {
  if (!file.exists(pf$dest)) {
    cat(sprintf("ダウンロード中: %s ...", basename(pf$dest)))
    tryCatch({
      download.file(pf$url, pf$dest, mode = "wb", quiet = TRUE)
      cat(" OK\n")
    }, error = function(e) cat(sprintf(" ERROR: %s\n", e$message)))
    Sys.sleep(1)
  } else {
    cat(sprintf("既存: %s\n", basename(pf$dest)))
  }
}

# --- 1b. 旧形式(.xls) パース関数 ---
# 構造: 最初のブロック(行20-66) = 総人口・男女計の47都道府県
# col 9 = 都道府県番号(01-47), cols 13-17 = 年度データ (千人)
parse_pop_xls <- function(file_path, target_years) {
  df <- read_excel(file_path, sheet = 1, col_names = FALSE, col_types = "text")

  result <- list()
  year_cols <- 13:17
  found_count <- 0

  for (i in 20:nrow(df)) {
    pref_num <- as.character(df[[9]][i])
    if (!is.na(pref_num) && grepl("^[0-4][0-9]$", pref_num)) {
      # 最初の47件のみ取得（総人口・男女計ブロック）
      found_count <- found_count + 1
      if (found_count > 47) break

      pref_code <- pref_num
      for (j in seq_along(year_cols)) {
        if (j <= length(target_years)) {
          pop_val <- suppressWarnings(as.numeric(as.character(df[[year_cols[j]]][i])))
          if (!is.na(pop_val)) {
            result[[length(result) + 1]] <- data.frame(
              pref_code = pref_code,
              year = target_years[j],
              population_1000 = pop_val,
              stringsAsFactors = FALSE
            )
          }
        }
      }
    }
  }

  bind_rows(result)
}

# --- 1c. 新形式(.xlsx) パース関数 ---
# 構造: row 7 = ヘッダー, row 8+ = データ
# col 10 = 都道府県コード, col 11 = 地域名, cols 14-18 = 年度データ (千人)
parse_pop_xlsx <- function(file_path, target_years) {
  df <- read_excel(file_path, sheet = 1, col_names = FALSE, col_types = "text")

  result <- list()
  year_cols <- 14:18

  for (i in 8:nrow(df)) {
    pref_code_raw <- as.character(df[[10]][i])
    pop_type <- as.character(df[[8]][i])
    sex      <- as.character(df[[9]][i])

    if (!is.na(pref_code_raw) && grepl("^\\d{5}$", pref_code_raw) &&
        pref_code_raw != "00000") {
      # 総人口 + 男女計 の行のみ
      if (!is.na(pop_type) && grepl("総人口", pop_type) &&
          !is.na(sex) && grepl("男女計", sex)) {
        pref_code <- sprintf("%02d", as.integer(pref_code_raw) / 1000)
        for (j in seq_along(year_cols)) {
          if (j <= length(target_years)) {
            pop_val <- suppressWarnings(as.numeric(as.character(df[[year_cols[j]]][i])))
            if (!is.na(pop_val)) {
              result[[length(result) + 1]] <- data.frame(
                pref_code = pref_code,
                year = target_years[j],
                population_1000 = pop_val,
                stringsAsFactors = FALSE
              )
            }
          }
        }
      }
    }
  }

  bind_rows(result)
}

# --- 1d. 全ファイルからパース ---
cat("\n人口データのパース中...\n")

pop_all <- list()

# 2014 file -> 2014 only
pop_2014 <- parse_pop_xls(pop_files[[1]]$dest, 2010:2014)
pop_all[[1]] <- pop_2014 |> filter(year == 2014)
cat(sprintf("  2014: %d prefectures\n", nrow(pop_all[[1]])))

# 2019 file -> 2015-2019
pop_2019 <- parse_pop_xls(pop_files[[2]]$dest, 2015:2019)
pop_all[[2]] <- pop_2019
cat(sprintf("  2015-2019: %d records\n", nrow(pop_all[[2]])))

# 2023 file -> 2020-2023 only (skip 2015 which is already in 2019 file)
pop_2023 <- parse_pop_xlsx(pop_files[[3]]$dest, c(2015, 2020:2023))
pop_all[[3]] <- pop_2023 |> filter(year >= 2020)
cat(sprintf("  2020-2023: %d records\n", nrow(pop_all[[3]])))

pop_combined <- bind_rows(pop_all) |>
  mutate(population = population_1000 * 1000) |>
  arrange(year, pref_code)

cat(sprintf("\n人口データ合計: %d records (%d prefectures × %d years)\n",
            nrow(pop_combined),
            n_distinct(pop_combined$pref_code),
            n_distinct(pop_combined$year)))

# 確認: 各年度の都道府県数
pop_check <- pop_combined |>
  group_by(year) |>
  summarise(n_pref = n(), .groups = "drop")
print(pop_check)

# =============================================================================
# 2. NDB集計データの読み込み（02_analyze_M_radiation.R の出力を利用）
# =============================================================================

cat("\n=== NDBデータの読み込み ===\n")

ndb_csv <- file.path(output_dir, sprintf("%s_pref_year_wide.csv", TARGET_CODE))
if (!file.exists(ndb_csv)) {
  stop("NDB集計データが見つかりません。先に 02_analyze_M_radiation.R を実行してください。")
}

ndb_wide <- read.csv(ndb_csv, stringsAsFactors = FALSE, fileEncoding = "UTF-8")
cat(sprintf("NDBデータ: %d prefectures × %d years\n", nrow(ndb_wide), ncol(ndb_wide) - 1))

# long format に変換
ndb_long <- ndb_wide |>
  pivot_longer(
    cols = starts_with("X"),
    names_to = "year_col",
    values_to = "total_count"
  ) |>
  mutate(
    year = as.integer(gsub("X", "", year_col)),
    pref_code = sprintf("%02d", match(pref_name, pref_names))
  ) |>
  select(pref_code, pref_name, year, total_count)

# =============================================================================
# 3. NDB × 人口推計 の結合 → 人口あたり算定回数
# =============================================================================

cat("\n=== 人口あたり算定回数の算出 ===\n")

merged <- ndb_long |>
  inner_join(pop_combined |> select(pref_code, year, population),
             by = c("pref_code", "year"))

# 人口10万人あたり算定回数
merged <- merged |>
  mutate(
    count_per_100k = total_count / population * 100000
  )

cat(sprintf("結合データ: %d records\n", nrow(merged)))

# --- 3a. 都道府県 × 年度 ワイド表示 ---
cat("\n--- 人口10万人あたり算定回数 (都道府県 × 年度) ---\n")

percapita_wide <- merged |>
  select(pref_name, year, count_per_100k) |>
  mutate(count_per_100k = round(count_per_100k, 1)) |>
  pivot_wider(names_from = year, values_from = count_per_100k) |>
  mutate(pref_name = factor(pref_name, levels = pref_names)) |>
  arrange(pref_name)

print(percapita_wide, n = 50)

# --- 3b. 最新年度のランキング ---
latest_year <- max(merged$year)
cat(sprintf("\n--- %d年度 人口10万人あたり算定回数 ランキング ---\n", latest_year))

ranking <- merged |>
  filter(year == latest_year) |>
  arrange(desc(count_per_100k)) |>
  mutate(rank = row_number()) |>
  select(rank, pref_name, total_count, population, count_per_100k)

print(as.data.frame(ranking), row.names = FALSE)

# --- 3c. 全国平均との比較 ---
cat("\n--- 年度別 全国平均（人口10万人あたり） ---\n")

national_avg <- merged |>
  group_by(year) |>
  summarise(
    total_count_all = sum(total_count, na.rm = TRUE),
    population_all  = sum(population, na.rm = TRUE),
    avg_per_100k    = total_count_all / population_all * 100000,
    .groups = "drop"
  )

print(as.data.frame(national_avg))

# =============================================================================
# 4. 可視化
# =============================================================================

cat("\n=== グラフ作成 ===\n")

class_name_short <- if (TARGET_CODE == "M001") "体外照射" else TARGET_CODE

# --- 4a. 都道府県別 人口10万人あたり （最新年度、横棒グラフ） ---
plot_data_bar <- merged |>
  filter(year == latest_year) |>
  mutate(pref_name = factor(pref_name, levels = rev(pref_names)))

# 全国平均線
nat_avg_latest <- national_avg |> filter(year == latest_year) |> pull(avg_per_100k)

g1 <- ggplot(plot_data_bar, aes(x = pref_name, y = count_per_100k)) +
  geom_col(fill = "steelblue") +
  geom_hline(yintercept = nat_avg_latest, color = "red", linetype = "dashed",
             linewidth = 0.7) +
  annotate("text", x = 5, y = nat_avg_latest + 50,
           label = sprintf("全国平均: %.0f", nat_avg_latest),
           color = "red", size = 3, hjust = 0) +
  coord_flip() +
  scale_y_continuous(labels = scales::comma) +
  labs(
    title = sprintf("%s(%s) 人口10万人あたり算定回数 (%d年度)",
                     TARGET_CODE, class_name_short, latest_year),
    subtitle = "データ: NDB Open Data / 総務省人口推計",
    x = NULL, y = "人口10万人あたり算定回数"
  ) +
  theme_minimal(base_family = "HiraginoSans-W3") +
  theme(axis.text.y = element_text(size = 7))

ggsave(file.path(output_dir, sprintf("%s_percapita_pref_%d.png", TARGET_CODE, latest_year)),
       g1, width = 10, height = 12, dpi = 150)
cat(sprintf("  都道府県別人口あたり: %s_percapita_pref_%d.png\n", TARGET_CODE, latest_year))

# --- 4b. 年度推移（全国平均） ---
g2 <- ggplot(national_avg, aes(x = year, y = avg_per_100k)) +
  geom_line(color = "steelblue", linewidth = 1) +
  geom_point(color = "steelblue", size = 2.5) +
  scale_x_continuous(breaks = 2014:2023) +
  labs(
    title = sprintf("%s(%s) 人口10万人あたり算定回数 全国推移",
                     TARGET_CODE, class_name_short),
    subtitle = "データ: NDB Open Data / 総務省人口推計",
    x = "年度", y = "人口10万人あたり算定回数"
  ) +
  theme_minimal(base_family = "HiraginoSans-W3") +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

ggsave(file.path(output_dir, sprintf("%s_percapita_national_trend.png", TARGET_CODE)),
       g2, width = 10, height = 6, dpi = 150)
cat(sprintf("  全国推移: %s_percapita_national_trend.png\n", TARGET_CODE))

# --- 4c. 上位・下位5都道府県の年度推移 ---
rank_latest <- merged |>
  filter(year == latest_year) |>
  arrange(desc(count_per_100k))

top5  <- head(rank_latest$pref_name, 5)
bot5  <- tail(rank_latest$pref_name, 5)
highlight_prefs <- c(top5, bot5)

trend_highlight <- merged |>
  filter(pref_name %in% highlight_prefs) |>
  mutate(group = ifelse(pref_name %in% top5, "上位5", "下位5"))

g3 <- ggplot(trend_highlight,
             aes(x = year, y = count_per_100k, color = pref_name)) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 1.5) +
  facet_wrap(~ group, scales = "free_y") +
  scale_x_continuous(breaks = 2014:2023) +
  labs(
    title = sprintf("%s(%s) 人口10万人あたり 上位5/下位5都道府県の年度推移",
                     TARGET_CODE, class_name_short),
    subtitle = "データ: NDB Open Data / 総務省人口推計",
    x = "年度", y = "人口10万人あたり算定回数", color = "都道府県"
  ) +
  theme_minimal(base_family = "HiraginoSans-W3") +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

ggsave(file.path(output_dir, sprintf("%s_percapita_top_bottom5.png", TARGET_CODE)),
       g3, width = 14, height = 6, dpi = 150)
cat(sprintf("  上位/下位5推移: %s_percapita_top_bottom5.png\n", TARGET_CODE))

# --- 4d. ヒートマップ（全都道府県 × 全年度） ---
heatmap_data <- merged |>
  mutate(pref_name = factor(pref_name, levels = rev(pref_names)))

g4 <- ggplot(heatmap_data, aes(x = factor(year), y = pref_name, fill = count_per_100k)) +
  geom_tile(color = "white", linewidth = 0.3) +
  scale_fill_viridis_c(option = "C", labels = scales::comma,
                       name = "人口10万人\nあたり") +
  labs(
    title = sprintf("%s(%s) 人口10万人あたり算定回数 ヒートマップ",
                     TARGET_CODE, class_name_short),
    subtitle = "データ: NDB Open Data / 総務省人口推計",
    x = "年度", y = NULL
  ) +
  theme_minimal(base_family = "HiraginoSans-W3") +
  theme(axis.text.y = element_text(size = 6.5),
        axis.text.x = element_text(angle = 45, hjust = 1))

ggsave(file.path(output_dir, sprintf("%s_percapita_heatmap.png", TARGET_CODE)),
       g4, width = 10, height = 12, dpi = 150)
cat(sprintf("  ヒートマップ: %s_percapita_heatmap.png\n", TARGET_CODE))

# =============================================================================
# 5. CSV出力
# =============================================================================

cat("\n=== CSV出力 ===\n")

# 人口10万人あたり ワイド形式
write.csv(percapita_wide,
          file.path(output_dir, sprintf("%s_percapita_wide.csv", TARGET_CODE)),
          row.names = FALSE, fileEncoding = "UTF-8")
cat(sprintf("  %s_percapita_wide.csv\n", TARGET_CODE))

# 詳細（人口含む）
detail_out <- merged |>
  select(pref_code, pref_name, year, total_count, population, count_per_100k) |>
  arrange(year, pref_code)

write.csv(detail_out,
          file.path(output_dir, sprintf("%s_percapita_detail.csv", TARGET_CODE)),
          row.names = FALSE, fileEncoding = "UTF-8")
cat(sprintf("  %s_percapita_detail.csv\n", TARGET_CODE))

# 人口データ
write.csv(pop_combined |> select(pref_code, year, population_1000, population),
          file.path(data_dir, "population_by_pref_year.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")
cat("  population_by_pref_year.csv\n")

cat("\n=== 処理完了 ===\n")
